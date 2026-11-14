// MonitorBalance.swift — AUD-010: the left/right balance of what In-App Playback plays aloud
// (AUD-010-R1, R2, R7; specs/138-aud-010-channel-balance, data-model.md).
//
// b in −1…+1: −1 full left, 0 centre, +1 full right. The law is a true stereo balance: the near
// channel stays at unity and the opposite one is scaled linearly, left = min(1, 1 − b) and
// right = min(1, 1 + b). Nothing of one channel is moved into the other. The balance acts on the
// monitored output only; the analysis never sees it (AUD-010-R3, InAppPlaybackGraph).
//
// Plain arithmetic, no platform API: tested on Linux as well.
public enum MonitorBalance {
    public static let range: ClosedRange<Double> = -1...1
    /// Values this close to 0 are stored as 0: the centre detent.
    public static let detent: Double = 0.03

    /// NaN → 0; clamped to `range`; rounded to whole percent; within `detent` of 0 → 0.
    public static func validated(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        let clamped: Double = min(max(value, range.lowerBound), range.upperBound)
        let percent: Double = (clamped * 100).rounded()
        let rounded: Double = percent / 100
        return abs(rounded) <= detent ? 0 : rounded
    }

    /// The gain of each output channel at balance `value` (validated first).
    public static func gains(_ value: Double) -> (left: Float, right: Float) {
        let balance: Double = validated(value)
        let left: Double = min(1, 1 - balance)
        let right: Double = min(1, 1 + balance)
        return (Float(left), Float(right))
    }
}
