// FlashAnalysis.swift — measures flashes in a recorded sequence (FX-019-R1, R2; data-model.md
// "FlashReport"). Independent of `FlashEnvelope`'s running state: it takes the whole series, finds
// the transitions, then counts every sliding window by brute force. Used by the acceptance tests on
// the envelope's output and on pixels read back from both renderers, and later by ACC-002 (offline
// preset analysis). Allocates; not for the frame path.

public struct FlashReport: Sendable, Equatable {
    /// Transitions in the whole series.
    public var transitions: Int
    /// The most transitions inside any window.
    public var maxTransitionsPerWindow: Int
    /// Largest per-frame increase and decrease.
    public var maxRise: Double
    public var maxFall: Double
    /// Flashes = transitions ÷ 2 rounded up (a lone transition counts as a flash; FX-019-R2).
    public var maxFlashesPerWindow: Int { (maxTransitionsPerWindow + 1) / 2 }
}

public enum FlashAnalysis {
    /// A transition this much older than the window still counts (frame-time sums are not exact).
    static let windowTolerance = 1e-9

    /// `values[i]` is shown at frame i; `frameTimes[i]` is the time since frame i − 1
    /// (`frameTimes[0]` is ignored). Times are used as given (real time); non-finite values read as 0.
    public static func analyze(_ values: [Double], frameTimes: [Double], threshold: Double, window: Double = 1) -> FlashReport {
        let n = values.count
        guard n > 0 else { return FlashReport(transitions: 0, maxTransitionsPerWindow: 0, maxRise: 0, maxFall: 0) }
        let v = values.map { $0.isFinite ? max($0, 0) : 0 }
        var time = [Double](repeating: 0, count: n)
        for i in 1..<max(n, 1) { time[i] = time[i - 1] + max(i < frameTimes.count ? frameTimes[i] : 0, 0) }

        var maxRise = 0.0, maxFall = 0.0
        for i in 1..<max(n, 1) {
            let d = v[i] - v[i - 1]
            if d > 0 { maxRise = max(maxRise, d) } else { maxFall = max(maxFall, -d) }
        }

        // Transitions: hysteresis from the extreme of the previous leg.
        var at: [Double] = []
        var direction = 0           // 0 none, 1 rising, −1 falling
        var low = v[0], high = v[0]
        for i in 1..<max(n, 1) {
            let x = v[i]
            switch direction {
            case 0:
                if x >= low + threshold { direction = 1; high = x; at.append(time[i]) }
                else if x <= high - threshold { direction = -1; low = x; at.append(time[i]) }
                else { low = min(low, x); high = max(high, x) }
            case 1:
                if x > high { high = x }
                else if x <= high - threshold { direction = -1; low = x; at.append(time[i]) }
            default:
                if x < low { low = x }
                else if x >= low + threshold { direction = 1; high = x; at.append(time[i]) }
            }
        }

        // Every window that ends at a transition: (t − window, t].
        var worst = 0
        for (j, end) in at.enumerated() {
            var k = j
            while k > 0 && end - at[k - 1] < window + windowTolerance { k -= 1 }
            worst = max(worst, j - k + 1)
        }
        return FlashReport(transitions: at.count, maxTransitionsPerWindow: worst, maxRise: maxRise, maxFall: maxFall)
    }
}
