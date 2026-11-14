// TempoCoordinatorTests.swift — SHOW-011-T12: the app's tap tempo with an injected clock and
// announcer: taps, reset to the estimate or to no tempo, rejected taps, VoiceOver texts, and the
// analysis following the visual and PERF-011 (SHOW-011-R8, R12 to R14, R16). ANL-006-T06: the
// readout's state words, accessibility values and Reset announcement per state, on an injected
// state clock (contracts/tempo-confidence.md "App"). No wall clock.
import AudioCore
import PerformanceControl
import XCTest
@testable import projectM_iOS

@MainActor
final class TempoCoordinatorTests: XCTestCase {
    private final class Announcements {
        var said: [String] = []
    }

    /// The indicator's clock: advances 250 ms (one poll) per reading.
    private func make(step: Double = 500) -> (TempoCoordinator, Announcements) {
        let log = Announcements()
        let coordinator = TempoCoordinator(clock: TempoCoordinator.syntheticClock(stepMilliseconds: step),
                                           stateClock: TempoCoordinator.syntheticClock(stepMilliseconds: 250),
                                           announce: { (text: String) -> Void in log.said.append(text) })
        return (coordinator, log)
    }

    /// `polls` polls of one estimate (250 ms apart on the state clock).
    private func feed(_ tempo: TempoCoordinator, bpm: Double, confidence: Double, polls: Int) {
        for _ in 0..<polls {
            tempo.updateEstimate(TempoEstimate(bpm: bpm, confidence: confidence, beatNanoseconds: nil))
        }
    }

    func testFourTapsSetAManualTempoAndAnnounceIt() {
        let (tempo, log) = make()
        XCTAssertEqual(tempo.tapValue, "Searching for tempo")
        tempo.tap()
        tempo.tap()
        XCTAssertEqual(tempo.tapValue, "Tap 2 of 4")
        tempo.tap()
        XCTAssertEqual(tempo.snapshot, .none)
        XCTAssertTrue(log.said.isEmpty)
        tempo.tap()
        XCTAssertEqual(tempo.snapshot.origin, .manual)
        XCTAssertEqual(tempo.snapshot.bpm, 120)
        XCTAssertEqual(log.said, ["Tempo set to 120 BPM"])
        XCTAssertEqual(tempo.readout, .manual(bpm: 120))
        XCTAssertEqual(TempoCoordinator.readoutText(tempo.readout), "120 BPM")
        XCTAssertEqual(TempoCoordinator.stateText(tempo.readout), "Manual")
        XCTAssertEqual(TempoCoordinator.accessibilityValue(tempo.readout), "120 BPM, manual")
        XCTAssertEqual(tempo.tapValue, "120 BPM, manual")
        tempo.tap()   // same tempo: no repeated announcement
        XCTAssertEqual(log.said.count, 1)
    }

    func testResetWithoutEstimateIsNoTempo() {
        let (tempo, log) = make()
        for _ in 0..<4 { tempo.tap() }
        tempo.reset()
        XCTAssertEqual(tempo.snapshot, .none)
        XCTAssertEqual(tempo.tapsInSequence, 0)
        XCTAssertEqual(log.said.last, "Manual tempo cleared. Searching for tempo")
        XCTAssertEqual(tempo.readout, .searching)
        XCTAssertEqual(TempoCoordinator.readoutText(tempo.readout), "— BPM")
        XCTAssertEqual(TempoCoordinator.accessibilityValue(tempo.readout), "Searching for tempo")
    }

    func testResetReturnsToTheDetectedTempo() {
        let (tempo, log) = make()
        feed(tempo, bpm: 126.2, confidence: 0.9, polls: 9)            // 2 s at high confidence
        XCTAssertEqual(tempo.readout, .stable(bpm: 126.2))
        XCTAssertEqual(TempoCoordinator.accessibilityValue(tempo.readout), "126 BPM, stable")
        for _ in 0..<4 { tempo.tap() }
        XCTAssertEqual(tempo.snapshot.origin, .manual)
        XCTAssertEqual(tempo.readout, .manual(bpm: 120))
        tempo.reset()
        XCTAssertEqual(tempo.snapshot.origin, .estimated, "the snapshot is unchanged (ANL-006-R10)")
        XCTAssertEqual(tempo.readout, .stable(bpm: 126.2), "no new dwell after Reset (ANL-006-R7)")
        XCTAssertEqual(log.said.last, "Manual tempo cleared. Detected tempo 126 BPM")
        XCTAssertEqual(TempoCoordinator.stateText(tempo.readout), "Stable")
    }

    // MARK: - ANL-006-T06: states on the readout

