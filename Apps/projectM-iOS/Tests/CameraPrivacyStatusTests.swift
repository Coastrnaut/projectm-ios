// CameraPrivacyStatusTests.swift — CAM-012-T06, T09: the in-app camera indicator follows the camera
// feed, Stop camera stops the camera once and for good, the fallback visual is the one chosen before
// Camera, and the frame loop keeps running after Stop (CAM-012-R1 to R8; S1, S2, S4). Stand-in
// cameras only; no real permission is asked. Waits are expectations with generous ceilings, never
// wall-clock assertions. Host tests need a Metal device and skip without one.
import CameraLayer
import Metal
import PresentationLifecycle
import UIKit
import XCTest
@testable import projectM_iOS

/// A camera that stays in `.starting` (the stub passes through it synchronously).
private final class StartingCameraProvider: CameraFrameProvider {
    var state: CameraFeedState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((CameraFeedState) -> Void)?
    var startCount = 0
    var stopCount = 0
    func start() {
        guard state == .idle else { return }
        startCount += 1
        state = .starting
    }
    func stop() {
        guard state != .idle else { return }
        stopCount += 1
        state = .idle
    }
    func latestFrame() -> CameraFrame? { nil }
}

@MainActor
final class CameraPrivacyStatusTests: XCTestCase {
    private func makeHost(_ scenario: CameraScenario) throws -> (CameraVisualHost, StubCameraFrameProvider) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        var stub: StubCameraFrameProvider?
        let host = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32) { (device: MTLDevice) -> any CameraFrameProvider in
            let made = StubCameraFrameProvider(device: device, scenario: scenario)
            stub = made
            return made
        }
        return (host, try XCTUnwrap(stub))
    }

    /// Fulfils when `condition` holds, checking every 50 ms on the main run loop; fails after `timeout`.
    private func wait(_ description: String, timeout: TimeInterval = 10, until condition: @escaping @MainActor () -> Bool) {
        let done = expectation(description: description)
        var fulfilled = false
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { (_: Timer) in
            MainActor.assumeIsolated {
                if !fulfilled, condition() {
                    fulfilled = true
                    done.fulfill()
                }
            }
        }
        wait(for: [done], timeout: timeout)
        timer.invalidate()
    }

    // MARK: - Indicator (T06; R1, R2, R9, S1)

    func testIndicatorIsShownOnlyWhileStartingOrRunning() {
        let all: [CameraFeedState] = [.idle, .requestingAccess, .starting, .running, .denied, .restricted, .unavailable, .interrupted, .failed]
        XCTAssertEqual(all.filter { CameraIndicator(state: $0).isShown }, [.starting, .running])
        XCTAssertEqual(CameraIndicator(state: .running).accessibilityValue, "Live")
        XCTAssertEqual(CameraIndicator(state: .starting).accessibilityValue, "Starting")
        XCTAssertFalse(CameraIndicator.hidden.isShown)
        XCTAssertEqual(CameraIndicator.label, "Camera on")
        XCTAssertEqual(CameraIndicator.stopTitle, "Stop camera")
    }

    func testIndicatorFollowsTheFeedThroughStartInterruptionPauseAndBackground() throws {
        let (host, stub) = try makeHost(.granted)
        var shown: [Bool] = []
        host.onFeedStateChange = { (state: CameraFeedState) in shown.append(CameraIndicator(state: state).isShown) }
        host.resume()
        XCTAssertTrue(CameraIndicator(state: host.feedState).isShown, "start → shown")
        stub.interrupt()
        XCTAssertFalse(CameraIndicator(state: host.feedState).isShown, "interruption → hidden")
        stub.endInterruption()
        XCTAssertTrue(CameraIndicator(state: host.feedState).isShown, "frames flow again → shown")
        host.pause()
        XCTAssertFalse(CameraIndicator(state: host.feedState).isShown, "pause → hidden")
        host.resume()
        host.appEnteredBackground()
        XCTAssertFalse(CameraIndicator(state: host.feedState).isShown, "background → hidden")
        host.appWillEnterForeground()
        XCTAssertTrue(CameraIndicator(state: host.feedState).isShown, "foreground → shown again")
        XCTAssertEqual(shown.last, true)
        XCTAssertFalse(shown.isEmpty)
        host.pause()
    }

    func testDeniedCameraShowsNoIndicator() throws {
        let (host, _) = try makeHost(.denied)
        host.resume()
        XCTAssertEqual(host.feedState, .denied)
        XCTAssertFalse(CameraIndicator(state: host.feedState).isShown)
        host.pause()
    }

    // MARK: - Stop camera (T09; R4, R6, S2, S4)

    func testStopCameraStopsTheProviderOnceDropsThePictureAndNeverRestarts() throws {
        let made = try makeHost(.granted)
        var host: CameraVisualHost? = made.0
        let stub = made.1
        var reported: [CameraFeedState] = []
        host?.onFeedStateChange = { (state: CameraFeedState) in reported.append(state) }
        host?.resume()
        XCTAssertEqual(stub.state, .running)
        XCTAssertNotNil(stub.latestFrame())

        host?.stopCamera()
        XCTAssertEqual(stub.stopCount, 1, "the provider is stopped once")
        XCTAssertEqual(stub.state, .idle, "before stopCamera() returns")
        XCTAssertEqual(host?.feedState, .idle, "and the host already reports it, so the badge goes")
        XCTAssertEqual(reported.last, .idle)
        XCTAssertNil(stub.latestFrame(), "the last picture is dropped")
        XCTAssertTrue(host?.isRunning ?? false, "the frame loop keeps running")

        host?.pause()
        host?.resume()
        host?.appEnteredBackground()
        host?.appWillEnterForeground()
        host?.sceneDidDisconnect()
        host?.sceneWillConnect()
        let registry = PresentationResourceRegistry()
        host?.presentationResources.forEach(registry.register)
        registry.setCanPresent(false)
        registry.setCanPresent(true)
        XCTAssertEqual(stub.state, .idle, "nothing restarts a stopped camera")
        XCTAssertEqual(stub.startCount, 1)

        host?.pause()
        host = nil   // the coordinator releases the host after Stop
        XCTAssertEqual(stub.stopCount, 1, "releasing the host does not stop it a second time")
    }

    func testStopWhileStartingStopsItAndKeepsItOff() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let provider = StartingCameraProvider()
        let host = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32) { (_: MTLDevice) -> any CameraFrameProvider in provider }
        host.resume()
        XCTAssertEqual(host.feedState, .starting)
        XCTAssertTrue(CameraIndicator(state: host.feedState).isShown, "starting shows the badge")
        host.stopCamera()
        XCTAssertEqual(provider.stopCount, 1)
        XCTAssertEqual(host.feedState, .idle)
        host.pause()
        host.resume()
        XCTAssertEqual(provider.startCount, 1, "not started again")
        host.pause()
    }

    // MARK: - Fallback visual (T09; R5, R8)

    func testFallbackIsTheVisualChosenBeforeCameraAndNothingIsWritten() throws {
        let suite = "CameraPrivacyStatusTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.visualBeforeCamera, .projectM, "nothing chosen yet → projectM")
        settings.visual = .circularSpectrum
        settings.visual = .camera
        let before = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("settings.") }.mapValues { "\($0)" }
        XCTAssertEqual(settings.visualBeforeCamera, .circularSpectrum)
        let after = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("settings.") }.mapValues { "\($0)" }
        XCTAssertEqual(before, after, "reading the fallback writes nothing")
        defaults.set("camera", forKey: AppSettings.visualKey)
        XCTAssertEqual(settings.visualBeforeCamera, .projectM, "a stored camera never comes back")
    }

    // MARK: - No freeze (T09; acceptance "without freeze")

    func testFrameLoopKeepsCompositingAfterStopCamera() throws {
        let (host, stub) = try makeHost(.granted)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        host.view.frame = window.bounds
        window.addSubview(host.view)
        window.isHidden = false
        defer {
            host.pause()
            host.view.removeFromSuperview()
            window.isHidden = true
        }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        host.resume()

        wait("frames with the camera") { host.framesComposited > 2 && host.framesShown > 0 }
        host.stopCamera()
        XCTAssertEqual(stub.state, .idle)
        let composited = host.framesComposited, shown = host.framesShown
        wait("frames after Stop camera") { host.framesComposited > composited + 2 }
        XCTAssertEqual(host.framesShown, shown, "no camera picture after Stop")
        XCTAssertEqual(stub.stopCount, 1)
    }
}
