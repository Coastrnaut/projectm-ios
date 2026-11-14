// LatencyOffset.swift — AUD-013: the per-source visual delay (specs/095-aud-013-source-latency-
// calibration, contracts/latency-delay.md C1-C3; research AUD-013-D1 to D5; ADR-0035).
//
// What it shifts: the audio on its way to every visual consumer, on the sample clock. The app puts a
// `LatencyDelayReader` outermost in the analysis chain (tap → channel selection → trim → gate →
// delay → `WaveformTap` → pipeline), so bands, the oscilloscope, MOD-002 bindings, kick, centroid,
// onsets, beats and tempo all move by the same amount, and around projectM's reader. Playback, the
// PCM sink and the audio-state classifier are never delayed. Range 0…250 ms: the visuals can only be
// delayed (the analysis cannot see audio before it arrives).
//
// Law (C3): the reader pulls every frame the wrapped reader has into a preallocated stereo line and
// releases only frames that at least `applied` newer frames have followed, unchanged and in order.
// A target change moves `applied` by at most ⌈pulled / 4⌉ frames per read (D2), so between two
// arrivals the released frames stay within 75…125 % of the arrived ones (+1 frame). At target and
// applied 0 with an empty line the read is forwarded unchanged (bit-identical, no copy).
//
// Sessions (D4): `.analysis` empties its line when the wrapped reader's session generation
// (ANL-016-R9) changes and applies the target at once; `.renderer` never empties (projectM's feed is
// continuous across a switch, ADR-0034) and drops the oldest frames beyond applied + 2,205 (R-06's
// freshness bound). Overflow (D5): a pull that finds the line full reads up to 1,024 more frames aside and drops as
// many of the oldest (drop-oldest, counted).
//
// Real-time safety (Constitution VII): the line is allocated in `init`; a read does one relaxed
// atomic load (the target), copies, and never allocates, locks or logs. One consumer thread per
// reader (the analysis worker or the render loop); never on an audio callback.
import Synchronization

/// Bounds, conversions and the estimate (contract C1).
public enum LatencyOffset {
    public static let minimumMilliseconds: Double = 0
    public static let maximumMilliseconds: Double = 250
    /// 44.1 frames per millisecond at the normalized rate.
    public static let framesPerMillisecond: Double = NormalizedPCMRing.sampleRate / 1_000
    /// 250 ms at 44.1 kHz.
    public static let maximumDelayFrames: Int = 11_025
    /// The longest delay plus the analysis tap's capacity (0.5 s): a full pull always fits.
    public static let lineCapacityFrames: Int = maximumDelayFrames + NormalizedPCMRing.analysisTapDefaultCapacityFrames
    /// projectM's feed keeps at most this many frames beyond the delay (the freshness rule, R-06).
    public static let rendererExcessFrames: Int = NormalizedPCMRing.freshnessFrames
    /// A change moves the applied delay by at most 1/4 of the frames pulled in a read.
    public static let slewDivisor: Int = 4
    /// Frames read aside at once when a pull finds the line full (then as many oldest are dropped).
    public static let overflowDropFrames: Int = 1_024

    /// NaN → 0; clamped to 0…250; rounded to whole milliseconds.
    public static func validatedMilliseconds(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        let clamped: Double = min(max(value, minimumMilliseconds), maximumMilliseconds)
        return clamped.rounded()
    }

    /// Whole frames for `milliseconds` (validated first).
    public static func frames(milliseconds: Double) -> Int {
        let valid: Double = validatedMilliseconds(milliseconds)
        let exact: Double = valid * framesPerMillisecond
        return min(Int(exact.rounded()), maximumDelayFrames)
    }

    /// AUD-013-R9 (research D3): output latency + I/O buffer for In-App Playback and System/App
    /// Capture, 0 for Microphone (its sound reaches the microphone after it was heard). Non-finite or
    /// negative inputs count as 0. Whole milliseconds within the range.
    public static func estimateMilliseconds(mode: AudioSourceMode, outputLatency: Double, ioBufferDuration: Double) -> Double {
        guard mode != .microphone else { return 0 }
        let output: Double = usable(outputLatency)
        let buffer: Double = usable(ioBufferDuration)
        let seconds: Double = output + buffer
        return validatedMilliseconds(seconds * 1_000)
    }

    private static func usable(_ seconds: Double) -> Double {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return seconds
    }
}

/// The target delay shared by the app (writer) and the delay readers (contract C2).
public final class LatencyOffsetControl: Sendable {
    private let target: Atomic<Int>

    public init(targetFrames: Int = 0) {
        target = Atomic(LatencyOffsetControl.clamped(targetFrames))
    }

    /// 0…`LatencyOffset.maximumDelayFrames` (clamped on write).
    public var targetFrames: Int {
        get { target.load(ordering: .relaxed) }
        set { target.store(LatencyOffsetControl.clamped(newValue), ordering: .relaxed) }
    }

    private static func clamped(_ frames: Int) -> Int {
        min(max(frames, 0), LatencyOffset.maximumDelayFrames)
    }
}

/// A delay line in front of a visual consumer (contract C3). One consumer thread only.
public final class LatencyDelayReader: NormalizedPCMReader, AnalysisSessionReporting, @unchecked Sendable {
    public enum Mode: Sendable, Equatable {
        /// The analysis chain: emptied on a new session.
        case analysis
        /// projectM's feed: kept across sessions, excess beyond delay + 2,205 frames dropped.
        case renderer
    }

