import SpriteKit

/// One frame's adjustment for a part: a move (rig units, y up), a turn (degrees, counterclockwise),
/// a squash or stretch, and which drawing to show (nil for the part's own picture).
struct PartPose {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var degrees: CGFloat = 0
    var sx: CGFloat = 1
    var sy: CGFloat = 1
    var variant: String? = nil
}

/// A character built from separately painted parts (body, arms, feet, a top tuft) that turn on joints,
/// so one set of paintings gives a full run cycle, jump and more, all animated in code.
///
/// Art: "<name>-rig.json" plus pictures named "<name>-rig-<picture>.png".
/// The JSON gives each part its picture, pivot (a fraction of the picture, x from the left, y from the bottom),
/// joint (rig units from the ground under the character's center, y up) and draw order.
/// Hands and feet swap between a few drawings as they move ("variants": planted, push-off, kicked...),
/// the way cutout animation is done; a variant can be the mirror image of its picture.
/// "inFront" names the variants that draw in front of the body, like a foot kicked up toward the camera.
/// Arms and the tuft ride on the torso, so they sway and bob with the body; feet stand on the ground.
final class CutoutRig: SKNode {
    private struct Manifest: Decodable {
        struct Variant: Decodable {
            let image: String
            let pivot: [CGFloat]
            let mirror: Bool?
        }
        struct Part: Decodable {
            let name: String
            let image: String?
            let pivot: [CGFloat]
            let joint: [CGFloat]
            let z: CGFloat
            let variants: [String: Variant]?
            /// Another part this one hangs from (a spark on a fuse): it follows that part's move and turn.
            let parent: String?
            /// Whether it rides the torso's bob and sway. Missing means the standard set below.
            let torso: Bool?
        }
        let name: String
        let parts: [Part]
        let height: CGFloat
        let inFront: [String]?
    }

    /// A drawing a part can show: its picture, size, pivot, and whether it's flipped.
    private struct Look {
        let texture: SKTexture
        let size: CGSize
        let anchor: CGPoint
        let mirrored: Bool
    }

    /// Parts carried by the torso when the JSON doesn't say. Anything else (the feet) stands on the ground.
    static let torsoParts: Set<String> = ["body", "arm-l", "arm-r", "sprout"]

    /// From the ground to the top of the tallest part, in rig units. Scale the rig by target / height.
    let height: CGFloat

    private let torso = SKNode()
    private let bodyJoint: CGPoint
    private var sprites: [String: SKSpriteNode] = [:]
    private var joints: [String: CGPoint] = [:]
    private var baseZ: [String: CGFloat] = [:]
    private var looks: [String: [String: Look]] = [:]
    private var defaultLooks: [String: Look] = [:]
    private var inFront: Set<String> = []
    private var parents: [String: String] = [:]
    private var onTorso: Set<String> = []

