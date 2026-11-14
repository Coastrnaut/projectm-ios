// CAM-006-T07, T08: the white balance control routine, gain validation and the lock on a running
// stand-in camera (CAM-006-R2 to R12; S1 to S3). The routine tests are plain Swift (every platform,
// including the Linux shape); the stand-in provider tests need a Metal device.
import CameraLayer
import XCTest
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
#endif

final class CameraWhiteBalanceTests: XCTestCase {
    // MARK: Control routine (contract C2)

    func testLockAndUnlockChangeTheModeInsideOneConfigurationEach() {   // R4, R6, S1
        let device = FakeCameraWhiteBalanceDevice()
        XCTAssertEqual(CameraWhiteBalanceControl.lock(device), .locked)
        XCTAssertEqual(device.configurations, 1)
        XCTAssertEqual(device.lockedGains, CameraWhiteBalanceGains(red: 1.9, green: 1, blue: 2.2), "held at the current gains")
        XCTAssertEqual(CameraWhiteBalanceControl.lock(device), .locked, "already locked: nothing configured")
        XCTAssertEqual(device.configurations, 1)
        XCTAssertEqual(CameraWhiteBalanceControl.release(device), .continuousAuto)
        XCTAssertEqual(device.configurations, 2)
        XCTAssertEqual(CameraWhiteBalanceControl.release(device), .continuousAuto, "not locked: nothing configured")
        XCTAssertEqual(device.configurations, 2)
        XCTAssertEqual(device.changesOutsideConfiguration, 0)
        XCTAssertEqual(device.invalidGainsApplied, 0)
        XCTAssertEqual(CameraWhiteBalanceControl.state(of: device),
                       CameraWhiteBalanceState(canLock: true, isRunning: true, mode: .continuousAuto))
    }

    func testUnsupportedDeviceIsNeverConfigured() {   // R3, S2
        let device = FakeCameraWhiteBalanceDevice(canLock: false)
        XCTAssertEqual(CameraWhiteBalanceControl.lock(device), .continuousAuto)
        XCTAssertEqual(CameraWhiteBalanceControl.release(device), .continuousAuto)
        XCTAssertEqual(device.configurations, 0)
        XCTAssertFalse(CameraWhiteBalanceControl.state(of: device).isAdjustable)
    }

    func testRefusedConfigurationLeavesTheStateAsReadBack() {   // R6
        let device = FakeCameraWhiteBalanceDevice()
        device.refusesConfiguration = true
        XCTAssertEqual(CameraWhiteBalanceControl.lock(device), .continuousAuto, "busy device: unchanged")
        device.refusesConfiguration = false
        CameraWhiteBalanceControl.lock(device)
        device.refusesConfiguration = true
        XCTAssertEqual(CameraWhiteBalanceControl.release(device), .locked, "a refused release reports the lock")
    }

