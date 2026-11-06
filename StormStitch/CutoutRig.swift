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
/// Art: "<name>-rig.json" plus one picture per part, "<name>-rig-<picture>.png".
/// The JSON gives each part its pivot (a fraction of its picture, x from the left, y from the bottom),
/// its joint (rig units from the ground under the character's center, y up) and its draw order.
/// A part can list alternate drawings ("variants"), like a foot kicked up showing its sole;
/// a variant can be the mirror image of its picture.
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
            let pivot: [CGFloat]
            let joint: [CGFloat]
            let z: CGFloat
            let variants: [String: Variant]?
        }
        let name: String
        let parts: [Part]
        let height: CGFloat
    }

    /// A drawing a part can show: its picture, size, pivot, and whether it's flipped.
    private struct Look {
        let texture: SKTexture
        let size: CGSize
        let anchor: CGPoint
        let mirrored: Bool
    }

    /// Parts carried by the torso. Anything else (the feet) is placed from the ground.
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

    /// Nil when the character has no rig art yet, so callers can fall back to their painted poses.
    init?(named name: String) {
        guard let url = Bundle.main.url(forResource: "\(name)-rig", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              let body = manifest.parts.first(where: { $0.name == "body" }),
              body.joint.count == 2 else { return nil }
        height = manifest.height
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
            guard part.joint.count == 2, let main = look(part.name, pivot: part.pivot, mirrored: false) else { return nil }
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
            if CutoutRig.torsoParts.contains(part.name) {
                sprite.position = CGPoint(x: joint.x - bodyJoint.x, y: joint.y - bodyJoint.y)
                torso.addChild(sprite)
            } else {
                sprite.position = joint
                addChild(sprite)
            }
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
            if CutoutRig.torsoParts.contains(name) {
                sprite.position = CGPoint(x: joint.x - bodyJoint.x + p.dx, y: joint.y - bodyJoint.y + p.dy)
            } else {
                sprite.position = CGPoint(x: joint.x + p.dx, y: joint.y + p.dy)
                // Seen from behind, a kicked foot comes up toward the camera, in front of the body.
                sprite.zPosition = alt != nil && name.hasPrefix("foot") ? 1 : (baseZ[name] ?? 0)
            }
        }
    }
}

// MARK: Motions for a runner seen from behind
// Part names: body, sprout, arm-l, arm-r, foot-l, foot-r ("l" is the side on the left of the screen).
// Feet have a "kick" variant showing the sole. Distances are rig units for a character about 450 units tall.

extension CutoutRig {
    /// Share of the cycle each foot spends on the ground; the rest is the swing, so there's a short
    /// moment with both feet in the air between steps.
    static let stance: CGFloat = 0.4
    /// Share of the swing that shows the sole. After that the foot reaches forward heel-first to land.
    static let kickUntil: CGFloat = 0.55

