import SpriteKit
import UIKit

/// Easing curves and the player's motion preference, shared by every screen.
enum Motion {
    /// True when Reduce Motion is on in Settings > Accessibility > Motion.
    /// Shakes and flashes get gentler, and menus fade instead of bouncing.
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// How much of a shake or flash to keep under Reduce Motion.
    static let reducedStrength: CGFloat = 0.3

    /// Overshoots about 10% past the target, then settles back. For things that pop into place.
    static func easeOutBack(_ t: Float) -> Float {
        let c1: Float = 1.70158
        let c3 = c1 + 1
        let u = t - 1
        return 1 + c3 * u * u * u + c1 * u * u
    }

    /// Starts fast and glides to a stop. For slides and count-ups.
    static func easeOutCubic(_ t: Float) -> Float {
        let u = 1 - t
        return 1 - u * u * u
    }
}

extension SKAction {
    /// Pops past the target and settles back (ease out back).
    func overshoot() -> SKAction {
        timingFunction = Motion.easeOutBack
        return self
    }

    /// Starts fast and glides to a stop (ease out cubic).
    func glide() -> SKAction {
        timingFunction = Motion.easeOutCubic
        return self
    }

    /// Run on an SKLabelNode: counts it up from zero to its final value, easing to a stop.
    static func countUp(to value: Int, duration: TimeInterval, format: @escaping (Int) -> String) -> SKAction {
        .customAction(withDuration: duration) { node, elapsed in
            guard let label = node as? SKLabelNode else { return }
            let t = Float(min(1, elapsed / CGFloat(max(duration, 0.001))))
            label.text = format(Int((Float(value) * Motion.easeOutCubic(t)).rounded()))
        }
    }
}