    /// R5, S2: invalid reported gains (or maximum) are clamped into range or refused; never handed to the camera.
    func testInvalidGainsAreClampedOrRefusedNeverApplied() {
        let nan = Float.nan, inf = Float.infinity
        let cases: [(gains: CameraWhiteBalanceGains, maximum: Float, expected: CameraWhiteBalanceGains?)] = [
            (CameraWhiteBalanceGains(red: 0.5, green: 1, blue: 2), 4, CameraWhiteBalanceGains(red: 1, green: 1, blue: 2)),
            (CameraWhiteBalanceGains(red: 4.01, green: 9, blue: 3), 4, CameraWhiteBalanceGains(red: 4, green: 4, blue: 3)),
            (CameraWhiteBalanceGains(red: -1, green: 0, blue: 5), 2.5, CameraWhiteBalanceGains(red: 1, green: 1, blue: 2.5)),
            (CameraWhiteBalanceGains(red: nan, green: 1, blue: 2), 4, nil),
            (CameraWhiteBalanceGains(red: 1, green: inf, blue: 2), 4, nil),
            (CameraWhiteBalanceGains(red: 1.5, green: 1, blue: 2), nan, nil),
            (CameraWhiteBalanceGains(red: 1.5, green: 1, blue: 2), 0.5, nil),
        ]
        for (index, item) in cases.enumerated() {
            XCTAssertEqual(item.gains.validated(maximum: item.maximum), item.expected, "case \(index)")
            let device = FakeCameraWhiteBalanceDevice(gains: item.gains, maximumGain: item.maximum)
            let mode: CameraWhiteBalanceMode = CameraWhiteBalanceControl.lock(device)
            XCTAssertEqual(device.invalidGainsApplied, 0, "case \(index): no invalid gain reached the camera")
            XCTAssertEqual(device.changesOutsideConfiguration, 0)
            if let expected = item.expected {
                XCTAssertEqual(mode, .locked, "case \(index): clamped and locked")
                XCTAssertEqual(device.lockedGains, expected)
                XCTAssertTrue(expected.isValid(maximum: item.maximum))
            } else {
                XCTAssertEqual(mode, .continuousAuto, "case \(index): refused")
                XCTAssertEqual(device.configurations, 0, "case \(index): nothing configured")
            }
        }
        let fake = FakeCameraWhiteBalanceDevice()
        XCTAssertTrue(fake.beginWhiteBalanceConfiguration())
        fake.applyWhiteBalanceLocked(gains: CameraWhiteBalanceGains(red: 7, green: 1, blue: 1))
        fake.endWhiteBalanceConfiguration()
        XCTAssertEqual(fake.invalidGainsApplied, 1, "the fake catches an invalid gain handed to it directly")
        XCTAssertEqual(fake.currentWhiteBalanceMode, .continuousAuto, "and does not apply it")
    }

    func testCameraWithoutCustomGainsLocksInPlace() {   // R4, Edge Cases
        let device = FakeCameraWhiteBalanceDevice(gains: CameraWhiteBalanceGains(red: .nan, green: 1, blue: 1),
                                                  supportsLockingWithGains: false)
        XCTAssertEqual(CameraWhiteBalanceControl.lock(device), .locked)
        XCTAssertNil(device.lockedGains, "no values passed")
        XCTAssertEqual(device.invalidGainsApplied, 0)
    }

    func testCameraWithoutContinuousModeKeepsTheReportedModeOnRelease() {   // Edge Cases
        let device = FakeCameraWhiteBalanceDevice()
        device.supportedModes = [.locked]
        CameraWhiteBalanceControl.lock(device)
        XCTAssertEqual(CameraWhiteBalanceControl.release(device), .locked)
        XCTAssertEqual(device.configurations, 1, "release made no configuration")
    }

    func testStateFlags() {
        XCTAssertFalse(CameraWhiteBalanceState.notRunning(canLock: true).isAdjustable)
        XCTAssertFalse(CameraWhiteBalanceState.notRunning(canLock: true).isLocked)
        XCTAssertTrue(CameraWhiteBalanceState(canLock: true, isRunning: true, mode: .locked).isLocked)
    }

    // MARK: Stand-in provider