    /// 0 below a, 1 above b, an S-curve between.
    static func smooth(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// One foot through a stride. Phase 0 is the foot landing; side -1 is the left foot, 1 the right.
    /// From behind, the sole shows only while the foot is kicked up behind the runner. The drawings swap
    /// at push-off and again mid-swing, while the foot moves fast, each with a quick squash so the swap
    /// reads as a snap rather than a pop.
    static func foot(_ phase: CGFloat, side: CGFloat) -> PartPose {
        let phase = phase.truncatingRemainder(dividingBy: 1)
        if phase < stance {
            // Landing: the foot squashes flat for a moment, then stands.
            let land = 1 - smooth(0, 0.08, phase)
            // Late in the stance the heel peels up as the foot pushes off.
            let peel = smooth(stance * 0.55, stance, phase)
            return PartPose(dy: 7 * peel, sx: 1 + 0.08 * land, sy: 1 - 0.12 * land - 0.08 * peel)
        }
        let u = (phase - stance) / (1 - stance)  // 0 just after push-off, 1 at landing
        // The foot rises fast behind the runner and comes down to land: a smooth arc that peaks early.
        let height = sin(.pi * pow(u, 0.8))
        let rise = 7 + 60 * height - 7 * u
        if u < kickUntil {
            let k = u / kickUntil
            let size = (1.08 - 0.1 * k) * (0.85 + 0.15 * smooth(0, 0.2, k))
            // Kicked back toward the camera: big and tipped up, curling as it rises.
            return PartPose(dy: rise, degrees: side * (22 - 18 * k), sx: size, sy: size, variant: "kick")
        }
        let k = (u - kickUntil) / (1 - kickUntil)
        let size = 0.94 * (0.88 + 0.12 * smooth(0, 0.25, k)) + 0.06 * k
        // Reaching forward to land, heel toward you, a little smaller because it's further away.
        return PartPose(dy: rise, degrees: side * -6 * (1 - k), sx: size, sy: size)
    }

    /// Running away from the camera. t goes 0 to 1 over one full cycle, which is two steps.
    static func run(_ t: CGFloat) -> [String: PartPose] {
        let p = 2 * .pi * t
        // The body is lowest mid-stance (a foot under it) and highest mid-flight, twice a cycle.
        let low = 0.5 + 0.5 * cos(4 * .pi * (t - stance / 2))
        let bob = 8 * (1 - low)
        // Leans over whichever foot is planted.
        let sway = 3 * cos(p - .pi * stance)
        // Arms swing opposite their own leg: forward (away from you) while that leg kicks back.
        let swing = sin(p - .pi * stance)

        func arm(_ forward: CGFloat, side: CGFloat) -> PartPose {
            // From behind, an arm swinging forward moves away from you: it rises, shrinks and tucks in.
            // Swinging back, it comes toward you: it drops, grows and swings out.
            PartPose(dy: 8 * forward, degrees: side * 16 * forward, sx: 1 - 0.09 * forward, sy: 1 - 0.09 * forward)
        }

        // The sprout follows the body a beat late, so it flops and settles.
        let lag: CGFloat = 0.09
        let lowLate = 0.5 + 0.5 * cos(4 * .pi * (t - lag - stance / 2))
        let swayLate = 3 * cos(2 * .pi * (t - lag) - .pi * stance)
        return [
            // Each foot lands once a cycle, half a cycle apart.
            "foot-l": foot(t, side: -1),
            "foot-r": foot(t + 0.5, side: 1),
            "arm-l": arm(swing, side: 1),
            "arm-r": arm(-swing, side: -1),
            "sprout": PartPose(dy: -3 * lowLate, degrees: -swayLate * 3, sx: 1 + 0.05 * lowLate, sy: 1 - 0.08 * lowLate),
            // A little squash on each landing, a little stretch in the air.
            "body": PartPose(dy: bob, degrees: sway,
                             sx: 1 + 0.03 * low - 0.015 * (1 - low), sy: 1 - 0.04 * low + 0.02 * (1 - low))
        ]
    }

    /// A jump, t from 0 at take-off to 1 at landing. The game moves the rig up and down; this only poses it.
    static func jump(_ t: CGFloat) -> [String: PartPose] {
        let up = sin(.pi * t)
        let arms = min(1, t * 4) * (1 - max(0, t - 0.75) * 4)
        let tucked: String? = up > 0.25 ? "kick" : nil
        return [
            // Both legs tuck up with their soles showing.
            "foot-l": PartPose(dy: 20 * up, variant: tucked),
            "foot-r": PartPose(dy: 20 * up, variant: tucked),
            // Arms swing up and out past the leaves, like a cheer.
            "arm-l": PartPose(dx: -15 * arms, dy: 20 * arms, degrees: -125 * arms),
            "arm-r": PartPose(dx: 15 * arms, dy: 20 * arms, degrees: 125 * arms),
            "sprout": PartPose(degrees: 14 * cos(2 * .pi * t)),
            "body": PartPose(sx: 1 - 0.05 * up, sy: 1 + 0.07 * up)
        ]
    }
}
