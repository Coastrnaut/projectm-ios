// AUD-015-T08, T10: the app's side of the background policy. The shipped Info.plist declares no
// `audio` background mode and the app offers no "keep playing" (AUD-015-R3); the return notice is
// hidden while the scene is inactive and while a stop or pause reason shows (R7); rendering and
// every presentation-bound resource are suspended while away in every mode, and an unlock in the
// background resumes neither them nor the microphone (R5, R8).
import AudioCore
import CaptureKit
import PresentationLifecycle
import XCTest
@testable import projectM_iOS

@MainActor
final class BackgroundPolicyAppTests: XCTestCase {
    // MARK: - Configuration (R3)

    func testTheShippedAppDeclaresOnlyScreenCaptureAndNoKeepPlaying() {
        let modes: [String] = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] ?? []
        XCTAssertEqual(modes, ["screen-capture"], "ADR-0001 ruling 17")
        let configuration = AppCoordinator.backgroundConfiguration(infoDictionary: Bundle.main.infoDictionary)
        XCTAssertEqual(configuration, .shipped)
    }

    func testAnAudioModeWouldBeReadButKeepPlayingStaysOff() {
        let info: [String: Any] = ["UIBackgroundModes": ["screen-capture", "audio"]]
        let configuration = AppCoordinator.backgroundConfiguration(infoDictionary: info)
        XCTAssertTrue(configuration.declaresAudioBackgroundMode)
        XCTAssertFalse(configuration.keepPlayingInBackground, "no setting: the wish is never assumed")
        XCTAssertEqual(AppCoordinator.backgroundConfiguration(infoDictionary: nil), .shipped)
    }

    // MARK: - Notice visibility (R7)

    func testTheNoticeShowsOnlyWhenActiveAndNoReasonShows() {
        let reason: BackgroundPolicy.Reason = .microphoneStoppedInBackground
        XCTAssertEqual(AppCoordinator.visibleBackgroundNotice(reason: reason, sceneActive: true, stopReasonShown: false),
                       reason.notice)
        XCTAssertNil(AppCoordinator.visibleBackgroundNotice(reason: reason, sceneActive: false, stopReasonShown: false))
        XCTAssertNil(AppCoordinator.visibleBackgroundNotice(reason: reason, sceneActive: true, stopReasonShown: true))
        XCTAssertNil(AppCoordinator.visibleBackgroundNotice(reason: nil, sceneActive: true, stopReasonShown: false))
        XCTAssertNil(AppCoordinator.visibleBackgroundNotice(reason: .systemCaptureFollowsSystem, sceneActive: true,
                                                            stopReasonShown: false))
    }

    // MARK: - Rendering stops while away (R8)

    final class Source: AudioSource {
        let mode: AudioSourceMode
        var availability: SourceAvailability = .available
        private(set) var resumes = 0
        init(_ mode: AudioSourceMode) { self.mode = mode }
        func start(into sink: PCMSink) async throws -> AsyncStream<SourceEvent> {
            AsyncStream.makeStream(of: SourceEvent.self).stream
        }
        func stop() async {}
        func suspend() async {}
        func resume() async throws { resumes += 1 }
    }

    final class Visualization: VisualizationControlling {
        var userPaused = false
        private(set) var suspended = false
        func suspendVisualization() { suspended = true }
        func resumeVisualization() { suspended = false }
    }

    final class Resource: PresentationBoundResource {
        let presentationResourceName = "frame loop"
        private(set) var suspended = false
        func suspendForPresentationLoss() { suspended = true }
        func resumeForPresentation() { suspended = false }
    }

    func testRenderingIsSuspendedWhileAwayInEveryMode() async {
        for mode in AudioSourceMode.allCases {
            for event in [AppLifecycleEvent.background, .lock] {
                let source = Source(mode)
                let manager = CaptureManager(sources: [source], runsAnalysisTimer: false)
                let visualization = Visualization()
                let resource = Resource()
                let coordinator = LifecycleCoordinator(manager: manager, visualization: visualization)
                coordinator.presentation.register(resource)
                await manager.select(mode)
                coordinator.visualizationStarted()
                await coordinator.handle(event)
                let label = "\(mode) \(event)"
                XCTAssertTrue(visualization.suspended, label)
                XCTAssertTrue(resource.suspended, label)
                XCTAssertEqual(coordinator.presentation.activeCount, 0, label)
            }
        }
    }

    func testAnUnlockInTheBackgroundResumesNeitherRenderingNorTheMicrophone() async {
        let source = Source(.microphone)
        let manager = CaptureManager(sources: [source], runsAnalysisTimer: false)
        let visualization = Visualization()
        let resource = Resource()
        let coordinator = LifecycleCoordinator(manager: manager, visualization: visualization)
        coordinator.presentation.register(resource)
        await manager.select(.microphone)
        coordinator.visualizationStarted()
        await coordinator.handle(.background)
        await coordinator.handle(.lock)
        await coordinator.handle(.unlock)
        XCTAssertTrue(visualization.suspended)
        XCTAssertTrue(resource.suspended)
        XCTAssertEqual(source.resumes, 0)
        XCTAssertEqual(manager.backgroundNotice, .microphoneStoppedInBackground)
        await coordinator.handle(.foreground)
        XCTAssertFalse(visualization.suspended)
        XCTAssertFalse(resource.suspended)
        XCTAssertEqual(source.resumes, 1)
    }
}
