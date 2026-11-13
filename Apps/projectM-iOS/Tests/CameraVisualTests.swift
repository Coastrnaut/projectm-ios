// CameraVisualTests.swift — CAM-001-T14, T19, T21: the Camera visual's choice, persistence, host
// lifecycle and status-bar rule (CAM-001-R1, R6, R7, R10, R11, R13; S3, S4) with the stand-in camera.
// No test asks for real camera access: the AVFoundation provider is only checked where the device has
// no rear camera (the simulator), where it must not ask. Host tests need a Metal device and skip
// without one.
import AVFoundation
import CameraLayer
import Metal
import PresentationLifecycle
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class CameraVisualTests: XCTestCase {
    private func makeHost(_ scenario: CameraScenario) throws -> (CameraVisualHost, StubCameraFrameProvider) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        var stub: StubCameraFrameProvider?
        let host = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32) { device in
            let made = StubCameraFrameProvider(device: device, scenario: scenario)
            stub = made
            return made
        }
        return (host, try XCTUnwrap(stub))
    }

    // MARK: - Choice and persistence (T14; R1, R11, S4)

    func testCameraIsAChoiceThatReplacesProjectMButIsNotNative() {
        XCTAssertEqual(VisualChoice.camera.title, "Camera")
        XCTAssertEqual(VisualChoice.allCases.filter(\.isNative), [.circularSpectrum, .linearSpectrum])
        XCTAssertEqual(VisualChoice.allCases.filter(\.replacesProjectM), [.circularSpectrum, .linearSpectrum, .camera, .photo, .video])   // MED-001 adds Photo, MED-002 Video
        XCTAssertEqual(VisualChoice.allCases.filter(\.usesCamera), [.camera])
    }

    func testCameraChoiceIsNeverStoredOrRestored() throws {
        let suite = "CameraVisualTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        settings.visual = .linearSpectrum
        settings.visual = .camera
        XCTAssertEqual(settings.visual, .camera, "chosen for this session")
        XCTAssertEqual(defaults.string(forKey: AppSettings.visualKey), "linearSpectrum", "the key keeps the visual chosen before")
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).visual, .linearSpectrum, "a relaunch does not start the camera")
        defaults.set("camera", forKey: AppSettings.visualKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).visual, .projectM, "a stored camera reads as projectM")
    }

    func testHostCannotBeBuiltWithoutADevice() {
        XCTAssertThrowsError(try CameraVisualHost.make(device: nil, reader: nil, barCount: .b32),
                             "the coordinator then falls back to projectM with the unavailable notice")
    }

    // MARK: - Host lifecycle (T21; R7, S3)

    func testCameraRunsOnlyWhileTheHostRuns() throws {
        let (host, stub) = try makeHost(.granted)
        XCTAssertEqual(stub.state, .idle, "creating the visual does not start the camera")
        XCTAssertEqual(host.view.accessibilityIdentifier, "cameraVisual")
        XCTAssertEqual(host.view.accessibilityValue, "Off")
        host.resume()
        XCTAssertTrue(host.isRunning)
        XCTAssertEqual(stub.state, .running)
        XCTAssertEqual(host.feedState, .running)
        XCTAssertEqual(host.view.accessibilityValue, "Live")
        host.pause()
        XCTAssertEqual(stub.state, .idle, "pause stops the camera before returning")
        XCTAssertNil(stub.latestFrame(), "and drops the picture")
        host.resume()
        XCTAssertEqual(stub.state, .running, "resume starts it again")

        let registry = PresentationResourceRegistry()
        host.presentationResources.forEach(registry.register)
        registry.setCanPresent(false)
        XCTAssertEqual(stub.state, .idle, "presentation loss stops it (PERF-011)")
        registry.setCanPresent(true)
        XCTAssertEqual(stub.state, .running)

        host.appEnteredBackground()
        XCTAssertEqual(stub.state, .idle, "background stops it")
        host.appWillEnterForeground()
        XCTAssertEqual(stub.state, .running)

        host.sceneDidDisconnect()
        XCTAssertEqual(stub.state, .idle, "a disconnected scene stops it")
        host.sceneWillConnect()
        XCTAssertEqual(stub.state, .running)

        host.pause()
        host.appEnteredBackground()
        host.appWillEnterForeground()
        XCTAssertEqual(stub.state, .idle, "a pause survives a background round trip")
        XCTAssertEqual(stub.accessRequests, 0)
    }

    func testDeniedCameraKeepsTheVisualRunningAndReportsTheState() throws {
        let (host, stub) = try makeHost(.notDeterminedDeny)
        var reported: [CameraFeedState] = []
        host.onFeedStateChange = { reported.append($0) }
        host.resume()
        XCTAssertTrue(host.isRunning, "the spectrum keeps running (R5)")
        XCTAssertEqual(stub.accessRequests, 1, "asked once, on the user's choice")
        XCTAssertEqual(reported, [.requestingAccess, .denied])
        XCTAssertEqual(host.view.accessibilityValue, "Camera access off")
        host.pause()
        host.resume()
        XCTAssertEqual(stub.accessRequests, 1, "never asked again")
        XCTAssertEqual(host.feedState, .denied)
        host.pause()
    }

    func testStatusBarIsNeverHiddenWhileTheCameraIsShown() {
        XCTAssertTrue(AppCoordinator.systemOverlaysHidden(onVisualizer: true, controlsVisible: false, mode: .inAppPlayback, cameraShown: false))
        XCTAssertFalse(AppCoordinator.systemOverlaysHidden(onVisualizer: true, controlsVisible: false, mode: .inAppPlayback, cameraShown: true),
                       "R10: the camera indicator stays visible")
        XCTAssertFalse(AppCoordinator.systemOverlaysHidden(onVisualizer: true, controlsVisible: false, mode: .microphone, cameraShown: false))
    }

    // MARK: - The real provider without a camera (T19; R6)

    func testRealProviderWithoutARearCameraIsUnavailableWithoutAsking() throws {
        guard AVCameraFrameProvider.backCamera() == nil else {
            throw XCTSkip("This device has a rear camera; the device stage covers the real prompt.")
        }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let provider = AVCameraFrameProvider(device: device)
        provider.start()
        XCTAssertEqual(provider.state, .unavailable, "no prompt when there is no camera")
        XCTAssertNil(provider.latestFrame())
        provider.stop()
        XCTAssertEqual(provider.state, .idle)
    }
}
