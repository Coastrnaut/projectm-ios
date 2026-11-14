// CAM-004-T07, T14: the exposure control routine and exposure lock on a running stand-in camera
// (CAM-004-R2 to R10; S1 to S3). The routine tests are plain Swift (every platform, including the Linux
// shape); the stand-in provider tests need a Metal device.
import CameraLayer
import XCTest
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
#endif

final class CameraExposureTests: XCTestCase {
    // MARK: Control routine (contract C2)

    func testLockAndReleaseChangeTheModeInsideOneConfigurationEach() {   // R4, R5
        let device = FakeCameraExposureDevice()
        XCTAssertEqual(CameraExposureControl.lock(device), .locked)
        XCTAssertEqual(device.configurations, 1)
        XCTAssertEqual(CameraExposureControl.lock(device), .locked, "already locked: nothing configured")
        XCTAssertEqual(device.configurations, 1)
        XCTAssertEqual(CameraExposureControl.release(device), .continuousAuto)
        XCTAssertEqual(device.configurations, 2)
        XCTAssertEqual(CameraExposureControl.release(device), .continuousAuto, "not locked: nothing configured")
        XCTAssertEqual(device.configurations, 2)
        XCTAssertEqual(device.changesOutsideConfiguration, 0)
        XCTAssertEqual(CameraExposureControl.state(of: device), CameraExposureState(canLock: true, isRunning: true, mode: .continuousAuto))
    }

    func testUnsupportedDeviceIsNeverConfigured() {   // R3, S2
        let device = FakeCameraExposureDevice(canLock: false)
        XCTAssertEqual(CameraExposureControl.lock(device), .continuousAuto)
        XCTAssertEqual(device.configurations, 0)
        XCTAssertFalse(CameraExposureControl.state(of: device).isAdjustable)
    }

    func testRefusedConfigurationLeavesTheStateAsReadBack() {   // R5
        let device = FakeCameraExposureDevice()
        device.refusesConfiguration = true
        XCTAssertEqual(CameraExposureControl.lock(device), .continuousAuto, "busy device: unchanged")
        device.refusesConfiguration = false
        CameraExposureControl.lock(device)
        device.refusesConfiguration = true
        XCTAssertEqual(CameraExposureControl.release(device), .locked, "a refused release reports the lock")
    }

    func testStateFlags() {
        XCTAssertFalse(CameraExposureState.notRunning(canLock: true).isAdjustable)
        XCTAssertFalse(CameraExposureState.notRunning(canLock: true).isLocked)
        XCTAssertTrue(CameraExposureState(canLock: true, isRunning: true, mode: .locked).isLocked)
        XCTAssertEqual(FakeCameraKey.list("wide, front,none,macro"),
                       [FakeCameraKey(lens: .wide), FakeCameraKey(lens: .telephoto, position: .front)], "front is always wide")
    }

    // MARK: Stand-in provider

    #if canImport(Metal) && !COMPOSITOR_NO_METAL
    private func makeProvider(lockable: Set<FakeCameraKey>? = nil,
                              lenses: [CameraLens] = [.wide, .ultraWide]) throws -> StubCameraFrameProvider {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "no Metal device")
        return StubCameraFrameProvider(device: device, scenario: .granted, lensInventory: FixedCameraLensInventory(lenses),
                                       exposureLockCameras: lockable)
    }

    func testLockAndUnlockOnARunningCameraAreReadBackAndReported() throws {   // US1, S1, R9
        let provider = try makeProvider()
        var reported: [CameraExposureState] = []
        provider.onExposureChange = { (state: CameraExposureState) -> Void in reported.append(state) }
        XCTAssertEqual(provider.exposure, .notRunning(canLock: true), "capability known before a start")
        provider.setExposureLocked(true)
        XCTAssertEqual(provider.session.exposureDevice(lens: .wide).configurations, 0, "idle: nothing configured")
        provider.start()
        XCTAssertTrue(provider.exposure.isAdjustable)
        provider.setExposureLocked(true)
        XCTAssertTrue(provider.exposure.isLocked)
        XCTAssertEqual(provider.session.exposureDevice(lens: .wide).currentExposureMode, .locked)
        provider.setExposureLocked(false)
        XCTAssertEqual(provider.exposure.mode, .continuousAuto)
        XCTAssertEqual(reported.map(\.mode), [.continuousAuto, .locked, .continuousAuto], "running, locked, unlocked: once each")
        XCTAssertEqual(provider.startCount, 1, "no restart")
        XCTAssertEqual(provider.stopCount, 0)
        XCTAssertEqual(provider.session.exposureDevice(lens: .wide).changesOutsideConfiguration, 0)
        provider.setExposureLocked(true)
        provider.interrupt()
        XCTAssertFalse(provider.exposure.isAdjustable, "interrupted: disabled")
        provider.endInterruption()
        XCTAssertTrue(provider.exposure.isLocked, "the lock stayed on the camera through the interruption")
    }

    func testUnsupportedCameraExplainsAndMakesNoLockCall() throws {   // US2, R3, S2
        let provider = try makeProvider(lockable: [])
        XCTAssertFalse(provider.exposure.canLock)
        provider.start()
        provider.setExposureLocked(true)
        XCTAssertEqual(provider.exposure, CameraExposureState(canLock: false, isRunning: true, mode: .continuousAuto))
        XCTAssertEqual(provider.session.exposureDevice(lens: .wide).configurations, 0)
    }

    func testLensAndPositionSwitchesAndStopsReleaseTheLock() throws {   // US3, R6, R7, S3
        let provider = try makeProvider(lockable: [FakeCameraKey(lens: .wide), FakeCameraKey(lens: .wide, position: .front)])
        let wide = provider.session.exposureDevice(lens: .wide)
        provider.start()
        provider.setExposureLocked(true)
        provider.selectLens(.ultraWide)
        XCTAssertEqual(wide.currentExposureMode, .continuousAuto, "the previous lens was released")
        XCTAssertEqual(provider.exposure, CameraExposureState(canLock: false, isRunning: true, mode: .continuousAuto),
                       "ultra wide here cannot lock")
        provider.selectLens(.wide)
        provider.setExposureLocked(true)
        provider.select(.front)
        XCTAssertEqual(wide.currentExposureMode, .continuousAuto, "a position switch released it")
        XCTAssertEqual(provider.exposure, CameraExposureState(canLock: true, isRunning: true, mode: .continuousAuto))
        provider.setExposureLocked(true)
        let front = provider.session.exposureDevice(lens: .wide, position: .front)
        provider.stop()
        XCTAssertEqual(front.currentExposureMode, .continuousAuto, "a stop released it")
        XCTAssertEqual(provider.exposure, .notRunning(canLock: true))
        provider.start()
        provider.setExposureLocked(true)
        provider.fail()
        XCTAssertEqual(front.currentExposureMode, .continuousAuto, "a failure released it")
        XCTAssertFalse(provider.exposure.isLocked)
    }
    #endif
}
