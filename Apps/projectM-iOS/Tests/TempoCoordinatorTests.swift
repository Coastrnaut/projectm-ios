// TempoCoordinatorTests.swift — SHOW-011-T12: the app's tap tempo with an injected clock and
// announcer: taps, reset to the estimate or to no tempo, rejected taps, VoiceOver texts, and the
// analysis following the visual and PERF-011 (SHOW-011-R8, R12 to R14, R16). No wall clock.
import AudioCore
import PerformanceControl
import XCTest
@testable import projectM_iOS

@MainActor
final class TempoCoordinatorTests: XCTestCase {
    private final class Announcements {
        var said: [String] = []
    }

    private func make(step: Double = 500) -> (TempoCoordinator, Announcements) {
        let log = Announcements()
        let coordinator = TempoCoordinator(clock: TempoCoordinator.syntheticClock(stepMilliseconds: step),
                                           announce: { log.said.append($0) })
        return (coordinator, log)
    }

    func testFourTapsSetAManualTempoAndAnnounceIt() {
        let (tempo, log) = make()
        XCTAssertEqual(tempo.tapValue, "No tempo")
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
        XCTAssertEqual(TempoCoordinator.readoutText(tempo.snapshot), "120 BPM")
        XCTAssertEqual(TempoCoordinator.originText(tempo.snapshot), "Manual")
        XCTAssertEqual(TempoCoordinator.accessibilityValue(tempo.snapshot), "120 BPM, manual")
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
        XCTAssertEqual(log.said.last, "Manual tempo cleared. No tempo")
        XCTAssertEqual(TempoCoordinator.readoutText(tempo.snapshot), "—")
        XCTAssertEqual(TempoCoordinator.accessibilityValue(tempo.snapshot), "No tempo")
    }

    func testResetReturnsToTheDetectedTempo() {
        let (tempo, log) = make()
        tempo.updateEstimate(TempoEstimate(bpm: 126.2, confidence: 0.9, beatNanoseconds: nil))
        XCTAssertEqual(TempoCoordinator.accessibilityValue(tempo.snapshot), "126 BPM, detected")
        for _ in 0..<4 { tempo.tap() }
        XCTAssertEqual(tempo.snapshot.origin, .manual)
        tempo.reset()
        XCTAssertEqual(tempo.snapshot.origin, .estimated)
        XCTAssertEqual(log.said.last, "Manual tempo cleared. Detected tempo 126 BPM")
        XCTAssertEqual(TempoCoordinator.originText(tempo.snapshot), "Detected")
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
        tempo.updateEstimate(TempoEstimate(bpm: 120, confidence: 0.9, beatNanoseconds: nil))
        tempo.stopAnalysis()
        XCTAssertFalse(tempo.ownAnalysisRunning)
        XCTAssertFalse(tempo.isPolling)
        XCTAssertEqual(tempo.snapshot, .none, "stopping clears the estimate (SHOW-011-R14)")
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