    /// Nil when the character has no rig art yet, so callers can fall back to their painted poses.
    init?(named name: String) {
        guard let url = Bundle.main.url(forResource: "\(name)-rig", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              let body = manifest.parts.first(where: { $0.name == "body" }),
              body.joint.count == 2 else { return nil }
        height = manifest.height
        inFront = Set(manifest.inFront ?? ["kick"])
        bodyJoint = CGPoint(x: body.joint[0], y: body.joint[1])
        super.init()
        torso.position = bodyJoint
        addChild(torso)

        func look(_ picture: String, pivot: [CGFloat], mirrored: Bool) -> Look? {
            guard pivot.count == 2, let image = artImage("\(name)-rig-\(picture)") else { return nil }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            return Look(texture: texture, size: image.size, anchor: CGPoint(x: pivot[0], y: pivot[1]), mirrored: mirrored)
        }

        for part in manifest.parts {
            guard part.joint.count == 2,
                  let main = look(part.image ?? part.name, pivot: part.pivot, mirrored: false) else { return nil }
            defaultLooks[part.name] = main
            for (variant, v) in part.variants ?? [:] {
                if let alt = look(v.image, pivot: v.pivot, mirrored: v.mirror ?? false) {
                    looks[part.name, default: [:]][variant] = alt
                }
            }
            let sprite = SKSpriteNode(texture: main.texture, size: main.size)
            sprite.anchorPoint = main.anchor
            sprite.zPosition = part.z
            let joint = CGPoint(x: part.joint[0], y: part.joint[1])
            joints[part.name] = joint
            baseZ[part.name] = part.z
            sprites[part.name] = sprite
            if let parent = part.parent {
                parents[part.name] = parent
            } else if part.torso ?? CutoutRig.torsoParts.contains(part.name) {
                onTorso.insert(part.name)
                sprite.position = CGPoint(x: joint.x - bodyJoint.x, y: joint.y - bodyJoint.y)
                torso.addChild(sprite)
            } else {
                sprite.position = joint
                addChild(sprite)
            }
        }
        // Hang each child part on its parent's sprite, positioned from the parent's pivot.
        for (name, parent) in parents {
            guard let sprite = sprites[name], let host = sprites[parent],
                  let joint = joints[name], let hostJoint = joints[parent] else { return nil }
            sprite.position = CGPoint(x: joint.x - hostJoint.x, y: joint.y - hostJoint.y)
            host.addChild(sprite)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Poses every part. `lean` tips the whole torso (radians, positive leans left), for follow-through.
    func apply(_ pose: [String: PartPose], lean: CGFloat = 0) {
        let body = pose["body"] ?? PartPose()
        torso.position = CGPoint(x: bodyJoint.x + body.dx, y: bodyJoint.y + body.dy)
        torso.zRotation = body.degrees * .pi / 180 + lean
        for (name, sprite) in sprites {
            guard let joint = joints[name], let main = defaultLooks[name] else { continue }
            let p = pose[name] ?? PartPose()
            let alt = p.variant.flatMap { looks[name]?[$0] }
            let shown = alt ?? main
            if sprite.texture !== shown.texture {
                sprite.texture = shown.texture
                sprite.size = shown.size
                sprite.anchorPoint = shown.anchor
            }
            // Flipping across the pivot draws the mirror image turning on the mirrored pivot.
            sprite.xScale = p.sx * (shown.mirrored ? -1 : 1)
            sprite.yScale = p.sy
            if name == "body" {
                // The torso already carries the body's move and turn; the sprite only squashes.
                continue
            }
            sprite.zRotation = p.degrees * .pi / 180
            if let parent = parents[name], let hostJoint = joints[parent] {
                sprite.position = CGPoint(x: joint.x - hostJoint.x + p.dx, y: joint.y - hostJoint.y + p.dy)
            } else if onTorso.contains(name) {
                sprite.position = CGPoint(x: joint.x - bodyJoint.x + p.dx, y: joint.y - bodyJoint.y + p.dy)
            } else {
                sprite.position = CGPoint(x: joint.x + p.dx, y: joint.y + p.dy)
                // Seen from behind, a kicked foot comes up toward the camera, in front of the body.
                let front = alt != nil && p.variant.map { inFront.contains($0) } == true
                sprite.zPosition = front ? 1 : (baseZ[name] ?? 0)
            }
        }
    }
}

// MARK: Motions for a runner seen from behind
// Part names: body, sprout, arm-l, arm-r, foot-l, foot-r ("l" is the side on the left of the screen).
// Feet swap between "push", "kick" and "pass" drawings (planted is the default); arms between
// "fwd", "back" and "up" (hanging is the default). Distances are rig units for a character about 450 tall.

extension CutoutRig {
    /// 0 below a, 1 above b, an S-curve between.
    static func smooth(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Size just after a drawing swaps in: starts at 90% and settles to full, so the swap reads as a snap.
    static func snap(_ t: CGFloat, length: CGFloat = 0.25) -> CGFloat {
        0.9 + 0.1 * smooth(0, length, t)
    }

    /// One foot through a stride, swapping drawings: planted, push-off, kicked up, passing forward.
    /// Phase 0 is the foot landing; side -1 is the left foot, 1 the right.
    static func foot(_ phase: CGFloat, side: CGFloat) -> PartPose {
        let phase = phase.truncatingRemainder(dividingBy: 1)
        if phase < 0.3 {
            // Planted. Landing squashes it flat for a moment.
            let land = 1 - smooth(0, 0.08, phase)
            return PartPose(sx: 1 + 0.1 * land, sy: 1 - 0.14 * land)
        }
        if phase < 0.42 {
            let k = (phase - 0.3) / 0.12
            let s = snap(k)
            // Push-off: the heel rolls up, the foot pressing into the ground.
            return PartPose(dy: 2 * k, degrees: side * -4 * k, sx: s, sy: s, variant: "push")
        }
        if phase < 0.68 {
            let k = (phase - 0.42) / 0.26
            let s = snap(k)
            // Kicked up behind the runner, sole to the camera, rising in an arc.
            return PartPose(dy: 4 + 17 * sin(.pi * k), degrees: side * (8 - 12 * k), sx: s, sy: s, variant: "kick")
        }
        let k = (phase - 0.68) / 0.32
        let s = snap(k)
        // Passing forward under the body to land. The drawing is already lifted; it drops to the ground.
        return PartPose(dy: 3 - 5 * smooth(0.4, 1, k), degrees: side * 4 * (1 - k), sx: s, sy: s, variant: "pass")
    }

    /// An arm's swing, from -1 (back toward you) to 1 (forward, away from you), swapping drawings.
    static func arm(_ forward: CGFloat, side: CGFloat) -> PartPose {
        var variant: String? = nil
        var base: CGFloat = 0
        if forward > 0.45 {
            variant = "fwd"
            base = 0.7
        } else if forward < -0.45 {
            variant = "back"
            base = -0.7
        }
        // Within each drawing the arm keeps turning a little, so the swing never stops.
        return PartPose(dy: 3 * forward, degrees: side * 10 * (forward - base), variant: variant)
    }

    /// Running away from the camera. t goes 0 to 1 over one full cycle, which is two steps.
    static func run(_ t: CGFloat) -> [String: PartPose] {
        let stanceMid: CGFloat = 0.15
        let p = 2 * .pi * t
        // Lowest when a foot is planted under the body, highest in between steps.
        let low = 0.5 + 0.5 * cos(4 * .pi * (t - stanceMid))
        let bob = 8 * (1 - low)
        let sway = 3 * cos(p - 2 * .pi * stanceMid)
        // Each arm swings opposite its own leg: forward while that leg kicks back.
        let swing = sin(p - 2 * .pi * 0.3)
        // The sprout follows the body a beat late, so it flops and settles.
        let lag: CGFloat = 0.09
        let lowLate = 0.5 + 0.5 * cos(4 * .pi * (t - lag - stanceMid))
        let swayLate = 3 * cos(2 * .pi * (t - lag - stanceMid))
        return extras(t).merging([
            "foot-l": foot(t, side: -1),
            "foot-r": foot(t + 0.5, side: 1),
            "arm-l": arm(swing, side: 1),
            "arm-r": arm(-swing, side: -1),
            "sprout": PartPose(dy: -3 * lowLate, degrees: -swayLate * 3, sx: 1 + 0.05 * lowLate, sy: 1 - 0.08 * lowLate),
            // A little squash on each landing, a little stretch in the air.
            "body": PartPose(dy: bob, degrees: sway,
                             sx: 1 + 0.03 * low - 0.015 * (1 - low), sy: 1 - 0.04 * low + 0.02 * (1 - low))
        ]) { _, own in own }
    }

    /// Motion for extra parts some monsters have. Parts a monster doesn't have are simply ignored.
    static func extras(_ t: CGFloat) -> [String: PartPose] {
        // Fizz's spark flickers: a quick pulse and spin, faster than the steps.
        let pulse = 0.5 + 0.5 * sin(2 * .pi * t * 3)
        let flicker = 0.75 + 0.4 * pulse
        let flap = sin(4 * .pi * t)
        let sway = sin(2 * .pi * t)
        let flapDrawing: String? = flap > 0.4 ? "up" : (flap < -0.4 ? "down" : nil)
        return [
            "spark": PartPose(degrees: 40 * sin(2 * .pi * t * 2), sx: flicker, sy: flicker),
            // Gobbler's tail fan wiggles a beat behind the steps.
            "tail": PartPose(degrees: 3 * sin(2 * .pi * (t - 0.12))),
            // Comet's antlers rock a beat behind the body; his scarf end flaps twice a cycle.
            "antlers": PartPose(degrees: -4 * cos(2 * .pi * (t - 0.24))),
            "scarf": PartPose(degrees: 8 * sin(4 * .pi * t), variant: sin(4 * .pi * t) > 0 ? "flap" : nil),
            // Stickle's antennae bob twice a cycle, a beat behind the body.
            "antenna-l": PartPose(degrees: 8 * sin(4 * .pi * (t - 0.08))),
            "antenna-r": PartPose(degrees: -8 * sin(4 * .pi * (t - 0.08))),
            // Origo's wings flap twice a cycle, swapping between up, level and down.
            "wing-l": PartPose(degrees: -6 * flap, variant: flapDrawing),
            "wing-r": PartPose(degrees: 6 * flap, variant: flapDrawing),
            // Blotch's ooze skirt ripples side to side, and drops flick off his sides.
            "skirt": PartPose(sx: 1 + 0.05 * abs(sway), sy: 1 - 0.06 * abs(sway),
                              variant: sway > 0.45 ? "left" : (sway < -0.45 ? "right" : nil)),
            "drop-l": flick(t, side: -1),
            "drop-r": flick(t + 0.5, side: 1),
            // Wickling's tassel swings under him like a pendulum, a beat behind.
            "tassel": PartPose(degrees: 10 * sin(2 * .pi * (t - 0.15))),
            // Thundercap's bolt flickers to a new drawing four times a cycle; his sparkles twinkle.
            "bolt": PartPose(degrees: 6 * sin(8 * .pi * t), variant: boltDrawings[Int(4 * (t - floor(t))) % 4]),
            "spark-a": twinkle(t),
            "spark-b": twinkle(t + 0.5),
            // Squidge's flag flaps between its two drawings on top of his boat hat.
            "flag": PartPose(degrees: 4 * sin(4 * .pi * t), variant: sin(4 * .pi * t) > 0 ? "flap" : nil)
        ].merging(tripod(t)) { own, _ in own }
    }

    static let boltDrawings: [String?] = [nil, "long", "fork", "long"]

    /// A sparkle that bobs, spins and pulses in size.
    static func twinkle(_ t: CGFloat) -> PartPose {
        let k = 0.5 + 0.5 * sin(4 * .pi * t)
        let size = 0.4 + 0.7 * k
        return PartPose(dy: 10 * sin(2 * .pi * t), degrees: 90 * (t - floor(t)), sx: size, sy: size)
    }

    /// A drop flung off Blotch's side once a cycle, arcing out and shrinking away.
    static func flick(_ t: CGFloat, side: CGFloat) -> PartPose {
        let k = t - floor(t)
        let size = max(0.001, 1 - pow(k, 1.5))
        return PartPose(dx: side * 80 * k, dy: 60 * sin(.pi * k) - 30 * k, degrees: side * 200 * k, sx: size, sy: size)
    }

    /// Stickle's six legs: left front and back step with the right middle, then the other three.
    static func tripod(_ t: CGFloat, allUp: Bool = false) -> [String: PartPose] {
        let s = sin(2 * .pi * t)
        var legs: [String: PartPose] = [:]
        for n in 1...3 {
            for (side, sign) in [("l", CGFloat(1)), ("r", CGFloat(-1))] {
                let groupA = (side == "l") == (n != 2)
                let lift = max(0, groupA ? s : -s)
                let up = allUp || lift > 0.25
                legs["leg-\(side)\(n)"] = PartPose(dy: 7 * lift, degrees: sign * 6 * lift, variant: up ? "up" : nil)
            }
        }
        return legs
    }

    /// Ducking under a ruler, t from 0 (dropping into it) to 1 (popping back up).
    /// Arms sweep back, feet tuck, the body sinks and leans forward, top pieces flatten.
    static func slide(_ t: CGFloat) -> [String: PartPose] {
        let down = smooth(0, 0.15, t) * (1 - smooth(0.85, 1, t))
        let tuck: String? = down > 0.3 ? "pass" : nil
        var pose = extras(t * 2)
        pose.merge([
            "foot-l": PartPose(dy: -4 * down, variant: tuck),
            "foot-r": PartPose(dy: -4 * down, variant: tuck),
            "arm-l": PartPose(dy: -6 * down, degrees: -20 * down, variant: down > 0.3 ? "back" : nil),
            "arm-r": PartPose(dy: -6 * down, degrees: 20 * down, variant: down > 0.3 ? "back" : nil),
            "sprout": PartPose(dy: -3 * down, degrees: -8 * down, sx: 1 + 0.06 * down, sy: 1 - 0.12 * down),
            "body": PartPose(dy: -10 * down, sx: 1 + 0.08 * down, sy: 1 - 0.12 * down)
        ]) { _, own in own }
        return pose
    }

    /// Taking a hit, t from 0 (the impact) to 1 (recovered). Arms fly up, the body jolts and wobbles.
    static func hit(_ t: CGFloat) -> [String: PartPose] {
        let shock = 1 - smooth(0, 1, t)
        let wobble = sin(t * 18) * shock
        var pose = extras(t)
        pose.merge([
            "foot-l": PartPose(dy: 6 * shock, variant: shock > 0.4 ? "push" : nil),
            "foot-r": PartPose(dy: 3 * shock, variant: shock > 0.4 ? "pass" : nil),
            "arm-l": PartPose(dy: 6 * shock, degrees: -30 * wobble, variant: shock > 0.3 ? "up" : nil),
            "arm-r": PartPose(dy: 6 * shock, degrees: 30 * wobble, variant: shock > 0.3 ? "up" : nil),
            "sprout": PartPose(degrees: 25 * wobble),
            "body": PartPose(dy: 4 * shock, degrees: 8 * wobble, sx: 1 - 0.06 * shock, sy: 1 + 0.08 * shock)
        ]) { _, own in own }
        return pose
    }

    /// A jump, t from 0 at take-off to 1 at landing. The game moves the rig up and down; this only poses it.
    static func jump(_ t: CGFloat) -> [String: PartPose] {
        let up = sin(.pi * t)
        let feet: String = t < 0.12 ? "push" : (t < 0.8 ? "kick" : "pass")
        let arms: String? = t < 0.1 ? "back" : (t < 0.85 ? "up" : nil)
        let raise = smooth(0.1, 0.3, t)
        let wobble = 6 * sin(6 * .pi * t) * raise
        var airborne = extras(t).merging(tripod(t, allUp: true)) { _, legs in legs }
        airborne["antenna-l"] = PartPose(degrees: -14 * up)
        airborne["antenna-r"] = PartPose(degrees: 14 * up)
        // Origo spreads his wings and glides.
        airborne["wing-l"] = PartPose(degrees: -4 * up, variant: "glide")
        airborne["wing-r"] = PartPose(degrees: 4 * up, variant: "glide")
        // Blotch stretches up, then lands in a splat; his drops stay put while he's airborne.
        let landing = t > 0.88
        airborne["skirt"] = PartPose(sx: 1 - 0.1 * up + (landing ? 0.15 : 0), sy: 1 + 0.15 * up - (landing ? 0.3 : 0),
                                     variant: landing ? "splat" : nil)
        airborne["drop-l"] = PartPose(sx: 0.001, sy: 0.001)
        airborne["drop-r"] = PartPose(sx: 0.001, sy: 0.001)
        // Thundercap cracks his big zap bolt in the air.
        airborne["bolt"] = PartPose(variant: t > 0.2 && t < 0.8 ? "zap" : "long")
        return airborne.merging([
            "foot-l": PartPose(dy: 5 * up, variant: feet),
            "foot-r": PartPose(dy: 5 * up, variant: feet),
            // Arms wind back, then throw up in a cheer, wobbling a little at the top.
            "arm-l": PartPose(dy: 6 * raise * up, degrees: wobble, variant: arms),
            "arm-r": PartPose(dy: 6 * raise * up, degrees: -wobble, variant: arms),
            "sprout": PartPose(degrees: 14 * cos(2 * .pi * t)),
            "body": PartPose(sx: 1 - 0.05 * up, sy: 1 + 0.07 * up)
        ]) { _, own in own }
    }
}
