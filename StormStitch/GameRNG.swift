import Foundation

/// A small seeded random generator (SplitMix64). The same seed gives the same run,
/// which is what makes the Daily Storm and friend challenges fair: everyone gets
/// the identical course. Works with Swift's `using:` APIs, e.g. `lanes.shuffled(using: &rng)`.
struct GameRNG: RandomNumberGenerator {
    private(set) var state: UInt64

    init(seed: UInt64) {
        state = seed ^ 0x5DEE_CE66_D1CE_4E5B
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A random seed for ordinary runs.
    static func freshSeed() -> UInt64 {
        UInt64.random(in: 1...UInt64.max)
    }
}
