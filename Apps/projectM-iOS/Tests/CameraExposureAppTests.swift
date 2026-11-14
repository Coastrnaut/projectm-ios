// CameraExposureAppTests.swift — CAM-004-T11: the Lock exposure row's notes and the host's exposure
// path with the stand-in camera (CAM-004-R2 to R9; S1 to S4). Simulator results are never device
// evidence. Host tests need a Metal device and skip without one.
import CameraLayer
import LibraryBackup
import Metal
import XCTest
@testable import projectM_iOS

@MainActor
final class CameraExposureAppTests: XCTestCase {
    /// Contract C4: the note per state (none while the switch can be used).
    func testNotesExplainWhyTheSwitchIsDisabled() {
        XCTAssertEqual(CameraExposureRow.note(for: .notRunning(canLock: false)), "This camera can't lock exposure.")
        XCTAssertEqual(CameraExposureRow.note(for: CameraExposureState(canLock: false, isRunning: true, mode: .continuousAuto)),
                       "This camera can't lock exposure.")
        XCTAssertEqual(CameraExposureRow.note(for: .notRunning(canLock: true)), "Exposure can be locked while the camera is running.")
        XCTAssertNil(CameraExposureRow.note(for: CameraExposureState(canLock: true, isRunning: true, mode: .locked)))
    }

    /// R8, S4: no stored setting for exposure.
    func testExposureIsNotStored() {
        let keys: [String] = AppSettings.allKeys + Array(LibrarySettingsPolicy.includedKeys)
        XCTAssertFalse(keys.contains { (key: String) -> Bool in key.lowercased().contains("exposure") })
    }

    private func makeHost(lockable: Set<FakeCameraKey>?) throws -> (CameraVisualHost, StubCameraFrameProvider) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let inventory = FixedCameraLensInventory([.wide, .ultraWide])
        var stub: StubCameraFrameProvider?
        let host = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32, lenses: inventory) {
            (device: MTLDevice) -> any CameraFrameProvider in
            let made = StubCameraFrameProvider(device: device, scenario: .granted, lensInventory: inventory, exposureLockCameras: lockable)
            stub = made
            return made
        }
        return (host, try XCTUnwrap(stub))
    }

    /// S1, R5, R7, R9: the host locks and releases the running camera, reports the read-back state,
    /// keeps the frame loop and camera running, and its stop releases the lock.
    func testHostLocksAndReleasesTheRunningCamera() throws {
        let (host, camera) = try makeHost(lockable: nil)
        var reported: [CameraExposureState] = []
        host.onExposureChange = { (state: CameraExposureState) -> Void in reported.append(state) }
        host.setCameraExposureLocked(true)
        XCTAssertFalse(host.cameraExposure.isLocked, "not running: nothing happens")
        host.resume()
        host.setCameraExposureLocked(true)
        XCTAssertTrue(host.cameraExposure.isLocked)
        XCTAssertEqual(reported.last?.mode, .locked)
        XCTAssertTrue(host.isRunning, "the frame loop kept running")
        XCTAssertEqual(camera.startCount, 1, "no restart")
        host.cameraLens = .ultraWide
        XCTAssertEqual(camera.session.exposureDevice(lens: .wide).currentExposureMode, .continuousAuto, "lens switch released it")
        XCTAssertFalse(host.cameraExposure.isLocked)
        host.setCameraExposureLocked(true)
        host.pause()
        XCTAssertEqual(camera.session.exposureDevice(lens: .ultraWide).currentExposureMode, .continuousAuto, "the stop released it")
        XCTAssertEqual(host.cameraExposure, .notRunning(canLock: true))
    }

    /// S2, R3: an unsupported camera is never configured.
    func testHostNeverConfiguresAnUnsupportedCamera() throws {
        let (host, camera) = try makeHost(lockable: [])
        host.resume()
        defer { host.pause() }
        host.setCameraExposureLocked(true)
        XCTAssertEqual(host.cameraExposure, CameraExposureState(canLock: false, isRunning: true, mode: .continuousAuto))
        XCTAssertEqual(camera.session.exposureDevice(lens: .wide).configurations, 0)
    }
}
