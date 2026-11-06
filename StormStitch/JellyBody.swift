import SpriteKit

/// A damped spring: kick it with an impulse and it overshoots, swings back, and settles.
struct Spring {
    var value = 0.0
    var velocity = 0.0
    /// Higher is snappier.
    var stiffness: Double
    /// Higher settles faster with less wobble.
    var damping: Double

    mutating func kick(_ impulse: Double) {
        velocity += impulse
    }

    mutating func step(_ dt: Double) {
        // Small fixed steps keep the spring stable even when a frame runs long.
        var remaining = min(dt, 0.1)
        while remaining > 0 {
            let h = min(remaining, 1.0 / 120.0)
            velocity += (-stiffness * value - damping * velocity) * h
            value += velocity * h
            remaining -= h
        }
    }

    mutating func reset() {
        value = 0
        velocity = 0
    }
}

/// Squishy follow-through for the runner, so every monster feels soft and alive:
/// the top of the body lags behind lane changes and swings past, landings wobble,
/// jumps stretch, and pose changes snap with a quick squash.
/// Feet stay planted; only the body above them bends.
struct JellyBody {
    /// Sideways bend of the top of the body, as a fraction of its width.
    var lean = Spring(stiffness: 260, damping: 13)
    /// Squash (negative) and stretch (positive), as a fraction of height.
    var squash = Spring(stiffness: 420, damping: 16)

    /// How hard each kick lands. Reduce Motion halves it.
    var strength: Double { Motion.reduced ? 0.5 : 1 }

    mutating func laneChange(direction: Int) {
        // Moving right leaves the top behind on the left, then it swings past.
        lean.kick(-Double(direction) * 2.6 * strength)
    }

    mutating func jump() { squash.kick(2.8 * strength) }
    mutating func land(hard: Bool) { squash.kick(-(hard ? 3.2 : 2.0) * strength) }
    mutating func poseChanged() { squash.kick(-1.6 * strength) }
    mutating func hit() {
        lean.kick(Double.random(in: 0.5...1) * (Bool.random() ? 3.4 : -3.4) * strength)
        squash.kick(-2.4 * strength)
    }

    mutating func step(_ dt: Double) {
        lean.step(dt)
        squash.step(dt)
        lean.value = max(-0.22, min(0.22, lean.value))
        squash.value = max(-0.3, min(0.3, squash.value))
    }

    mutating func reset() {
        lean.reset()
        squash.reset()
    }

    /// Width and height multipliers that keep the body's volume roughly the same.
    var scale: (x: CGFloat, y: CGFloat) {
        let s = CGFloat(squash.value)
        return (1 - s * 0.6, 1 + s)
    }

    /// Bends the sprite: feet fixed, the middle shifted a little, the top shifted most,
    /// which reads as a soft body rather than a rigid tilt.
    /// `mirrored` is true when the sprite is flipped, so the bend still leans the right way.
    func warp(mirrored: Bool) -> SKWarpGeometryGrid? {
        let bend = Float(lean.value) * (mirrored ? -1 : 1)
        guard abs(bend) > 0.002 else { return nil }
        let source: [vector_float2] = [
            vector_float2(0, 0), vector_float2(1, 0),
            vector_float2(0, 0.5), vector_float2(1, 0.5),
            vector_float2(0, 1), vector_float2(1, 1)
        ]
        let middle = bend * 0.35
        let destination: [vector_float2] = [
            vector_float2(0, 0), vector_float2(1, 0),
            vector_float2(middle, 0.5), vector_float2(1 + middle, 0.5),
            vector_float2(bend, 1), vector_float2(1 + bend, 1)
        ]
        return SKWarpGeometryGrid(columns: 1, rows: 2, sourcePositions: source, destinationPositions: destination)
    }
}
