import SpriteKit
import UIKit

// The live cast for the opening story: jointed cutout rigs that breathe, wave, flinch, slump and run
// inside the story panels. Every motion is baked once into a table of poses, so playing it back
// each frame is a lookup, not a pile of new dictionaries.

/// A short motion baked at 60 poses a second, plus how far the whole rig lifts off the ground
/// (a fraction of its on-screen height) at each pose.
struct StoryClip {
    let frames: [[String: PartPose]]
    let lifts: [CGFloat]
    let duration: TimeInterval
    let loops: Bool

    /// `pose` gets t from 0 to 1 (a loop's last pose stops just short of 1, so it wraps cleanly).
    init(duration: TimeInterval, loops: Bool, _ pose: (CGFloat) -> ([String: PartPose], CGFloat)) {
        let count = max(2, Int((duration * 60).rounded()))
        var frames: [[String: PartPose]] = []
        var lifts: [CGFloat] = []
        frames.reserveCapacity(count)
        lifts.reserveCapacity(count)
        for i in 0..<count {
            let t = loops ? CGFloat(i) / CGFloat(count) : CGFloat(i) / CGFloat(count - 1)
            let (parts, lift) = pose(t)
            frames.append(parts)
            lifts.append(lift)
        }
        self.frames = frames
        self.lifts = lifts
        self.duration = duration
        self.loops = loops
    }

    /// The pose to show `time` seconds into the clip. A one-shot clip holds its last pose.
    func index(at time: TimeInterval) -> Int {
        let count = frames.count
        let k = max(0, time) / duration
        if loops {
            return Int(k * Double(count)) % count
        }
        return min(count - 1, Int((k * Double(count - 1)).rounded()))
    }
}

/// The story's motions. Front rigs have body (with "blink") and arm-l / arm-r (rest, "wave", "cheer", "slump").
enum StoryMotion {
    /// Standing and breathing, with a blink near the end of each breath cycle.
    static let idle = StoryClip(duration: 3.6, loops: true) { t in
        let breathe = sin(2 * .pi * t)
        let blink = t > 0.86 && t < 0.9
        return ([
            "arm-l": PartPose(degrees: 3 * breathe),
            "arm-r": PartPose(degrees: -3 * breathe),
            "body": PartPose(sx: 1 - 0.012 * breathe, sy: 1 + 0.018 * breathe, variant: blink ? "blink" : nil)
        ], 0)
    }

    /// A hello: the right arm swaps to its wave drawing and waggles, the body leans into it.
    static let wave = StoryClip(duration: 1.6, loops: false) { t in
        let w = CutoutRig.smooth(0, 0.12, t) * (1 - CutoutRig.smooth(0.82, 1, t))
        let breathe = sin(2 * .pi * t * 0.45)
        return ([
            "arm-l": PartPose(degrees: 3 * breathe),
            "arm-r": PartPose(degrees: -3 * breathe + 16 * w * sin(2 * .pi * t * 4), variant: w > 0.4 ? "wave" : nil),
            "body": PartPose(degrees: -3 * w, sx: 1 - 0.012 * breathe, sy: 1 + 0.018 * breathe)
        ], 0.025 * w * (0.5 - 0.5 * cos(2 * .pi * t * 4)))
    }

    /// Two happy hops with both fists pumping.
    static let cheer = StoryClip(duration: 1.2, loops: true) { t in
        (CutoutRig.frontCheer(t), 0)
    }

    /// Thunder! A jump straight up with both arms thrown high, then a squashed landing.
    static let startle = StoryClip(duration: 0.8, loops: false) { t in
        let air: CGFloat = t < 0.5 ? sin(.pi * t / 0.5) : 0
        let land: CGFloat = t >= 0.5 ? sin(.pi * min(1, (t - 0.5) / 0.3)) : 0
        let jitter = 8 * sin(t * 60) * (1 - t)
        let arms: String? = t < 0.7 ? "cheer" : nil
        return ([
            "arm-l": PartPose(degrees: 10 + jitter, variant: arms),
            "arm-r": PartPose(degrees: -10 - jitter, variant: arms),
            "body": PartPose(sx: 1 - 0.06 * air + 0.08 * land, sy: 1 + 0.1 * air - 0.1 * land)
        ], 0.22 * air)
    }

    /// Hunched and shivering, eyes squeezing shut now and then.
    static let tremble = StoryClip(duration: 1.5, loops: true) { t in
        let s = sin(2 * .pi * t * 9)
        let blink = t > 0.3 && t < 0.4
        return ([
            "arm-l": PartPose(degrees: 2 * s),
            "arm-r": PartPose(degrees: -2 * s),
            "body": PartPose(dx: 10 * s, degrees: 1.5 * s, sx: 1.04, sy: 0.95, variant: blink ? "blink" : nil)
        ], 0)
    }

    /// The color is gone: arms hang, the body sags and sways.
    static let slump = StoryClip(duration: 3, loops: true) { t in
        (CutoutRig.frontSlump(t), 0)
    }

    /// Running away from the camera (back-view rigs), two steps per loop.
    static let run = StoryClip(duration: 0.48, loops: true) { t in
        (CutoutRig.run(t), 0)
    }

    /// A joyful hop mid-run with arms thrown up.
    static let jump = StoryClip(duration: 0.7, loops: false) { t in
        (CutoutRig.jump(t), 0.32 * sin(.pi * t))
    }
}