    #if canImport(Metal) && !COMPOSITOR_NO_METAL
    private func makeProvider(lockable: Set<FakeCameraKey>? = nil,
                              lenses: [CameraLens] = [.wide, .ultraWide]) throws -> StubCameraFrameProvider {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "no Metal device")
        return StubCameraFrameProvider(device: device, scenario: .granted, lensInventory: FixedCameraLensInventory(lenses),
                                       whiteBalanceLockCameras: lockable)
    }

    func testLockAndUnlockOnARunningCameraAreReadBackAndReported() throws {   // US1, S1, R6, R11
        let provider = try makeProvider()
        let wide = provider.session.whiteBalanceDevice(lens: .wide)
        var reported: [CameraWhiteBalanceState] = []
        provider.onWhiteBalanceChange = { (state: CameraWhiteBalanceState) -> Void in reported.append(state) }
        XCTAssertEqual(provider.whiteBalance, .notRunning(canLock: true), "capability known before a start")
        provider.setWhiteBalanceLocked(true)
        XCTAssertEqual(wide.configurations, 0, "idle: nothing configured")
        provider.start()
        XCTAssertTrue(provider.whiteBalance.isAdjustable)
        provider.setWhiteBalanceLocked(true)
        XCTAssertTrue(provider.whiteBalance.isLocked)
        XCTAssertEqual(wide.currentWhiteBalanceMode, .locked)
        provider.setWhiteBalanceLocked(false)
        XCTAssertEqual(provider.whiteBalance.mode, .continuousAuto)
        XCTAssertEqual(reported.map(\.mode), [.continuousAuto, .locked, .continuousAuto], "running, locked, unlocked: once each")
        XCTAssertEqual(provider.startCount, 1, "no restart")
        XCTAssertEqual(provider.stopCount, 0)
        XCTAssertEqual(wide.changesOutsideConfiguration, 0)
        XCTAssertEqual(wide.invalidGainsApplied, 0)
    }

    func testLockSurvivesAnInterruption() throws {   // US2, R7, S3
        let provider = try makeProvider()
        provider.start()
        provider.setWhiteBalanceLocked(true)
        provider.interrupt(.otherInterruption)
        XCTAssertFalse(provider.whiteBalance.isAdjustable, "interrupted: disabled")
        XCTAssertEqual(provider.session.whiteBalanceDevice(lens: .wide).currentWhiteBalanceMode, .locked, "kept on the camera")
        provider.endInterruption()
        XCTAssertTrue(provider.whiteBalance.isLocked, "read back as locked when running again")
    }

    func testUnsupportedCameraMakesNoLockCall() throws {   // US3, R3, S2
        let provider = try makeProvider(lockable: [])
        XCTAssertFalse(provider.whiteBalance.canLock)
        provider.start()
        provider.setWhiteBalanceLocked(true)
        XCTAssertEqual(provider.whiteBalance, CameraWhiteBalanceState(canLock: false, isRunning: true, mode: .continuousAuto))
        XCTAssertEqual(provider.session.whiteBalanceDevice(lens: .wide).configurations, 0)
    }

    func testLensAndPositionSwitchesAndStopsReleaseTheLock() throws {   // US2, R8, R9, S3
        let provider = try makeProvider(lockable: [FakeCameraKey(lens: .wide), FakeCameraKey(lens: .wide, position: .front)])
        let wide = provider.session.whiteBalanceDevice(lens: .wide)
        provider.start()
        provider.setWhiteBalanceLocked(true)
        provider.selectLens(.ultraWide)
        XCTAssertEqual(wide.currentWhiteBalanceMode, .continuousAuto, "the previous lens was released")
        XCTAssertEqual(provider.whiteBalance, CameraWhiteBalanceState(canLock: false, isRunning: true, mode: .continuousAuto),
                       "ultra wide here cannot lock")
        provider.selectLens(.wide)
        provider.setWhiteBalanceLocked(true)
        provider.select(.front)
        XCTAssertEqual(wide.currentWhiteBalanceMode, .continuousAuto, "a position switch released it")
        XCTAssertEqual(provider.whiteBalance, CameraWhiteBalanceState(canLock: true, isRunning: true, mode: .continuousAuto))
        provider.setWhiteBalanceLocked(true)
        let front = provider.session.whiteBalanceDevice(lens: .wide, position: .front)
        provider.stop()
        XCTAssertEqual(front.currentWhiteBalanceMode, .continuousAuto, "a stop released it")
        XCTAssertEqual(provider.whiteBalance, .notRunning(canLock: true))
        provider.start()
        provider.setWhiteBalanceLocked(true)
        provider.fail()
        XCTAssertEqual(front.currentWhiteBalanceMode, .continuousAuto, "a failure released it")
        XCTAssertFalse(provider.whiteBalance.isLocked)
        XCTAssertEqual(front.changesOutsideConfiguration + wide.changesOutsideConfiguration, 0)
    }
    #endif
}
