// FrameIntervalHistogram.swift — PERF-012 (specs/209-perf-012-performance-report, research PERF-012-D1 to D3): the
// intervals between frames handed to the display, for the performance report's percentiles.
//
// * Fixed 0.1 ms buckets from 0 to 250 ms (2,500 buckets; the last also takes longer intervals), the exact maximum,
//   sum and count, and exact counts of intervals at least 25, 50 and 100 ms long.
// * A percentile is the upper edge of the bucket holding the nearest rank (rank = ceil(p × count), at least 1), capped
//   by the exact maximum: never lower than the true nearest-rank value, at most one bucket (0.1 ms) above it.
// * `FrameIntervalRecorder` wraps one histogram in a `Mutex`. `FrameDropCounter` records into it on every accepted
//   `submit` (the frame thread, only while the performance overlay is shown). The buckets are allocated once at init
//   and mutated in place under the lock, so recording allocates nothing (PERF-012-R11). Local and in memory only.
import Synchronization

/// Frame-to-frame intervals in fixed buckets (PERF-012 data model).
public struct FrameIntervalHistogram: Sendable, Equatable {
    public static let resolutionMs: Double = 0.1
    public static let bucketCount: Int = 2_500
    /// Long-frame thresholds, counted exactly (an interval at least this long).
    public static let longFrameThresholdsMs: [Double] = [25, 50, 100]

    public private(set) var buckets: [UInt32]
    public private(set) var count: Int = 0
    public private(set) var sumMs: Double = 0
    /// Exact longest interval; 0 when `count` is 0.
    public private(set) var maxMs: Double = 0
    /// One count per entry of `longFrameThresholdsMs`.
    public private(set) var longFrames: [Int]

    public init() {
        buckets = [UInt32](repeating: 0, count: Self.bucketCount)
        longFrames = [Int](repeating: 0, count: Self.longFrameThresholdsMs.count)
    }

    /// Adds one interval in seconds; non-finite or non-positive values are ignored.
    public mutating func record(seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        let ms: Double = seconds * 1_000
        let raw: Double = (ms / Self.resolutionMs).rounded(.down)
        let index: Int = raw >= Double(Self.bucketCount - 1) ? Self.bucketCount - 1 : Int(raw)
        if buckets[index] < UInt32.max { buckets[index] += 1 }
        count += 1
        sumMs += ms
        if ms > maxMs { maxMs = ms }
        for i in 0..<Self.longFrameThresholdsMs.count where ms >= Self.longFrameThresholdsMs[i] {
            longFrames[i] += 1
        }
    }

    /// Nearest-rank percentile (`p` in 0…1) in milliseconds; nil when nothing was recorded.
    public func percentile(_ p: Double) -> Double? {
        guard count > 0, p.isFinite else { return nil }
        let clamped: Double = min(max(p, 0), 1)
        let rank: Int = max(1, Int((clamped * Double(count)).rounded(.up)))
        var cumulative: Int = 0
        for index in 0..<Self.bucketCount {
            cumulative += Int(buckets[index])
            guard cumulative >= rank else { continue }
            if index == Self.bucketCount - 1 { return maxMs }
            let upperEdge: Double = Double(index + 1) * Self.resolutionMs
            return min(upperEdge, maxMs)
        }
        return maxMs
    }

    /// Total measured time in seconds.
    public var measuredSeconds: Double { sumMs / 1_000 }
}

/// The app session's frame intervals, shared by the display counters (PERF-012-D3).
public final class FrameIntervalRecorder: Sendable {
    private let state = Mutex(FrameIntervalHistogram())

    public init() {}

    /// The frame thread: one interval in seconds. Allocates nothing.
    public func record(seconds: Double) {
        state.withLock { (histogram: inout FrameIntervalHistogram) -> Void in histogram.record(seconds: seconds) }
    }

    /// A copy of everything recorded since init (the export).
    public func snapshot() -> FrameIntervalHistogram {
        state.withLock { (histogram: inout FrameIntervalHistogram) -> FrameIntervalHistogram in histogram }
    }
}