/// One rig on a story panel, following a script of beats.
final class StoryActor {
    struct Beat {
        let at: TimeInterval
        let clip: StoryClip
    }

    /// An entrance: the actor moves from one spot to another, growing or shrinking for depth.
    struct Travel {
        let from: CGPoint
        let to: CGPoint
        let start: TimeInterval
        let duration: TimeInterval
        let fromScale: CGFloat
        let toScale: CGFloat
    }

    let rig: CutoutRig
    private let height: CGFloat
    private let baseScale: CGFloat
    private let home: CGPoint
    private let beats: [Beat]
    private let phase: TimeInterval
    private let travel: Travel?
    /// Stitches sewn behind a runner, streaming back toward the camera like the ground going by.
    private let trail: [SKSpriteNode]
    private var sprites: [SKSpriteNode] = []

    /// `height` is the on-screen height in the parent's units; `home` is where its feet stand.
    init(rig: CutoutRig, height: CGFloat, at home: CGPoint, beats: [Beat], phase: TimeInterval = 0,
         travel: Travel? = nil, trail: [SKSpriteNode] = []) {
        self.rig = rig
        self.height = height
        self.baseScale = height / max(rig.height, 1)
        self.home = home
        self.beats = beats
        self.phase = phase
        self.travel = travel
        self.trail = trail
        StoryActor.collectSprites(in: rig, into: &sprites)
    }

    private static func collectSprites(in node: SKNode, into list: inout [SKSpriteNode]) {
        for child in node.children {
            if let sprite = child as? SKSpriteNode { list.append(sprite) }
            collectSprites(in: child, into: &list)
        }
    }

    /// Draws every part of the rig through a shader (the story's color drain).
    func tint(_ shader: SKShader) {
        for sprite in sprites { sprite.shader = shader }
    }

    /// Poses the rig `time` seconds into its panel. `still` (Reduce Motion) holds the last beat's first pose
    /// at the actor's final spot, with no lifts, hops or trail.
    func update(_ time: TimeInterval, still: Bool) {
        guard var beat = beats.first else { return }
        if still {
            beat = beats[beats.count - 1]
        } else {
            for b in beats where b.at <= time { beat = b }
        }
        let clip = beat.clip
        var local = time - beat.at
        if clip.loops { local += phase }
        let i = still ? 0 : clip.index(at: local)
        rig.apply(clip.frames[i])

        var point = home
        var s: CGFloat = 1
        if let travel {
            let k: CGFloat = still ? 1 : CGFloat(max(0, min(1, (time - travel.start) / travel.duration)))
            // Fast out of the gate, easing into place.
            let e = 1 - (1 - k) * (1 - k)
            point = CGPoint(x: travel.from.x + (travel.to.x - travel.from.x) * e,
                            y: travel.from.y + (travel.to.y - travel.from.y) * e)
            s = travel.fromScale + (travel.toScale - travel.fromScale) * e
        }
        rig.setScale(baseScale * s)
        let lift = still ? 0 : clip.lifts[i] * height * s
        rig.position = CGPoint(x: point.x, y: point.y + lift)

        guard !trail.isEmpty else { return }
        let n = CGFloat(trail.count)
        for k in 0..<trail.count {
            let dash = trail[k]
            if still {
                dash.alpha = 0
                continue
            }
            var f = CGFloat(time / 0.36) + CGFloat(k) / n
            f -= floor(f)
            dash.position = CGPoint(x: point.x, y: point.y - 4 * s - f * 80 * s)
            dash.setScale(s * (0.6 + 0.8 * f))
            dash.alpha = 0.9 * (1 - f)
        }
    }
}

/// Grey-out for the story: drains a sprite's color (u_gray 0 to 1), and can flood color back in
/// from a point (u_cx, u_cy in texture coordinates, y up) out to u_radius, measured in picture heights,
/// with a golden seam glowing along the spreading edge (u_seam).
enum StoryTint {
    static func make() -> SKShader {
        let shader = SKShader(source: source)
        shader.uniforms = [
            SKUniform(name: "u_gray", float: 0),
            SKUniform(name: "u_cx", float: 0.5),
            SKUniform(name: "u_cy", float: 0.5),
            SKUniform(name: "u_aspect", float: 1),
            SKUniform(name: "u_radius", float: -1),
            SKUniform(name: "u_seam", float: 0)
        ]
        return shader
    }

    static func set(_ shader: SKShader, _ name: String, _ value: CGFloat) {
        shader.uniformNamed(name)?.floatValue = Float(value)
    }

    private static let source = """
    void main() {
        vec4 c = SKDefaultShading();
        vec2 d = (v_tex_coord - vec2(u_cx, u_cy)) * vec2(u_aspect, 1.0);
        float len = length(d);
        float inside = 1.0 - smoothstep(u_radius - 0.05, u_radius, len);
        float g = u_gray * (1.0 - inside);
        float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
        vec3 rgb = mix(c.rgb, vec3(l), g);
        float seam = smoothstep(u_radius - 0.07, u_radius - 0.035, len) * (1.0 - smoothstep(u_radius - 0.035, u_radius, len));
        rgb += vec3(1.0, 0.79, 0.24) * seam * u_seam * c.a;
        gl_FragColor = vec4(rgb, c.a);
    }
    """
}
