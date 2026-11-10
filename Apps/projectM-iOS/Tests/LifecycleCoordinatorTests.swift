// Task T098: the data-model lifecycle matrix for each adapter, through LifecycleCoordinator.
//
// | Event              | System/App Capture            | Microphone                  | In-App Playback              |
// | Background / lock  | continues                     | paused (source suspended)   | paused (source suspended)    |
// | Foreground         | as above                      | auto-resume ≤ 2 s           | auto-resume ≤ 2 s            |
// | Interruption       | no change                     | interrupted → auto-resume   | interrupted → auto-resume    |
//                                                        or one-tap restart            or one-tap restart
// | Route change       | n/a                           | microphoneUnavailable       | paused (audioRouteChanged)   |
// | OS ends session    | endedBySystem                 | n/a                         | n/a                          |
// In every mode the visualization suspends on background/lock and resumes on return, unless the
// user had paused it (FR-046, FR-050, FR-054).
import AudioCore
import CaptureKit
import XCTest
@testable import projectM_iOS

@MainActor
final class LifecycleCoordinatorTests: XCTestCase {
    /// A minimal source: records suspend/resume and emits events on demand.
    final class StubSource: AudioSource {
        let mode: AudioSourceMode
        var availability: SourceAvailability = .available
        private(set) var suspends = 0
        private(set) var resumes = 0
        private var continuation: AsyncStream<SourceEvent>.Continuation?
        init(_ mode: AudioSourceMode) { self.mode = mode }
        func start(into sink: PCMSink) async throws -> AsyncStream<SourceEvent> {
            let (stream, continuation) = AsyncStream.makeStream(of: SourceEvent.self)
            self.continuation = continuation
            return stream
        }
        func stop() async { continuation?.finish(); continuation = nil }
        func suspend() async { suspends += 1 }
        func resume() async throws { resumes += 1 }
        func emit(_ event: SourceEvent) { continuation?.yield(event) }
    }

    /// Records what the coordinator asked of the visualization.
    final class FakeVisualization: VisualizationControlling {
        var userPaused = false
        private(set) var suspended = false
        private(set) var calls: [String] = []
        func suspendVisualization() { suspended = true; calls.append("suspend") }
        func resumeVisualization() { suspended = false; calls.append("resume") }
    }

    private var sources: [AudioSourceMode: StubSource] = [:]
    private var manager: CaptureManager!
    private var visualization: FakeVisualization!
    private var coordinator: LifecycleCoordinator!

    override func setUp() async throws {
        reset()
    }

    /// A fresh manager, sources, visualization and coordinator.
    private func reset() {
        sources = Dictionary(uniqueKeysWithValues: AudioSourceMode.allCases.map { ($0, StubSource($0)) })
        manager = CaptureManager(sources: Array(sources.values), runsAnalysisTimer: false)
        visualization = FakeVisualization()
        coordinator = LifecycleCoordinator(manager: manager, visualization: visualization)
    }

    private func start(_ mode: AudioSourceMode) async {
        await manager.select(mode)
        coordinator.visualizationStarted()
        XCTAssertEqual(manager.state, .waiting)
    }

    /// Lets queued source-event handling run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<20 { await Task.yield() }
    }

    // MARK: - Background / lock (FR-050, FR-054)

    func testBackgroundAndLockSuspendTheVisualizationInEveryMode() async {
        for mode in AudioSourceMode.allCases {
            for event in [AppLifecycleEvent.background, .lock] {
                reset()   // fresh manager per case
                await start(mode)
                await coordinator.handle(event)
                XCTAssertTrue(visualization.suspended, "\(mode) \(event): visualization suspended")
            }
        }
    }

    func testSystemCaptureContinuesInTheBackground() async {
        await start(.systemAppCapture)
        await coordinator.handle(.background)
        XCTAssertEqual(manager.state, .waiting, "System/App Capture continues (RI-003)")
        XCTAssertEqual(sources[.systemAppCapture]?.suspends, 0)
    }

    func testMicrophoneAndInAppPausesInTheBackground() async {
        for mode in [AudioSourceMode.microphone, .inAppPlayback] {
            reset()
            await start(mode)
            await coordinator.handle(.lock)
            XCTAssertEqual(manager.state, .paused, "\(mode)")
            XCTAssertEqual(sources[mode]?.suspends, 1)
        }
    }

    // MARK: - Foreground: auto-resume within 2 s

    func testForegroundResumesWithinTwoSeconds() async {
        for mode in [AudioSourceMode.microphone, .inAppPlayback] {
            reset()
            await start(mode)
            await coordinator.handle(.background)
            let began = Date()
            await coordinator.handle(.foreground)
            XCTAssertLessThan(Date().timeIntervalSince(began), 2, "\(mode): resume ≤ 2 s")
            XCTAssertEqual(sources[mode]?.resumes, 1)
            XCTAssertNotEqual(manager.state, .paused)
            XCTAssertFalse(visualization.suspended, "\(mode): visualization resumed")
        }
    }

    func testForegroundKeepsAUserPauseOfTheVisualization() async {
        await start(.inAppPlayback)
        visualization.userPaused = true
        await coordinator.handle(.background)
        await coordinator.handle(.foreground)
        XCTAssertFalse(visualization.calls.contains("resume"), "a user pause stays (FR-046)")
    }

    // MARK: - Interruption

    func testInterruptionLeavesSystemCaptureAlone() async {
        await start(.systemAppCapture)
        sources[.systemAppCapture]?.emit(.interruptionBegan)
        await settle()
        XCTAssertEqual(manager.state, .waiting)
    }

    func testInterruptionAutoResumesOrNeedsRestart() async {
        for mode in [AudioSourceMode.microphone, .inAppPlayback] {
            reset()
            await start(mode)
            sources[mode]?.emit(.interruptionBegan)
            await settle()
            XCTAssertEqual(manager.state, .interrupted, "\(mode)")
            sources[mode]?.emit(.interruptionEnded(shouldResume: true))
            await settle()
            XCTAssertNotEqual(manager.state, .interrupted, "\(mode): auto-resume")

            sources[mode]?.emit(.interruptionBegan)
            sources[mode]?.emit(.interruptionEnded(shouldResume: false))
            await settle()
            XCTAssertEqual(manager.state, .interrupted, "\(mode): no auto-resume, one-tap restart")
            XCTAssertEqual(manager.stopReason, .interrupted)
        }
    }

    // MARK: - Route change and OS end

    func testRouteChange() async {
        await start(.inAppPlayback)
        sources[.inAppPlayback]?.emit(.outputRouteLost)
        await settle()
        XCTAssertEqual(manager.state, .paused)
        XCTAssertEqual(manager.stopReason, .audioRouteChanged)

        reset()
        await start(.microphone)
        sources[.microphone]?.emit(.failed(.microphoneUnavailable))
        await settle()
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertEqual(manager.stopReason, .microphoneUnavailable)
    }

    func testOSEndsTheCaptureSession() async {
        await start(.systemAppCapture)
        sources[.systemAppCapture]?.emit(.endedBySystem(nil))
        await settle()
        XCTAssertEqual(manager.state, .endedBySystem)
    }

    func testNoVisualizationMeansNothingToSuspend() async {
        await coordinator.handle(.background)
        XCTAssertEqual(visualization.calls, [], "the chooser has no visualization")
    }
}
