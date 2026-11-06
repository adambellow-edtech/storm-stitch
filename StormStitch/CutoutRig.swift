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
    /// A foot lifted past this switches to its kicked drawing.
    static let kickAt: CGFloat = 0.3

    /// Running away from the camera. t goes 0 to 1 over one full cycle, which is two steps.
    static func run(_ t: CGFloat) -> [String: PartPose] {
        let p = 2 * .pi * t
        let s = sin(p)
        let liftL = max(0, s)
        let liftR = max(0, -s)
        let bob = 7 * abs(s)
        let sway = 3 * s

        func foot(_ lift: CGFloat, side: CGFloat) -> PartPose {
            if lift > CutoutRig.kickAt {
                // Kicked back toward the camera: the bent leg with its sole showing, rising off the ground.
                return PartPose(dy: 27.5 * lift, degrees: side * 6 * lift, variant: "kick")
            }
            // Planted, or just leaving the ground: a small rise as the heel peels up.
            return PartPose(dy: 15 * lift)
        }

        func arm(_ forward: CGFloat, side: CGFloat) -> PartPose {
            // From behind, an arm swinging forward moves away from you: it rises, shrinks and tucks in.
            // Swinging back, it comes toward you: it drops, grows and swings out.
            PartPose(dy: 8 * forward, degrees: side * 18 * forward, sx: 1 - 0.1 * forward, sy: 1 - 0.1 * forward)
        }

        return [
            "foot-l": foot(liftL, side: -1),
            "foot-r": foot(liftR, side: 1),
            // The arm on the same side as the kicking foot swings forward.
            "arm-l": arm(s, side: 1),
            "arm-r": arm(-s, side: -1),
            // The tuft lags behind the body's sway, so it flops.
            "sprout": PartPose(dy: bob * 0.5, degrees: -sway * 0.6 + 12 * sin(p - 1.1)),
            "body": PartPose(dy: bob, degrees: sway, sx: 1 - 0.02 * abs(cos(p)), sy: 1 + 0.025 * abs(s))
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