    func testReadoutTextsPerState() {
        let cases: [(TempoReadout, String, String, String)] = [
            (.manual(bpm: 120.4), "120 BPM", "Manual", "120 BPM, manual"),
            (.stable(bpm: 119.6), "120 BPM", "Stable", "120 BPM, stable"),
            (.uncertain(bpm: 124.4), "≈124 BPM", "Uncertain", "About 124 BPM, uncertain"),
            (.searching, "— BPM", "Searching", "Searching for tempo"),
        ]
        for (readout, number, word, spoken) in cases {
            XCTAssertEqual(TempoCoordinator.readoutText(readout), number)
            XCTAssertEqual(TempoCoordinator.stateText(readout), word)
            XCTAssertEqual(TempoCoordinator.accessibilityValue(readout), spoken)
            XCTAssertEqual(TempoCoordinator.tapValue(readout: readout, taps: 0, of: 4), spoken)
        }
        XCTAssertEqual(TempoCoordinator.tapValue(readout: .stable(bpm: 120), taps: 2, of: 4), "Tap 2 of 4")
        XCTAssertEqual(TempoCoordinator.resetAnnouncement(.uncertain(bpm: 124.4)),
                       "Manual tempo cleared. Tempo uncertain, about 124 BPM")
    }

    func testTheReadoutFollowsTheIndicator() {
        let (tempo, _) = make()
        XCTAssertEqual(tempo.readout, .searching)
        feed(tempo, bpm: 124, confidence: 0.45, polls: 1)
        XCTAssertEqual(tempo.readout, .uncertain(bpm: 124), "a low-confidence estimate is shown as uncertain")
        XCTAssertEqual(tempo.snapshot, .none, "consumers still see no tempo below 0.5 (unchanged)")
        feed(tempo, bpm: 124, confidence: 0.9, polls: 8)
        XCTAssertEqual(tempo.confidenceState, .uncertain, "1.75 s of high confidence is not enough")
        feed(tempo, bpm: 124, confidence: 0.9, polls: 1)
        XCTAssertEqual(tempo.readout, .stable(bpm: 124))
        feed(tempo, bpm: 124, confidence: 0.3, polls: 5)                // 1 s below the exit threshold
        XCTAssertEqual(tempo.readout, .uncertain(bpm: 124))
        tempo.updateEstimate(nil)
        XCTAssertEqual(tempo.readout, .searching)
    }

    func testTheDebugEstimateScript() throws {
        let script = try XCTUnwrap(TempoCoordinator.estimateScript("120:0.9:40:0.3"))
        XCTAssertEqual(script(1)?.confidence, 0.9)
        XCTAssertEqual(script(40)?.confidence, 0.9)
        XCTAssertEqual(script(41)?.confidence, 0.3)
        XCTAssertEqual(script(41)?.bpm, 120)
        XCTAssertEqual(try XCTUnwrap(TempoCoordinator.estimateScript("90:0.8"))(1_000)?.confidence, 0.8)
        XCTAssertNil(TempoCoordinator.estimateScript("120"))
        XCTAssertNil(TempoCoordinator.estimateScript("a:b"))
    }

    func testRejectedTapsAreAnnounced() {
        let (fast, fastLog) = make(step: 200)
        fast.tap()
        fast.tap()
        XCTAssertEqual(fastLog.said, ["Tap slower"])
        let (slow, slowLog) = make(step: 1_500)
        slow.tap()
        slow.tap()
        XCTAssertEqual(slowLog.said, ["Tap faster"])
    }

    func testAnalysisFollowsTheVisualAndPresentation() throws {
        let (tempo, _) = make()
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: 4_096)
        tempo.runOwnAnalysis(on: try XCTUnwrap(ring.analysisTap))
        XCTAssertTrue(tempo.ownAnalysisRunning)
        XCTAssertTrue(tempo.isPolling)
        tempo.suspendForPresentationLoss()
        XCTAssertFalse(tempo.ownAnalysisRunning, "PERF-011 stops it before returning")
        XCTAssertFalse(tempo.isPolling)
        tempo.resumeForPresentation()
        XCTAssertTrue(tempo.ownAnalysisRunning)
        feed(tempo, bpm: 120, confidence: 0.9, polls: 9)
        XCTAssertEqual(tempo.readout, .stable(bpm: 120))
        tempo.stopAnalysis()
        XCTAssertFalse(tempo.ownAnalysisRunning)
        XCTAssertFalse(tempo.isPolling)
        XCTAssertEqual(tempo.snapshot, .none, "stopping clears the estimate (SHOW-011-R14)")
        XCTAssertEqual(tempo.readout, .searching, "and the indicator starts searching again (ANL-006)")
        tempo.runOwnAnalysis(on: nil)
        XCTAssertFalse(tempo.ownAnalysisRunning)
    }

    func testManualTempoSurvivesStoppingTheAnalysis() {
        let (tempo, _) = make()
        for _ in 0..<4 { tempo.tap() }
        tempo.stopAnalysis()
        XCTAssertEqual(tempo.snapshot.origin, .manual)
    }
}
