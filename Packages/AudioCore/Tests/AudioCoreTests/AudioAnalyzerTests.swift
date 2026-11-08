// AudioAnalyzer drives the classifier from a real PCMSink with an injected clock.
import XCTest
import Foundation
@testable import AudioCore

final class AudioAnalyzerTests: XCTestCase {
    private final class TestClock: @unchecked Sendable {
        var now: Double = 0
    }

    private let format = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: true, sampleType: .float32)

    private func push(_ sink: PCMSink, amplitude: Float, seconds: Double) {
        let frames = Int(48_000 * seconds)
        let samples = [Float](repeating: amplitude, count: frames * 2)
        samples.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: frames, format: format, hostTimeNs: 1) }
    }

    func testLoudAudioBecomesActiveAndPublishesTransitions() {
        let sink = PCMSink()
        let clock = TestClock()
        let analyzer = AudioAnalyzer(sink: sink, clock: { clock.now })
        let received = UpdateCollector()
        analyzer.setUpdateHandler { received.append($0) }
        let started = analyzer.apply(.started)
        XCTAssertEqual(started.state, .waiting)

        for i in 1...30 {          // 30 × 10 ms of loud audio
            push(sink, amplitude: 0.5, seconds: 0.01)
            clock.now = Double(i) * 0.01
            analyzer.step()
        }
        XCTAssertEqual(analyzer.currentState, .active)
        // Each transition is delivered once: `apply` returns its own, published updates the rest.
        let states = (started.newTransitions + received.all.flatMap(\.newTransitions)).map(\.state)
        XCTAssertEqual(states, [.waiting, .active])
        XCTAssertEqual(analyzer.transitions(from: 0).map(\.state), [.waiting, .active])
        XCTAssertTrue(received.all.last!.hasVerifiedActiveAudio)
    }

    func testNoDataBecomesNoAudioReceived() {
        let sink = PCMSink()
        let clock = TestClock()
        let analyzer = AudioAnalyzer(sink: sink, clock: { clock.now })
        analyzer.apply(.started)
        clock.now = 5.01
        XCTAssertEqual(analyzer.step().state, .noAudioReceived)
    }

    func testDigitalSilenceIsSilentNotNoAudio() {
        let sink = PCMSink()
        let clock = TestClock()
        let analyzer = AudioAnalyzer(sink: sink, clock: { clock.now })
        analyzer.apply(.started)
        push(sink, amplitude: 0, seconds: 0.01)
        clock.now = 0.01
        XCTAssertEqual(analyzer.step().state, .silent)
    }

    // MARK: - Transitions are delivered without the timer (review F6)

    func testApplyReturnsAndRecordsFinalTransitionOnce() {
        let sink = PCMSink()
        let clock = TestClock()
        let analyzer = AudioAnalyzer(sink: sink, clock: { clock.now })
        let received = UpdateCollector()
        analyzer.setUpdateHandler { received.append($0) }
        let started = analyzer.apply(.started)
        XCTAssertEqual(started.newTransitions.map(\.state), [.waiting])
        clock.now = 2
        let stopped = analyzer.apply(.userStopped)   // no timer and no publish afterwards
        XCTAssertEqual(stopped.newTransitions, [StateTransition(atSeconds: 2, state: .stopped)])
        XCTAssertEqual(analyzer.transitions(from: 0).map(\.state), [.waiting, .stopped])
        XCTAssertEqual(analyzer.transitions(from: 1).map(\.state), [.stopped])
        XCTAssertEqual(analyzer.transitions(from: 2), [])
        // Delivered once: a later publish does not repeat them.
        XCTAssertEqual(analyzer.step().newTransitions, [])
    }

    func testEndedBySystemAndFailureAreRecorded() {
        let sink = PCMSink()
        let analyzer = AudioAnalyzer(sink: sink, clock: { 0 })
        analyzer.apply(.started)
        analyzer.apply(.endedBySystem)
        XCTAssertEqual(analyzer.transitions(from: 0).last, StateTransition(atSeconds: 0, state: .endedBySystem,
                                                                           reason: "endedBySystem"))
        analyzer.beginAttempt()
        analyzer.apply(.started)
        analyzer.apply(.failed(.microphoneUnavailable))
        XCTAssertEqual(analyzer.transitions(from: 0).map(\.state), [.waiting, .stopped])
        XCTAssertEqual(analyzer.transitions(from: 0).last?.reason, "microphoneUnavailable")
    }

    func testFailedStartIsRecordedEvenWithoutStateChange() {
        let sink = PCMSink()
        let clock = TestClock()
        let analyzer = AudioAnalyzer(sink: sink, clock: { clock.now })
        analyzer.beginAttempt()
        clock.now = 4   // picker on screen
        let update = analyzer.apply(.startFailed(.cancelled))
        XCTAssertEqual(update.state, .notStarted)
        XCTAssertEqual(analyzer.transitions(from: 0), [StateTransition(atSeconds: 4, state: .notStarted, reason: "cancelled")])
    }

    // MARK: - A new attempt forgets the previous session (review F2)

    func testBeginAttemptForgetsPreviousSession() {
        let sink = PCMSink()
        let clock = TestClock()
        let analyzer = AudioAnalyzer(sink: sink, clock: { clock.now })
        analyzer.apply(.started)
        for i in 1...30 {
            push(sink, amplitude: 0.5, seconds: 0.01)
            clock.now = Double(i) * 0.01
            analyzer.step()
        }
        let old = analyzer.step()
        XCTAssertTrue(old.hasVerifiedActiveAudio)
        sink.reset()
        let fresh = analyzer.beginAttempt()
        XCTAssertGreaterThan(fresh.sequence, old.sequence, "older updates can be told apart")
        XCTAssertEqual(fresh.state, .notStarted)
        XCTAssertNil(fresh.reason)
        XCTAssertFalse(fresh.hasVerifiedActiveAudio)
        XCTAssertEqual(fresh.levels, .silent)
        XCTAssertEqual(fresh.statistics, PCMSinkStatistics())
        XCTAssertEqual(fresh.sessionSeconds, 0)
        XCTAssertEqual(analyzer.transitions(from: 0), [])
        let failed = analyzer.apply(.startFailed(.permissionDenied))
        XCTAssertFalse(failed.hasVerifiedActiveAudio)
    }

    // MARK: - Session clock (review F7, F8)

    func testSessionClockForStampingEvents() {
        let sink = PCMSink()
        let clock = TestClock()
        clock.now = 100
        let analyzer = AudioAnalyzer(sink: sink, clock: { clock.now })
        clock.now = 101
        XCTAssertEqual(analyzer.currentSessionSeconds(), 1, "valid before any session")
        analyzer.beginAttempt()
        clock.now = 105
        XCTAssertEqual(analyzer.currentSessionSeconds(), 0, "0 while the start is pending")
        analyzer.apply(.started)   // session time 0: the source has started
        clock.now = 106.5
        XCTAssertEqual(analyzer.currentSessionSeconds(), 1.5)
        analyzer.apply(.userStopped)
        clock.now = 160
        XCTAssertEqual(analyzer.currentSessionSeconds(), 55, "keeps advancing after the stop")
    }
}

private final class UpdateCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AnalyzerUpdate] = []
    func append(_ u: AnalyzerUpdate) { lock.lock(); items.append(u); lock.unlock() }
    var all: [AnalyzerUpdate] { lock.lock(); defer { lock.unlock() }; return items }
}
