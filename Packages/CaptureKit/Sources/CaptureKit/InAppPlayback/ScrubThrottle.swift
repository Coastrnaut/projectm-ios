// ScrubThrottle.swift — limits seeks while the scrubber is dragged (AUD-006-T17; AUD-006-R12):
// at most one every `minimumInterval`. The release of the scrubber always seeks, without asking.

public struct ScrubThrottle: Sendable {
    /// 0.1 s: at most 10 seeks per second.
    public static let minimumInterval = 0.1

    private var lastAccepted: Double?

    public init() {}

    /// True if a seek may be made at `time` (seconds on any monotonic clock); it then counts as made.
    public mutating func shouldSeek(at time: Double) -> Bool {
        if let last = lastAccepted, time >= last, time - last < ScrubThrottle.minimumInterval - 1e-9 { return false }
        lastAccepted = time
        return true
    }

    /// A new drag starts: the next value seeks at once.
    public mutating func reset() {
        lastAccepted = nil
    }
}
