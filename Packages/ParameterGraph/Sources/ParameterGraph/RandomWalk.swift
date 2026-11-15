// RandomWalk.swift — MOD-016: the ease between two seeded targets of a random walk oscillator (MOD-016-R4 to R6;
// specs/253-mod-016-random-walk, research MOD-016-D2, D3, contract W3, W5).
//
// e(φ) = (1 − s)·φ + s·(6φ⁵ − 15φ⁴ + 10φ³): a blend of a straight line and the quintic "smootherstep". Both parts rise
// monotonically from 0 to 1, so the walk always lies between its two targets (no overshoot: the bounds hold by
// construction). Its slope is at most (1 − s) + s·15/8, which bounds the change between frames. Plain Swift,
// Foundation-free (Linux).

/// The ease and its slope bound for `LFOShape.randomWalk`.
public enum RandomWalk {
    /// The steepest slope of the quintic part, 15/8 at φ = ½.
    public static let quinticMaximumSlope = 1.875

    /// The eased fraction (0…1) of the way from one target to the next at phase `phi` (0…1); a non-finite phase reads 0.
    public static func ease(_ phi: Double, smoothness: Double) -> Double {
        guard phi.isFinite, smoothness.isFinite else { return 0 }
        let x: Double = min(max(phi, 0), 1)
        let s: Double = min(max(smoothness, 0), 1)
        let inner: Double = x * (6 * x - 15) + 10
        let quintic: Double = x * x * x * inner
        let eased: Double = (1 - s) * x + s * quintic
        return min(max(eased, 0), 1)
    }

    /// The largest slope of `ease` for `smoothness` (per cycle): (1 − s) + 1.875·s.
    public static func maximumSlope(smoothness: Double) -> Double {
        let s: Double = min(max(smoothness, 0), 1)
        return (1 - s) + s * quinticMaximumSlope
    }
}
