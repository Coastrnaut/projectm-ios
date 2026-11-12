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
//
// PERF-011 (T13, T17): the same events suspend and resume the presentation-bound resources in the
// registry, in every mode and on the chooser; an unlock while still in the background resumes
// nothing; entering the foreground clears a lock. The capture matrix above is unchanged.
import AudioCore
import CaptureKit
import PresentationLifecycle
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
        var log: ((String) -> Void)?
        func suspendVisualization() { suspended = true; calls.append("suspend"); log?("suspend visualization") }
        func resumeVisualization() { suspended = false; calls.append("resume"); log?("resume visualization") }
    }

    /// A presentation-bound resource that records its calls into a shared log (PERF-011).
    final class FakeResource: PresentationBoundResource {
        let presentationResourceName: String
        private let log: (String) -> Void
        private(set) var suspended = false
        private(set) var suspends = 0
        private(set) var resumes = 0
        init(_ name: String, log: @escaping (String) -> Void) {
            presentationResourceName = name
            self.log = log
        }
        func suspendForPresentationLoss() { suspended = true; suspends += 1; log("suspend \(presentationResourceName)") }
        func resumeForPresentation() { suspended = false; resumes += 1; log("resume \(presentationResourceName)") }
    }

    /// Calls of the visualization and the resources, in order.
    private var order: [String] = []
    private var loop: FakeResource!
    private var warmUp: FakeResource!
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
        order = []
        visualization.log = { [weak self] in self?.order.append($0) }
        // Registered the way AppCoordinator registers the renderer: frame loop, then warm-up.
        loop = FakeResource("loop") { [weak self] in self?.order.append($0) }
        warmUp = FakeResource("warm-up") { [weak self] in self?.order.append($0) }
        coordinator.presentation.register(loop)
        coordinator.presentation.register(warmUp)
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

    // MARK: - PERF-011: presentation-bound resources (R1, R3, R10, R11)

    func testBackgroundAndLockSuspendTheResourcesInEveryMode() async {
        for mode in AudioSourceMode.allCases {
            for event in [AppLifecycleEvent.background, .lock] {
                reset()
                await start(mode)
                await coordinator.handle(event)
                XCTAssertTrue(coordinator.suspended)
                XCTAssertEqual(order, ["suspend visualization", "suspend warm-up", "suspend loop"], "\(mode) \(event)")
                XCTAssertEqual(coordinator.presentation.activeCount, 0, "\(mode) \(event): nothing active")
            }
        }
    }

    func testTheChooserStillSuspendsRegisteredResources() async {
        await coordinator.handle(.background)
        XCTAssertEqual(order, ["suspend warm-up", "suspend loop"], "no visualization, but the resources are released")
        await coordinator.handle(.foreground)
        XCTAssertEqual(order, ["suspend warm-up", "suspend loop", "resume loop", "resume warm-up"])
        XCTAssertEqual(visualization.calls, [])
    }

    func testForegroundResumesTheResourcesBeforeTheVisualization() async {
        await start(.inAppPlayback)
        await coordinator.handle(.background)
        order = []
        await coordinator.handle(.foreground)
        XCTAssertEqual(order, ["resume loop", "resume warm-up", "resume visualization"])
        XCTAssertFalse(coordinator.suspended)
        XCTAssertEqual(coordinator.presentation.activeCount, 2)
    }

    func testAUserPauseKeepsTheVisualizationPausedButResumesTheResources() async {
        await start(.inAppPlayback)
        visualization.userPaused = true
        await coordinator.handle(.background)
        order = []
        await coordinator.handle(.foreground)
        XCTAssertEqual(order, ["resume loop", "resume warm-up"], "the renderer keeps its own pause (FR-046)")
    }

    func testUnlockWhileStillInTheBackgroundResumesNothing() async {
        await start(.microphone)
        await coordinator.handle(.background)
        await coordinator.handle(.lock)
        order = []
        await coordinator.handle(.unlock)   // another app is in front
        XCTAssertEqual(order, [], "the app still cannot present frames")
        XCTAssertTrue(coordinator.suspended)
        XCTAssertTrue(visualization.suspended)
        XCTAssertEqual(coordinator.presentation.activeCount, 0)
        // The capture layer still receives the event, as before this feature.
        XCTAssertEqual(sources[.microphone]?.resumes, 1)

        await coordinator.handle(.foreground)
        XCTAssertEqual(order, ["resume loop", "resume warm-up", "resume visualization"])
    }

    func testForegroundClearsALockWithoutAnUnlockEvent() async {
        await start(.inAppPlayback)
        await coordinator.handle(.background)
        await coordinator.handle(.lock)
        await coordinator.handle(.foreground)
        XCTAssertFalse(coordinator.suspended, "entering the foreground proves frames can be presented")
        XCTAssertFalse(visualization.suspended)
        await coordinator.handle(.unlock)   // late: nothing more happens
        XCTAssertEqual(loop.suspends, 1)
        XCTAssertEqual(loop.resumes, 1)
        XCTAssertEqual(visualization.calls, ["suspend", "resume"])
    }

    func testLockThenUnlockInTheForeground() async {
        await start(.inAppPlayback)
        await coordinator.handle(.lock)
        XCTAssertTrue(loop.suspended)
        await coordinator.handle(.unlock)
        XCTAssertFalse(loop.suspended)
        XCTAssertEqual(visualization.calls, ["suspend", "resume"])
    }

    func testRepeatedAndRapidEventsCallEachResourceOncePerTransition() async {
        await start(.systemAppCapture)
        await coordinator.handle(.background)
        await coordinator.handle(.background)
        await coordinator.handle(.lock)
        XCTAssertEqual(loop.suspends, 1)
        XCTAssertEqual(warmUp.suspends, 1)
        XCTAssertEqual(visualization.calls, ["suspend"])
        await coordinator.handle(.foreground)
        await coordinator.handle(.foreground)
        XCTAssertEqual(loop.resumes, 1)
        XCTAssertEqual(visualization.calls, ["suspend", "resume"])
        for _ in 0..<10 {
            await coordinator.handle(.background)
            await coordinator.handle(.foreground)
        }
        XCTAssertEqual(loop.suspends, 11)
        XCTAssertEqual(loop.resumes, 11)
        XCTAssertEqual(warmUp.suspends, 11)
        XCTAssertEqual(warmUp.resumes, 11)
        XCTAssertFalse(loop.suspended)
        XCTAssertEqual(sources[.systemAppCapture]?.suspends, 0, "System/App Capture is never suspended (RI-003)")
    }

    func testAResourceRegisteredInTheBackgroundStartsSuspended() async {
        await coordinator.handle(.background)
        let camera = FakeResource("camera") { [weak self] in self?.order.append($0) }
        coordinator.presentation.register(camera)
        XCTAssertTrue(camera.suspended)
        await coordinator.handle(.foreground)
        XCTAssertFalse(camera.suspended)
        XCTAssertEqual(camera.resumes, 1)
    }

    func testAVisualizationStartedWhileSuspendedResumesOnForeground() async {
        await coordinator.handle(.background)
        await start(.inAppPlayback)
        await coordinator.handle(.foreground)
        XCTAssertEqual(visualization.calls, ["resume"])
    }
}
