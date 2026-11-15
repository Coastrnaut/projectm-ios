// ShowBeatGridAcceptanceTests.swift — SHOW-010-T06, T08: the beat grid in the app (SHOW-010-S1, S3; contract
// specs/254-show-010-beat-grid/contracts/beat-grid.md G5, G6) through the real SHOW-007 transport: a `ShowCoordinator`
// over a temporary store, SHOW-002's driver on a `ShowManualClock`, and SHOW-011's `TempoSource` fed with synthetic tap
// times and estimates. The tempo clock is injected; nothing waits on the wall clock.
import Foundation
import PerformanceControl
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class ShowBeatGridAcceptanceTests: XCTestCase {
    static let tapStart: UInt64 = 50_000_000_000
    static let beat: UInt64 = 500_000_000

    private var show: ShowCoordinator!
    private var driver: ShowAutoAdvanceCoordinator!
    private var transport: ShowTransportCoordinator!
    private var clock: ShowManualClock!
    private var source = TempoSource()
    private var tempoNow: UInt64 = 0

    /// Two cues with 10 s dwells: a 20 s timeline.
    override func setUp() async throws {
        let suite = "SHOW010-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        show = ShowCoordinator(store: ShowStore(directory: url), registry: try SceneArchiveService.appRegistry())
        show.applyScene = { (_: SceneDocument, _: [SceneIssue]) -> [String] in [] }
        for n in 1...2 {
            let look = ShowLook(visual: .circularSpectrum, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false,
                                glowIntensity: 0.7, glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""),
                                photoID: nil, videoID: nil)
            XCTAssertTrue(show.addScene(ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Cue \(n)"), label: "Cue \(n)"))
        }
        for cue in show.list.cues { XCTAssertTrue(show.setDwell(cue.id, to: try ShowCueDwell(seconds: 10))) }
        clock = ShowManualClock()
        driver = ShowAutoAdvanceCoordinator(show: show, clock: clock, runsLoop: false)
        transport = ShowTransportCoordinator(show: show, driver: driver, defaults: defaults)
        source = TempoSource()
        transport.beatGrid.tempo = { [unowned self] () -> TempoSnapshot in self.source.snapshot }
        transport.beatGrid.tempoClock = { [unowned self] () -> UInt64 in self.tempoNow }
    }

    /// Four taps 500 ms apart: a manual 120 BPM tempo anchored on the last tap (SHOW-011).
    private func tapTempo() {
        for i in 0..<4 { source.tap(at: Self.tapStart + UInt64(i) * Self.beat) }
        XCTAssertEqual(source.snapshot.periodNanoseconds, Self.beat)
        XCTAssertEqual(source.snapshot.anchorNanoseconds, Self.tapStart + 3 * Self.beat)
    }

    /// Starts the show and plays it to `seconds` on the show clock.
    private func play(to milliseconds: Int64) {
        show.next()
        clock.advance(by: .milliseconds(milliseconds))
        driver.tick()
        XCTAssertTrue(transport.isPlaying)
        XCTAssertEqual(transport.currentTime(), .milliseconds(milliseconds))
    }

    // MARK: - G5 placement

    func testPlayingPlacesTheTapAnchorOnTheTimelineAndPausingKeepsIt() throws {
        tapTempo()
        play(to: 4000)
        tempoNow = Self.tapStart + 3 * Self.beat + 300_000_000   // the last tap was 0.3 s ago
        let tempo: BeatGridTempo = try XCTUnwrap(transport.beatGrid.gridTempo())
        XCTAssertEqual(tempo.anchorNanoseconds, 200_000_000, "4.0 s − 0.3 s = 3.7 s ≡ 0.2 s (mod 0.5 s)")
        XCTAssertEqual(tempo.periodNanoseconds, 500_000_000)
        XCTAssertEqual(transport.beatGrid.accessibilityValue(), "120 BPM, tap tempo, bar 3 beat 4",
                       "bars start at 0.2, 2.2, 4.2 s: 4.0 s is beat 4 of bar 3")
        XCTAssertEqual(transport.beatGrid.readoutText(), "Bar 3 · Beat 4 · 120 BPM")

        driver.setOperatorHold(true)   // Pause
        XCTAssertFalse(transport.isPlaying)
        tempoNow += 100_000_000        // the music goes on; the frozen show must not slide the grid
        XCTAssertEqual(transport.beatGrid.gridTempo()?.anchorNanoseconds, 200_000_000, "kept while paused")
    }

    func testAnEstimateWithoutABeatTimeStartsAtZero() throws {
        source.updateEstimate(TempoEstimate(bpm: 120, confidence: 0.9, beatNanoseconds: nil))
        play(to: 4500)
        XCTAssertEqual(transport.beatGrid.gridTempo()?.anchorNanoseconds, 0)
        XCTAssertEqual(transport.beatGrid.accessibilityValue(), "120 BPM, detected, bar 3 beat 2")
        // Below SHOW-011's confidence floor there is no tempo.
        source.updateEstimate(TempoEstimate(bpm: 120, confidence: 0.3, beatNanoseconds: nil))
        XCTAssertNil(transport.beatGrid.gridTempo())
        XCTAssertEqual(transport.beatGrid.readoutText(), "No tempo")
        XCTAssertEqual(transport.beatGrid.marks(width: 300, inset: 14), [], "no tempo, no ticks")
    }

    func testAtStandbyTheReadoutShowsOnlyTheTempo() {
        tapTempo()
        XCTAssertNil(transport.currentTime())
        XCTAssertEqual(transport.beatGrid.readoutText(), "120 BPM")
        XCTAssertEqual(transport.beatGrid.accessibilityValue(), "120 BPM, tap tempo")
        XCTAssertEqual(transport.beatGrid.gridTempo()?.anchorNanoseconds, 0, "no placement yet: from 0:00")
    }

    // MARK: - G6 layout (S3)

    func testTheRowLaysOutA120BPMGridEveryHalfSecondAcrossTheTrack() {
        source.updateEstimate(TempoEstimate(bpm: 120, confidence: 0.9, beatNanoseconds: nil))
        XCTAssertEqual(transport.timeline.duration, .seconds(20))
        let marks: [BeatGridMark] = transport.beatGrid.marks(width: 300, inset: 14)
        XCTAssertEqual(marks.count, 41, "a tick every 0.5 s over 20 s")
        for (i, mark) in marks.enumerated() {
            XCTAssertEqual(mark.x, 14 + Double(i) * 0.5 / 20 * 272, accuracy: 0.01)
            XCTAssertEqual(mark.isBar, i % 4 == 0, "a bar every 2 s")
        }
        XCTAssertEqual(transport.beatGrid.drawnSummary, "ticks 41 bars 11")
    }
}
