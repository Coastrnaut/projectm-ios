// BeatGrid.swift — SHOW-010 the beat grid on the show timeline (specs/254-show-010-beat-grid; R1 to R3; data-model.md;
// contracts/beat-grid.md G1 to G4; research SHOW-010-D1 to D3).
//
// * A tempo is a period and an anchor beat in whole nanoseconds on the show timeline: beats are anchor + k × period
//   (integer arithmetic, floor division before the anchor), bars every fourth beat from the anchor (4/4, as SHOW-003 and
//   MOD-017 quantize).
// * `ticks` never returns more than `maximumTicks`: the stride (1, 4, 8, 16 … beats; bars stay bars) rises until the
//   window fits. `stride(for:duration:width:)` also keeps drawn ticks at least `minimumSpacing` points apart.
// * Bars are numbered so that 0:00 lies in bar 1; beats are 1…4 within a bar.
// Pure value types, Foundation only (Linux). The app converts SHOW-011's `TempoSnapshot` into a `BeatGridTempo`.
import Foundation

/// A tempo placed on the show timeline.
public struct BeatGridTempo: Sendable, Hashable {
    public enum Source: String, Sendable, Hashable {
        /// SHOW-011 tap tempo.
        case manual
        /// ANL-005's estimate (confidence at least SHOW-011's floor).
        case estimated
    }

    public let bpm: Double
    /// 60 s / BPM in whole nanoseconds (> 0).
    public let periodNanoseconds: Int64
    /// A beat (and bar start) on the show timeline, in nanoseconds; any value.
    public let anchorNanoseconds: Int64
    public let source: Source

    /// Nil for a non-positive period or a BPM that is not finite and positive.
    public init?(bpm: Double, periodNanoseconds: Int64, anchorNanoseconds: Int64, source: Source) {
        guard periodNanoseconds > 0, bpm.isFinite, bpm > 0 else { return nil }
        self.bpm = bpm
        self.periodNanoseconds = periodNanoseconds
        self.anchorNanoseconds = anchorNanoseconds
        self.source = source
    }

    /// The same tempo with its anchor moved.
    public func anchored(at nanoseconds: Int64) -> BeatGridTempo {
        BeatGridTempo(bpm: bpm, periodNanoseconds: periodNanoseconds, anchorNanoseconds: nanoseconds, source: source)!
    }
}

/// One beat on the timeline.
public struct BeatGridTick: Sendable, Hashable {
    public let nanoseconds: Int64
    /// The beat's index from the anchor (negative before it).
    public let beat: Int64
    /// Every fourth beat from the anchor starts a bar.
    public let isBar: Bool

    public var time: Duration { .nanoseconds(nanoseconds) }
}

/// A bar and beat (bar 1 contains 0:00; beats 1…4).
public struct BeatGridPosition: Sendable, Hashable {
    public let bar: Int64
    public let beat: Int

    public init(bar: Int64, beat: Int) {
        self.bar = bar
        self.beat = beat
    }
}

/// A tick laid out over a track.
public struct BeatGridMark: Sendable, Hashable {
    public let x: Double
    public let isBar: Bool
}

public enum BeatGrid {
    /// The most ticks any window returns (R2).
    public static let maximumTicks: Int = 512
    /// Drawn ticks are at least this many points apart (R2).
    public static let minimumSpacing: Double = 4
    public static let beatsPerBar: Int64 = 4

    // MARK: - Ticks (G1, G2)

    /// The beats from `start` to `end` (inclusive) whose index is a multiple of the stride, ascending. The stride rises
    /// (1 → 4 → 8 …) until at most `maximumTicks` remain. Empty without a tempo or for an empty window.
    public static func ticks(_ tempo: BeatGridTempo?, from start: Duration, to end: Duration,
                             stride requested: Int64 = 1) -> [BeatGridTick] {
        guard let tempo else { return [] }
        let lo: Int64 = nanoseconds(start)
        let hi: Int64 = nanoseconds(end)
        guard hi >= lo else { return [] }
        let first: Int64 = ceilDiv(lo - tempo.anchorNanoseconds, tempo.periodNanoseconds)
        let last: Int64 = floorDiv(hi - tempo.anchorNanoseconds, tempo.periodNanoseconds)
        guard last >= first else { return [] }
        var stride: Int64 = max(requested, 1)
        while count(first: first, last: last, stride: stride) > Int64(maximumTicks) { stride = next(stride) }
        var k: Int64 = ceilDiv(first, stride) * stride
        var result: [BeatGridTick] = []
        result.reserveCapacity(Int(count(first: first, last: last, stride: stride)))
        while k <= last {
            let t: Int64 = tempo.anchorNanoseconds + k * tempo.periodNanoseconds
            result.append(BeatGridTick(nanoseconds: t, beat: k, isBar: mod(k, beatsPerBar) == 0))
            k += stride
        }
        return result
    }

