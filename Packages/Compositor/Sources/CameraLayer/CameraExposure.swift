// CameraExposure.swift — locking and releasing a camera's exposure (CAM-004-R2 to R7; research
// CAM-004-D1, D2; contracts/exposure-lock.md C1, C2).
//
// One platform-free routine, written against `CameraExposureConfiguring`, which `AVCaptureDevice`
// conforms to on iOS (AVCameraLensInventory.swift) and `FakeCameraExposureDevice` implements for the
// stand-in camera and tests. So the code that locks the real camera is the code the Mac tests run.
//
// * Unsupported or already in the wanted mode: nothing is configured (CAM-004-R3).
// * Otherwise one configuration (`begin` … `end`) sets the mode; when the configuration cannot be
//   taken (the device is busy), nothing changes.
// * The result is always the mode read back from the device, never the mode asked for (R5).
// The routine never throws and never traps. Exposure is session state: nothing here is stored (R8).
import Foundation

/// The exposure mode a camera reports (data-model.md).
public enum CameraExposureMode: String, Sendable, Equatable {
    /// The exposure is held where it is.
    case locked
    /// The camera adjusts its exposure continuously.
    case continuousAuto
    /// Any other mode the camera reports (single automatic adjustment, custom).
    case other
}

/// The current camera's exposure as the app shows it (data-model.md; main-thread mirror).
public struct CameraExposureState: Sendable, Equatable {
    /// The current camera supports locked exposure.
    public var canLock: Bool
    /// The camera runs; exposure can change only then (CAM-004-R2).
    public var isRunning: Bool
    /// The mode read back from the camera (`continuousAuto` while not running).
    public var mode: CameraExposureMode

    public init(canLock: Bool, isRunning: Bool, mode: CameraExposureMode) {
        self.canLock = canLock
        self.isRunning = isRunning
        self.mode = mode
    }

    /// A camera that is not running (every start begins with automatic exposure, R8).
    public static func notRunning(canLock: Bool) -> CameraExposureState {
        CameraExposureState(canLock: canLock, isRunning: false, mode: .continuousAuto)
    }

    /// True when the camera reports locked exposure.
    public var isLocked: Bool { isRunning && mode == .locked }

    /// The switch is enabled: the camera runs and can lock (R2).
    public var isAdjustable: Bool { canLock && isRunning }
}

/// The part of a camera device an exposure change needs (contract C1).
public protocol CameraExposureConfiguring: AnyObject {
    /// The device supports the mode (`other` is never asked for).
    func supportsExposure(_ mode: CameraExposureMode) -> Bool
    /// The mode the device reports now.
    var currentExposureMode: CameraExposureMode { get }
    /// Takes the device's configuration; false when it cannot be taken.
    func beginExposureConfiguration() -> Bool
    /// Sets the mode (only between a successful begin and its end).
    func applyExposureMode(_ mode: CameraExposureMode)
    /// Gives the configuration back.
    func endExposureConfiguration()
}

public enum CameraExposureControl {
    /// Locks the exposure when the device supports it (contract C2); returns the mode read back.
    @discardableResult
    public static func lock<Device: CameraExposureConfiguring>(_ device: Device) -> CameraExposureMode {
        set(.locked, on: device)
    }

    /// Returns a locked device to continuous automatic exposure (C2); returns the mode read back.
    @discardableResult
    public static func release<Device: CameraExposureConfiguring>(_ device: Device) -> CameraExposureMode {
        guard device.currentExposureMode == .locked else { return device.currentExposureMode }
        return set(.continuousAuto, on: device)
    }

    /// The state of a running device.
    public static func state<Device: CameraExposureConfiguring>(of device: Device) -> CameraExposureState {
        CameraExposureState(canLock: device.supportsExposure(.locked), isRunning: true, mode: device.currentExposureMode)
    }

    private static func set<Device: CameraExposureConfiguring>(_ mode: CameraExposureMode, on device: Device) -> CameraExposureMode {
        guard mode != .other, device.supportsExposure(mode), device.currentExposureMode != mode else {
            return device.currentExposureMode
        }
        guard device.beginExposureConfiguration() else { return device.currentExposureMode }
        device.applyExposureMode(mode)
        device.endExposureConfiguration()
        return device.currentExposureMode
    }
}

/// A camera device stand-in (CAM-004-R10): which modes it supports, whether its configuration can be
/// taken, and counts of configurations and of mode changes made outside one (should stay 0).
public final class FakeCameraExposureDevice: CameraExposureConfiguring {
    public var supportedModes: Set<CameraExposureMode>
    /// The configuration cannot be taken (`lockForConfiguration` throws).
    public var refusesConfiguration = false
    public private(set) var currentExposureMode: CameraExposureMode = .continuousAuto
    public private(set) var configurations = 0
    public private(set) var changesOutsideConfiguration = 0
    private var configuring = false

    /// `canLock` false: a camera without locked exposure (it still adjusts automatically).
    public init(canLock: Bool = true) {
        supportedModes = canLock ? [.locked, .continuousAuto] : [.continuousAuto]
    }

    public func supportsExposure(_ mode: CameraExposureMode) -> Bool { supportedModes.contains(mode) }

    public func beginExposureConfiguration() -> Bool {
        guard !refusesConfiguration else { return false }
        configuring = true
        configurations += 1
        return true
    }

    public func applyExposureMode(_ mode: CameraExposureMode) {
        if !configuring { changesOutsideConfiguration += 1 }
        guard supportedModes.contains(mode) else { return }   // AVFoundation would raise; the fake refuses
        currentExposureMode = mode
    }

    public func endExposureConfiguration() {
        configuring = false
    }
}
