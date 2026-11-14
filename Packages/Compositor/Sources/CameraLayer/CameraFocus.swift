// CameraFocus.swift — setting and resetting a camera's focus point (CAM-005-R4, R5, R8, R12; research
// CAM-005-D3; contracts/focus-point.md C2).
//
// One platform-free routine, written against `CameraFocusConfiguring`, which `AVCaptureDevice`
// conforms to on iOS (AVCameraLensInventory.swift) and `FakeCameraFocusDevice` implements for the
// stand-in camera and tests (as CAM-004's exposure seam), so the code that focuses the real camera is
// the code the Mac tests run.
//
// * Unsupported (no point of interest, or neither automatic mode): nothing is configured (R5).
// * Otherwise one configuration (`begin` … `end`) sets the point, then single-shot automatic focus when
//   supported, else continuous automatic focus (R4). A refused configuration changes nothing.
// * Reset: continuous automatic focus at the centre, only when something differs (R8).
// * The result is always the state read back from the device (R12). Nothing is stored (R9).

/// The focus mode a camera reports.
public enum CameraFocusMode: String, Sendable, Equatable {
    /// One automatic focus at the point, then held.
    case autoFocus
    /// The camera refocuses continuously.
    case continuousAuto
    /// The lens is held where it is.
    case locked
    /// Anything else the camera reports.
    case other
}

/// The current camera's focus as the app shows it (data-model.md; main-thread mirror).
public struct CameraFocusState: Sendable, Equatable {
    /// The current camera can focus on a point (CAM-005-R5).
    public var canFocus: Bool
    /// The camera runs; focus can change only then.
    public var isRunning: Bool
    /// Read back from the camera (`continuousAuto` while not running).
    public var mode: CameraFocusMode
    /// Read back from the camera (`centre` while not running).
    public var point: CameraFocusPoint

    public init(canFocus: Bool, isRunning: Bool, mode: CameraFocusMode, point: CameraFocusPoint) {
        self.canFocus = canFocus
        self.isRunning = isRunning
        self.mode = mode
        self.point = point
    }

    /// A camera that is not running (every start begins with continuous focus at the centre).
    public static func notRunning(canFocus: Bool) -> CameraFocusState {
        CameraFocusState(canFocus: canFocus, isRunning: false, mode: .continuousAuto, point: .centre)
    }

    /// A tap can focus now.
    public var isAdjustable: Bool { canFocus && isRunning }
}

/// The part of a camera device a focus change needs (contract C2).
public protocol CameraFocusConfiguring: AnyObject {
    /// The device accepts a focus point of interest.
    var supportsFocusPoint: Bool { get }
    /// The device supports the mode (`other` is never asked for).
    func supportsFocus(_ mode: CameraFocusMode) -> Bool
    var currentFocusMode: CameraFocusMode { get }
    var currentFocusPoint: CameraFocusPoint { get }
    /// Takes the device's configuration; false when it cannot be taken.
    func beginFocusConfiguration() -> Bool
    /// Sets the point, then the mode (only between a successful begin and its end).
    func applyFocus(point: CameraFocusPoint, mode: CameraFocusMode)
    /// Gives the configuration back.
    func endFocusConfiguration()
}

public enum CameraFocusControl {
    /// The device can focus on a point: point of interest plus an automatic mode.
    public static func canFocus<Device: CameraFocusConfiguring>(_ device: Device) -> Bool {
        device.supportsFocusPoint && (device.supportsFocus(.autoFocus) || device.supportsFocus(.continuousAuto))
    }

    /// Focuses at `point` (contract C2); returns the state read back.
    @discardableResult
    public static func focus<Device: CameraFocusConfiguring>(at point: CameraFocusPoint, on device: Device) -> CameraFocusState {
        guard canFocus(device) else { return state(of: device) }
        let mode: CameraFocusMode = device.supportsFocus(.autoFocus) ? .autoFocus : .continuousAuto
        guard device.beginFocusConfiguration() else { return state(of: device) }
        device.applyFocus(point: point, mode: mode)
        device.endFocusConfiguration()
        return state(of: device)
    }

    /// Returns the device to continuous automatic focus at the centre (R8); nothing when already there
    /// or unsupported. Returns the state read back.
    @discardableResult
    public static func reset<Device: CameraFocusConfiguring>(_ device: Device) -> CameraFocusState {
        let atRest: Bool = device.currentFocusMode == .continuousAuto && device.currentFocusPoint.isClose(to: .centre)
        guard !atRest, device.supportsFocus(.continuousAuto) else { return state(of: device) }
        let point: CameraFocusPoint = device.supportsFocusPoint ? .centre : device.currentFocusPoint
        guard device.beginFocusConfiguration() else { return state(of: device) }
        device.applyFocus(point: point, mode: .continuousAuto)
        device.endFocusConfiguration()
        return state(of: device)
    }

    /// The state of a running device.
    public static func state<Device: CameraFocusConfiguring>(of device: Device) -> CameraFocusState {
        CameraFocusState(canFocus: canFocus(device), isRunning: true, mode: device.currentFocusMode,
                         point: device.currentFocusPoint)
    }
}

/// A camera device stand-in (CAM-005-R11): point support, supported modes, whether its configuration
/// can be taken, and counts of configurations and of changes made outside one (should stay 0).
public final class FakeCameraFocusDevice: CameraFocusConfiguring {
    public var supportsFocusPoint: Bool
    public var supportedModes: Set<CameraFocusMode>
    /// The configuration cannot be taken (`lockForConfiguration` throws).
    public var refusesConfiguration = false
    public private(set) var currentFocusMode: CameraFocusMode = .continuousAuto
    public private(set) var currentFocusPoint: CameraFocusPoint = .centre
    public private(set) var configurations = 0
    public private(set) var changesOutsideConfiguration = 0
    private var configuring = false

    /// `canFocusOnPoint` false: a fixed-focus or point-less camera (it still focuses automatically).
    public init(canFocusOnPoint: Bool = true, modes: Set<CameraFocusMode> = [.autoFocus, .continuousAuto, .locked]) {
        supportsFocusPoint = canFocusOnPoint
        supportedModes = modes
    }

    public func supportsFocus(_ mode: CameraFocusMode) -> Bool { supportedModes.contains(mode) }

    public func beginFocusConfiguration() -> Bool {
        guard !refusesConfiguration else { return false }
        configuring = true
        configurations += 1
        return true
    }

    public func applyFocus(point: CameraFocusPoint, mode: CameraFocusMode) {
        if !configuring { changesOutsideConfiguration += 1 }
        if supportsFocusPoint { currentFocusPoint = point }   // AVFoundation would raise; the fake refuses
        if supportedModes.contains(mode) { currentFocusMode = mode }
    }

    public func endFocusConfiguration() {
        configuring = false
    }
}
