import UIKit

/// Small wrapper so every action has its own, consistent haptic.
final class Haptics {
    var enabled = true

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    init() {
        light.prepare()
        soft.prepare()
        heavy.prepare()
        notify.prepare()
    }

    func lane() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.7)
        light.prepare()
    }

    func jump() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.4)
        light.prepare()
    }

    func land() {
        guard enabled else { return }
        soft.impactOccurred(intensity: 0.35)
        soft.prepare()
    }

    func spool() {
        guard enabled else { return }
        soft.impactOccurred(intensity: 0.6)
        soft.prepare()
    }

    func hit() {
        guard enabled else { return }
        heavy.impactOccurred()
        heavy.prepare()
    }

    func gameOver() {
        guard enabled else { return }
        notify.notificationOccurred(.error)
    }

    func success() {
        guard enabled else { return }
        notify.notificationOccurred(.success)
    }
}
