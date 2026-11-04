import Foundation

/// Every number that shapes how the run feels, adjustable live from the tuning panel.
/// World units: one lane is 1.0 wide, the runner is about 1.0 tall.
final class Tuning: ObservableObject {
    struct Defaults {
        static let startSpeed = 9.0
        static let endSpeed = 15.0
        static let jumpVelocity = 6.2
        static let gravity = 16.0
        static let fallMultiplier = 1.6
        static let laneSwitchTime = 0.12
        static let slideDuration = 0.6
        static let swipeThreshold = 22.0
        static let rowIntervalStart = 1.0
        static let rowIntervalEnd = 0.62
        static let stormStart = 6.0
        static let stormHitPenalty = 2.6
        static let stormRecoverRate = 0.3
        static let runLength = 120.0
    }

    /// Forward speed at the start and end of a run (units per second).
    @Published var startSpeed = Defaults.startSpeed
    @Published var endSpeed = Defaults.endSpeed
    /// Upward speed on jump. Peak height is jumpVelocity squared over twice gravity.
    @Published var jumpVelocity = Defaults.jumpVelocity
    @Published var gravity = Defaults.gravity
    /// Extra gravity while falling, so jumps feel snappy instead of floaty.
    @Published var fallMultiplier = Defaults.fallMultiplier
    @Published var laneSwitchTime = Defaults.laneSwitchTime
    @Published var slideDuration = Defaults.slideDuration
    /// How far a finger must travel (points) before it counts as a swipe instead of a tap.
    @Published var swipeThreshold = Defaults.swipeThreshold
    /// Seconds between hazard rows at the start and end of a run.
    @Published var rowIntervalStart = Defaults.rowIntervalStart
    @Published var rowIntervalEnd = Defaults.rowIntervalEnd
    /// How far behind you the storm starts, how much closer each hit brings it, and how fast it drops back.
    @Published var stormStart = Defaults.stormStart
    @Published var stormHitPenalty = Defaults.stormHitPenalty
    @Published var stormRecoverRate = Defaults.stormRecoverRate
    @Published var runLength = Defaults.runLength
    @Published var hapticsOn = true
    @Published var musicOn = true
    @Published var soundOn = true
    @Published var showFPS = false

    func reset() {
        startSpeed = Defaults.startSpeed
        endSpeed = Defaults.endSpeed
        jumpVelocity = Defaults.jumpVelocity
        gravity = Defaults.gravity
        fallMultiplier = Defaults.fallMultiplier
        laneSwitchTime = Defaults.laneSwitchTime
        slideDuration = Defaults.slideDuration
        swipeThreshold = Defaults.swipeThreshold
        rowIntervalStart = Defaults.rowIntervalStart
        rowIntervalEnd = Defaults.rowIntervalEnd
        stormStart = Defaults.stormStart
        stormHitPenalty = Defaults.stormHitPenalty
        stormRecoverRate = Defaults.stormRecoverRate
        runLength = Defaults.runLength
        hapticsOn = true
        musicOn = true
        soundOn = true
        showFPS = false
    }
}