    public let mode: Mode
    private let reader: any NormalizedPCMReader
    /// The wrapped reader's session reporting, cast once (no cast per read).
    private let reporting: (any AnalysisSessionReporting)?
    private let control: LatencyOffsetControl
    private let capacity: Int
    private let line: UnsafeMutablePointer<Float>
    /// Overflow scratch (`LatencyOffset.overflowDropFrames` stereo frames).
    private let overflow: UnsafeMutablePointer<Float>
    // Reader-thread-owned:
    private var head = 0
    private var count = 0
    private var applied: Int
    private var generation: UInt64
    private let dropped = Atomic<Int>(0)

    /// `capacityFrames` is for tests; the default fits the longest delay plus a full tap.
    public init(_ reader: any NormalizedPCMReader, control: LatencyOffsetControl, mode: Mode,
                capacityFrames: Int = LatencyOffset.lineCapacityFrames) {
        self.reader = reader
        reporting = reader as? any AnalysisSessionReporting
        self.control = control
        self.mode = mode
        capacity = max(capacityFrames, LatencyOffset.overflowDropFrames)
        let samples: Int = capacity * NormalizedPCMRing.channelCount
        line = .allocate(capacity: samples)
        line.initialize(repeating: 0, count: samples)
        let overflowSamples: Int = LatencyOffset.overflowDropFrames * NormalizedPCMRing.channelCount
        overflow = .allocate(capacity: overflowSamples)
        overflow.initialize(repeating: 0, count: overflowSamples)
        applied = control.targetFrames   // a new consumer starts at the target (nothing buffered)
        generation = reporting?.analysisSessionGeneration ?? 0
    }

    deinit {
        line.deinitialize(count: capacity * NormalizedPCMRing.channelCount)
        line.deallocate()
        overflow.deinitialize(count: LatencyOffset.overflowDropFrames * NormalizedPCMRing.channelCount)
        overflow.deallocate()
    }

    /// Forwarded; 0 when the wrapped reader reports none.
    public var analysisSessionGeneration: UInt64 { reporting?.analysisSessionGeneration ?? 0 }

    /// The delay in effect (reader thread).
    public var appliedDelayFrames: Int { applied }
    /// Frames held in the line (reader thread).
    public var bufferedFrames: Int { count }
    /// Frames dropped by overflow or the renderer's excess trim.
    public var droppedFrames: Int { dropped.load(ordering: .relaxed) }

    public func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        guard maxFrames > 0 else { return 0 }
        let target: Int = control.targetFrames
        if mode == .analysis {
            let current: UInt64 = analysisSessionGeneration
            if current != generation {
                generation = current
                head = 0
                count = 0
                applied = target
            }
        }
        if applied == 0 && target == 0 && count == 0 {
            return reader.read(into: dst, maxFrames: maxFrames)   // C3.P: unchanged
        }
        let pulled: Int = pull()
        if applied != target && pulled > 0 {
            let step: Int = (pulled + LatencyOffset.slewDivisor - 1) / LatencyOffset.slewDivisor
            if applied < target {
                applied = min(target, applied + step)
            } else {
                applied = max(target, applied - step)
            }
        }
        if mode == .renderer {
            let excess: Int = count - applied - LatencyOffset.rendererExcessFrames
            if excess > 0 { discardOldest(excess) }
        }
        let releasable: Int = count - applied
        guard releasable > 0 else { return 0 }
        let n: Int = min(releasable, maxFrames)
        copyOldest(into: dst, frames: n)
        return n
    }

    /// Moves everything the wrapped reader has into the line; returns the frames pulled.
    private func pull() -> Int {
        let channels: Int = NormalizedPCMRing.channelCount
        var total = 0
        while true {
            if count == capacity {
                // Full: read a chunk aside first, so nothing is dropped unless more audio exists.
                let n: Int = reader.read(into: overflow, maxFrames: LatencyOffset.overflowDropFrames)
                if n <= 0 { break }
                discardOldest(n)
                appendFromOverflow(frames: n)
                total += n
                continue
            }
            let tail: Int = (head + count) % capacity
            let contiguous: Int = min(capacity - count, capacity - tail)
            let n: Int = reader.read(into: line + tail * channels, maxFrames: contiguous)
            if n <= 0 { break }
            count += n
            total += n
        }
        return total
    }

    private func appendFromOverflow(frames: Int) {
        let channels: Int = NormalizedPCMRing.channelCount
        let tail: Int = (head + count) % capacity
        let first: Int = min(frames, capacity - tail)
        (line + tail * channels).update(from: overflow, count: first * channels)
        let rest: Int = frames - first
        if rest > 0 { line.update(from: overflow + first * channels, count: rest * channels) }
        count += frames
    }

    private func discardOldest(_ frames: Int) {
        let n: Int = min(frames, count)
        guard n > 0 else { return }
        head = (head + n) % capacity
        count -= n
        _ = dropped.add(n, ordering: .relaxed)
    }

    private func copyOldest(into dst: UnsafeMutablePointer<Float>, frames: Int) {
        let channels: Int = NormalizedPCMRing.channelCount
        let first: Int = min(frames, capacity - head)
        dst.update(from: line + head * channels, count: first * channels)
        let rest: Int = frames - first
        if rest > 0 { (dst + first * channels).update(from: line, count: rest * channels) }
        head = (head + frames) % capacity
        count -= frames
    }
}
