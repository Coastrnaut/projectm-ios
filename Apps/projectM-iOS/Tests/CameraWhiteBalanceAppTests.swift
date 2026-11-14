// CameraWhiteBalanceAppTests.swift — CAM-006-T11: the Lock white balance row's notes and the host's white
// balance path with the stand-in camera (CAM-006-R2 to R11; S1 to S4). Simulator results are never device
// evidence. Host tests need a Metal device and skip without one.
import CameraLayer
import LibraryBackup
import Metal
import XCTest
@testable import projectM_iOS

@MainActor
final class CameraWhiteBalanceAppTests: XCTestCase {
    /// Contract C4: the note per state (none while the switch can be used).
    func testNotesExplainWhyTheSwitchIsDisabled() {
        XCTAssertEqual(CameraWhiteBalanceRow.note(for: .notRunning(canLock: false)), "This camera can't lock white balance.")
        XCTAssertEqual(CameraWhiteBalanceRow.note(for: CameraWhiteBalanceState(canLock: false, isRunning: true, mode: .continuousAuto)),
                       "This camera can't lock white balance.")
        XCTAssertEqual(CameraWhiteBalanceRow.note(for: .notRunning(canLock: true)),
                       "White balance can be locked while the camera is running.")
        XCTAssertNil(CameraWhiteBalanceRow.note(for: CameraWhiteBalanceState(canLock: true, isRunning: true, mode: .locked)))
    }

    /// R10, S4: no stored setting for white balance.
    func testWhiteBalanceIsNotStored() {
        let keys: [String] = AppSettings.allKeys + Array(LibrarySettingsPolicy.includedKeys)
        XCTAssertFalse(keys.contains { (key: String) -> Bool in key.lowercased().contains("whitebalance") })
    }

    private func makeHost(lockable: Set<FakeCameraKey>?) throws -> (CameraVisualHost, StubCameraFrameProvider) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let inventory = FixedCameraLensInventory([.wide, .ultraWide])
        var stub: StubCameraFrameProvider?
        let host = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32, lenses: inventory) {
            (device: MTLDevice) -> any CameraFrameProvider in
            let made = StubCameraFrameProvider(device: device, scenario: .granted, lensInventory: inventory,
                                               whiteBalanceLockCameras: lockable)
            stub = made
            return made
        }
        return (host, try XCTUnwrap(stub))
    }

    /// S1, R6, R9, R11: the host locks and releases the running camera, reports the read-back state, keeps
    /// the frame loop and camera running; a lens switch and the host's stop release the lock.
    func testHostLocksAndReleasesTheRunningCamera() throws {
        let (host, camera) = try makeHost(lockable: nil)
        var reported: [CameraWhiteBalanceState] = []
        host.onWhiteBalanceChange = { (state: CameraWhiteBalanceState) -> Void in reported.append(state) }
        host.setCameraWhiteBalanceLocked(true)
        XCTAssertFalse(host.cameraWhiteBalance.isLocked, "not running: nothing happens")
        host.resume()
        host.setCameraWhiteBalanceLocked(true)
        XCTAssertTrue(host.cameraWhiteBalance.isLocked)
        XCTAssertEqual(reported.last?.mode, .locked)
        XCTAssertTrue(host.isRunning, "the frame loop kept running")
        XCTAssertEqual(camera.startCount, 1, "no restart")
        host.cameraLens = .ultraWide
        XCTAssertEqual(camera.session.whiteBalanceDevice(lens: .wide).currentWhiteBalanceMode, .continuousAuto, "lens switch released it")
        XCTAssertFalse(host.cameraWhiteBalance.isLocked)
        host.setCameraWhiteBalanceLocked(true)
        host.pause()
        XCTAssertEqual(camera.session.whiteBalanceDevice(lens: .ultraWide).currentWhiteBalanceMode, .continuousAuto, "the stop released it")
        XCTAssertEqual(host.cameraWhiteBalance, .notRunning(canLock: true))
        XCTAssertEqual(camera.session.whiteBalanceDevice(lens: .wide).invalidGainsApplied, 0)
    }

    /// S2, R3: an unsupported camera is never configured.
    func testHostNeverConfiguresAnUnsupportedCamera() throws {
        let (host, camera) = try makeHost(lockable: [])
        host.resume()
        defer { host.pause() }
        host.setCameraWhiteBalanceLocked(true)
        XCTAssertEqual(host.cameraWhiteBalance, CameraWhiteBalanceState(canLock: false, isRunning: true, mode: .continuousAuto))
        XCTAssertEqual(camera.session.whiteBalanceDevice(lens: .wide).configurations, 0)
    }
}
