// ShowBeatGridCoordinator.swift — SHOW-010 the beat grid on the show timeline in the app (specs/254-show-010-beat-grid;
// R4 to R6; contract G5; research SHOW-010-D4).
//
// * Reads SHOW-011's tempo snapshot (manual tap tempo first, else ANL-005's estimate at confidence ≥ 0.5) and the
//   monotonic analysis clock through injected closures; owned by `ShowTransportCoordinator`, wired by AppCoordinator.
// * Placement: the snapshot's anchor beat is on the analysis clock and the timeline on the show driver's clock; both are
//   monotonic, so only differences are used. While the show plays, the anchor lands at
//   `timelineNow − (tempoNow − anchor)`, reduced modulo the period. Paused or at Standby the last placement is kept;
//   without an anchor or before any placement the grid starts at 0:00. Memory only (nothing stored).
// * No timer: the timeline row reads it on its existing twice-a-second redraw.
import AudioCore
import Foundation
import PerformanceControl
import ShowControl

@MainActor
final class ShowBeatGridCoordinator {
    weak var transport: ShowTransportCoordinator?
    /// SHOW-011's snapshot (AppCoordinator wires the tempo coordinator).
    var tempo: () -> TempoSnapshot = { () -> TempoSnapshot in .none }
    /// The clock the snapshot's anchor is on.
    var tempoClock: () -> UInt64 = { () -> UInt64 in MonotonicClock.nowNanoseconds() }
    /// The last placement of an anchor beat on the timeline (ns, 0..<period of the tempo that placed it).
    private(set) var placedAnchor: Int64?

    /// The grid's tempo on the show timeline; nil without a tempo. Places the anchor while the show plays.
    func gridTempo() -> BeatGridTempo? {
        let snapshot: TempoSnapshot = tempo()
        guard let bpm = snapshot.bpm, let period = snapshot.periodNanoseconds, period > 0, period <= UInt64(Int64.max)
        else { return nil }
        let source: BeatGridTempo.Source
        switch snapshot.origin {
        case .manual: source = .manual
        case .estimated: source = .estimated
        case .none: return nil
        }
        let p = Int64(period)
        if let anchor = snapshot.anchorNanoseconds, let transport, transport.isPlaying, let now = transport.currentTime() {
            let tempoNow: UInt64 = tempoClock()
            let since: Int64 = tempoNow >= anchor ? Int64(clamping: tempoNow - anchor) : -Int64(clamping: anchor - tempoNow)
            placedAnchor = BeatGrid.mod(BeatGrid.nanoseconds(now) &- since, p)
        }
        let anchor: Int64 = placedAnchor.map { (a: Int64) -> Int64 in BeatGrid.mod(a, p) } ?? 0
        return BeatGridTempo(bpm: bpm, periodNanoseconds: p, anchorNanoseconds: anchor, source: source)
    }

    /// The ticks laid over a track `width` points wide with `inset` on each side (contract G3).
    func marks(width: Double, inset: Double) -> [BeatGridMark] { marks(gridTempo(), width: width, inset: inset) }

    /// The ticks of `tempo` (a `gridTempo()` the caller already read) over the track.
    func marks(_ tempo: BeatGridTempo?, width: Double, inset: Double) -> [BeatGridMark] {
        guard let transport else { return [] }
        let marks: [BeatGridMark] = BeatGrid.marks(tempo, duration: transport.timeline.duration, width: width, inset: inset)
        drawn = (marks.count, marks.filter { (m: BeatGridMark) -> Bool in m.isBar }.count)
        return marks
    }

    /// The last layout's tick and bar counts (DEBUG probe and tests; not observed).
    private(set) var drawn: (ticks: Int, bars: Int) = (0, 0)

    /// "ticks 41 bars 11" (the UI test's probe).
    var drawnSummary: String { "ticks \(drawn.ticks) bars \(drawn.bars)" }

    /// "Bar 3 · Beat 2 · 120 BPM" at the displayed time, or "No tempo".
    func readoutText() -> String { BeatGrid.readoutText(gridTempo(), at: transport?.displayedTime()) }

    /// "120 BPM, tap tempo, bar 3 beat 2" at the displayed time, or "No tempo".
    func accessibilityValue() -> String { BeatGrid.accessibilityValue(gridTempo(), at: transport?.displayedTime()) }
}