    /// The smallest stride (1, 4, 8, 16 …) whose ticks over [0, duration] drawn `width` points wide are at least
    /// `minimumSpacing` apart and at most `maximumTicks`. 1 without a tempo or a positive duration and width.
    public static func stride(_ tempo: BeatGridTempo?, duration: Duration, width: Double) -> Int64 {
        let total: Int64 = nanoseconds(duration)
        guard let tempo, total > 0, width > 0 else { return 1 }
        let beats: Int64 = total / tempo.periodNanoseconds + 1
        var stride: Int64 = 1
        while true {
            let spacing: Double = Double(tempo.periodNanoseconds) * Double(stride) / Double(total) * width
            if spacing >= minimumSpacing, beats / stride <= Int64(maximumTicks) { return stride }
            stride = next(stride)
        }
    }

    // MARK: - Layout (G3)

    /// The ticks over [0, duration] at the drawing stride, at x = inset + t / duration × (width − 2 × inset).
    public static func marks(_ tempo: BeatGridTempo?, duration: Duration, width: Double, inset: Double) -> [BeatGridMark] {
        let total: Int64 = nanoseconds(duration)
        let usable: Double = width - 2 * inset
        guard tempo != nil, total > 0, usable > 0 else { return [] }
        let stride: Int64 = stride(tempo, duration: duration, width: usable)
        return ticks(tempo, from: .zero, to: duration, stride: stride).map { (tick: BeatGridTick) -> BeatGridMark in
            let fraction: Double = Double(tick.nanoseconds) / Double(total)
            return BeatGridMark(x: inset + fraction * usable, isBar: tick.isBar)
        }
    }

    // MARK: - Position (G4)

    /// The bar and beat at `time` (0:00 is in bar 1); nil without a tempo.
    public static func position(_ tempo: BeatGridTempo?, at time: Duration) -> BeatGridPosition? {
        guard let tempo else { return nil }
        let k: Int64 = floorDiv(nanoseconds(time) - tempo.anchorNanoseconds, tempo.periodNanoseconds)
        let bar: Int64 = floorDiv(k, beatsPerBar)
        let firstBar: Int64 = floorDiv(floorDiv(-tempo.anchorNanoseconds, tempo.periodNanoseconds), beatsPerBar)
        return BeatGridPosition(bar: bar - firstBar + 1, beat: Int(k - bar * beatsPerBar) + 1)
    }

    /// The beat closest to `time` (a tie goes to the later beat); nil without a tempo.
    public static func nearestBeat(_ tempo: BeatGridTempo?, to time: Duration) -> Duration? {
        guard let tempo else { return nil }
        let offset: Int64 = nanoseconds(time) - tempo.anchorNanoseconds
        let k: Int64 = floorDiv(offset + tempo.periodNanoseconds / 2, tempo.periodNanoseconds)
        return .nanoseconds(tempo.anchorNanoseconds + k * tempo.periodNanoseconds)
    }

    // MARK: - Texts (G4)

    public static let noTempoText = "No tempo"

    /// "Bar 3 · Beat 2 · 120 BPM", "120 BPM" without a time, or "No tempo".
    public static func readoutText(_ tempo: BeatGridTempo?, at time: Duration?) -> String {
        guard let tempo else { return noTempoText }
        let bpm: String = "\(wholeBPM(tempo.bpm)) BPM"
        guard let time, let p = position(tempo, at: time) else { return bpm }
        return "Bar \(p.bar) · Beat \(p.beat) · " + bpm
    }

    /// "120 BPM, tap tempo, bar 3 beat 2" ("detected" for an estimate), "120 BPM, tap tempo" without a time, or
    /// "No tempo".
    public static func accessibilityValue(_ tempo: BeatGridTempo?, at time: Duration?) -> String {
        guard let tempo else { return noTempoText }
        let source: String = tempo.source == .manual ? "tap tempo" : "detected"
        let head: String = "\(wholeBPM(tempo.bpm)) BPM, " + source
        guard let time, let p = position(tempo, at: time) else { return head }
        return head + ", bar \(p.bar) beat \(p.beat)"
    }

    public static func wholeBPM(_ bpm: Double) -> Int { Int(bpm.rounded()) }

    // MARK: - Arithmetic

    /// A duration in whole nanoseconds (attoseconds truncated).
    public static func nanoseconds(_ d: Duration) -> Int64 {
        let parts = d.components
        return parts.seconds * 1_000_000_000 + parts.attoseconds / 1_000_000_000
    }

    /// `a` modulo `b` in 0..<b (b > 0).
    public static func mod(_ a: Int64, _ b: Int64) -> Int64 {
        let r: Int64 = a % b
        return r < 0 ? r + b : r
    }

    static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q: Int64 = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    static func ceilDiv(_ a: Int64, _ b: Int64) -> Int64 { -floorDiv(-a, b) }

    /// 1 → 4 → 8 → 16 …
    private static func next(_ stride: Int64) -> Int64 { stride < beatsPerBar ? beatsPerBar : stride * 2 }

    private static func count(first: Int64, last: Int64, stride: Int64) -> Int64 {
        let lo: Int64 = ceilDiv(first, stride)
        let hi: Int64 = floorDiv(last, stride)
        return hi >= lo ? hi - lo + 1 : 0
    }
}
