import SpriteKit

/// One frame's adjustment for a part: a move (rig units, y up), a turn (degrees, counterclockwise)
/// and a squash or stretch.
struct PartPose {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var degrees: CGFloat = 0
    var sx: CGFloat = 1
    var sy: CGFloat = 1
}

/// A character built from separately painted parts (body, arms, feet, a top tuft) that turn on joints,
/// so one painting gives a full run cycle, jump and more, all animated in code.
///
/// Art: "<name>-rig.json" plus one picture per part, "<name>-rig-<part>.png".
/// The JSON gives each part its pivot (a fraction of its picture, x from the left, y from the bottom),
/// its joint (rig units from the ground under the character's center, y up) and its draw order.
/// Arms and the tuft ride on the torso, so they sway and bob with the body; feet stay on the ground.
final class CutoutRig: SKNode {
    private struct Manifest: Decodable {
        struct Part: Decodable {
            let name: String
            let pivot: [CGFloat]
            let joint: [CGFloat]
            let z: CGFloat
        }
        let name: String
        let parts: [Part]
        let height: CGFloat
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
        for part in manifest.parts {
            guard part.pivot.count == 2, part.joint.count == 2,
                  let image = artImage("\(name)-rig-\(part.name)") else { return nil }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            let sprite = SKSpriteNode(texture: texture, size: image.size)
            sprite.anchorPoint = CGPoint(x: part.pivot[0], y: part.pivot[1])
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
            guard let joint = joints[name] else { continue }
            let p = pose[name] ?? PartPose()
            sprite.xScale = p.sx
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
                // Seen from behind, a foot kicked up toward the camera passes in front of the body.
                sprite.zPosition = name.hasPrefix("foot") && p.dy > 9 ? 1 : (baseZ[name] ?? 0)
            }
        }
    }
}

// MARK: Motions for a runner seen from behind
// Part names: body, sprout, arm-l, arm-r, foot-l, foot-r ("l" is the side on the left of the screen).
// Distances are rig units for a character about 470 units tall; scale them for very different builds.

extension CutoutRig {
    /// Running away from the camera. t goes 0 to 1 over one full cycle, which is two steps.
    static func run(_ t: CGFloat) -> [String: PartPose] {
        let p = 2 * .pi * t
        let liftL = max(0, sin(p))
        let liftR = max(0, -sin(p))
        let bob = 7 * abs(sin(p))
        let sway = 3.5 * sin(p)
        return [
            // A lifted foot kicks up toward the camera: it rises, tips, and its sole widens a little.
            "foot-l": PartPose(dx: 3 * liftL, dy: 42.5 * liftL, degrees: -12 * liftL, sx: 1 + 0.1 * liftL, sy: 1 - 0.12 * liftL),
            "foot-r": PartPose(dx: -3 * liftR, dy: 42.5 * liftR, degrees: 12 * liftR, sx: 1 + 0.1 * liftR, sy: 1 - 0.12 * liftR),
            // Arms pump opposite the feet.
            "arm-l": PartPose(dy: -bob * 0.3, degrees: 30 * sin(p)),
            "arm-r": PartPose(dy: -bob * 0.3, degrees: 30 * sin(p)),
            // The tuft lags behind the body's sway, so it flops.
            "sprout": PartPose(dy: bob, degrees: -sway * 0.6 + 12 * sin(p - 1.1)),
            "body": PartPose(dy: bob, degrees: sway, sx: 1 - 0.02 * abs(cos(p)), sy: 1 + 0.025 * abs(sin(p)))
        ]
    }

    /// A jump, t from 0 at take-off to 1 at landing. The game moves the rig up and down; this only poses it.
    static func jump(_ t: CGFloat) -> [String: PartPose] {
        let up = sin(.pi * t)
        let arms = 75 * min(1, t * 4) * (1 - max(0, t - 0.75) * 4)
        let tuck = 22.5 * up
        return [
            "foot-l": PartPose(dx: 5 * up, dy: tuck, degrees: -18 * up),
            "foot-r": PartPose(dx: -5 * up, dy: tuck, degrees: 18 * up),
            // Arms shoot up and out past the leaves, like a cheer.
            "arm-l": PartPose(dx: -0.45 * arms, dy: 0.25 * arms, degrees: -arms * 1.1),
            "arm-r": PartPose(dx: 0.45 * arms, dy: 0.25 * arms, degrees: arms * 1.1),
            "sprout": PartPose(degrees: 14 * cos(2 * .pi * t)),
            "body": PartPose(sx: 1 - 0.05 * up, sy: 1 + 0.07 * up)
        ]
    }
}
