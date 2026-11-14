// CameraWhiteBalance.swift — locking and releasing a camera's white balance (CAM-006-R2 to R6, R12;
// research CAM-006-D1, D2; contracts/white-balance-lock.md C1, C2).
//
// One platform-free routine, written against `CameraWhiteBalanceConfiguring`, which `AVCaptureDevice`
// conforms to on iOS (AVCameraLensInventory.swift) and `FakeCameraWhiteBalanceDevice` implements for the
// stand-in camera and tests (as CAM-004's exposure seam), so the code that locks the real camera is the
// code the Mac tests run.
//
// * Unsupported or already in the wanted mode: nothing is configured (R3).
// * A lock at given values passes only gains made valid by `validated(maximum:)` (each channel clamped
//   into 1…maximum); a non-finite gain or maximum refuses the lock and nothing is configured (R5).
//   A camera that cannot take given values is locked in place, without values (R4).
// * Otherwise one configuration (`begin` … `end`) per change; a refused configuration changes nothing.
// * The result is always the mode read back from the device (R6). Nothing is stored (R10).

/// The white balance mode a camera reports (data-model.md).
public enum CameraWhiteBalanceMode: String, Sendable, Equatable {
    /// The white balance is held where it is.
    case locked
    /// The camera adjusts its white balance continuously.
    case continuousAuto
    /// Any other mode the camera reports (single automatic adjustment).
    case other
}

/// The camera's per-channel white balance gains (data-model.md).
public struct CameraWhiteBalanceGains: Sendable, Equatable {
    public var red: Float
    public var green: Float
    public var blue: Float

    public init(red: Float, green: Float, blue: Float) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Every channel is finite and within 1…`maximum` (what the camera accepts).
    public func isValid(maximum: Float) -> Bool {
        let channels: [Float] = [red, green, blue]
        return maximum.isFinite && maximum >= 1 && channels.allSatisfy { (gain: Float) -> Bool in
            gain.isFinite && gain >= 1 && gain <= maximum
        }
    }

    /// Research CAM-006-D2: nil when `maximum` is not finite or below 1, or any channel is not finite;
    /// otherwise each channel clamped to 1…`maximum`.
    public func validated(maximum: Float) -> CameraWhiteBalanceGains? {
        guard maximum.isFinite, maximum >= 1, red.isFinite, green.isFinite, blue.isFinite else { return nil }
        let clamp: (Float) -> Float = { (gain: Float) -> Float in min(max(gain, 1), maximum) }
        return CameraWhiteBalanceGains(red: clamp(red), green: clamp(green), blue: clamp(blue))
    }

    /// Neutral gains (every channel 1).
    public static let unity = CameraWhiteBalanceGains(red: 1, green: 1, blue: 1)
}

/// The current camera's white balance as the app shows it (data-model.md; main-thread mirror).
public struct CameraWhiteBalanceState: Sendable, Equatable {
    /// The current camera supports locked white balance.
    public var canLock: Bool
    /// The camera runs; white balance can change only then (CAM-006-R2).
    public var isRunning: Bool
    /// The mode read back from the camera (`continuousAuto` while not running).
    public var mode: CameraWhiteBalanceMode

    public init(canLock: Bool, isRunning: Bool, mode: CameraWhiteBalanceMode) {
        self.canLock = canLock
        self.isRunning = isRunning
        self.mode = mode
    }

    /// A camera that is not running.
    public static func notRunning(canLock: Bool) -> CameraWhiteBalanceState {
        CameraWhiteBalanceState(canLock: canLock, isRunning: false, mode: .continuousAuto)
    }

    /// True when the running camera reports locked white balance.
    public var isLocked: Bool { isRunning && mode == .locked }

    /// The switch is enabled: the camera runs and can lock (R2).
    public var isAdjustable: Bool { canLock && isRunning }
}

/// The part of a camera device a white balance change needs (contract C1).
public protocol CameraWhiteBalanceConfiguring: AnyObject {
    /// The device supports the mode (`other` is never asked for).
    func supportsWhiteBalance(_ mode: CameraWhiteBalanceMode) -> Bool
    /// The mode the device reports now.
    var currentWhiteBalanceMode: CameraWhiteBalanceMode { get }
    /// The gains the device reports now (may be slightly out of range).
    var currentWhiteBalanceGains: CameraWhiteBalanceGains { get }
    /// The largest gain the device accepts.
    var maximumWhiteBalanceGain: Float { get }
    /// The device can be locked at given gains.
    var supportsLockingWithGains: Bool { get }
    /// Takes the device's configuration; false when it cannot be taken.
    func beginWhiteBalanceConfiguration() -> Bool
    /// Locks at `gains` (valid ones only), or in place when nil (only between a successful begin and its end).
    func applyWhiteBalanceLocked(gains: CameraWhiteBalanceGains?)
    /// Returns to continuous automatic white balance (only between a successful begin and its end).
    func applyWhiteBalanceContinuous()
    /// Gives the configuration back.
    func endWhiteBalanceConfiguration()
}

public enum CameraWhiteBalanceControl {
    /// Locks the white balance at the current, validated gains (contract C2); returns the mode read back.
    @discardableResult
    public static func lock<Device: CameraWhiteBalanceConfiguring>(_ device: Device) -> CameraWhiteBalanceMode {
        guard device.supportsWhiteBalance(.locked), device.currentWhiteBalanceMode != .locked else {
            return device.currentWhiteBalanceMode
        }
        var gains: CameraWhiteBalanceGains?
        if device.supportsLockingWithGains {
            guard let valid = device.currentWhiteBalanceGains.validated(maximum: device.maximumWhiteBalanceGain) else {
                return device.currentWhiteBalanceMode   // R5: refused, nothing configured
            }
            gains = valid
        }
        guard device.beginWhiteBalanceConfiguration() else { return device.currentWhiteBalanceMode }
        device.applyWhiteBalanceLocked(gains: gains)
        device.endWhiteBalanceConfiguration()
        return device.currentWhiteBalanceMode
    }

    /// Returns a locked device to continuous automatic white balance (C2); returns the mode read back.
    @discardableResult
    public static func release<Device: CameraWhiteBalanceConfiguring>(_ device: Device) -> CameraWhiteBalanceMode {
        guard device.currentWhiteBalanceMode == .locked, device.supportsWhiteBalance(.continuousAuto) else {
            return device.currentWhiteBalanceMode
        }
        guard device.beginWhiteBalanceConfiguration() else { return device.currentWhiteBalanceMode }
        device.applyWhiteBalanceContinuous()
        device.endWhiteBalanceConfiguration()
        return device.currentWhiteBalanceMode
    }

    /// The state of a running device.
    public static func state<Device: CameraWhiteBalanceConfiguring>(of device: Device) -> CameraWhiteBalanceState {
        CameraWhiteBalanceState(canLock: device.supportsWhiteBalance(.locked), isRunning: true,
                                mode: device.currentWhiteBalanceMode)
    }
}

/// A camera device stand-in (CAM-006-R12): supported modes, reported gains and maximum, whether it can be
/// locked at given gains and whether its configuration can be taken, with counts of configurations, of
/// changes made outside one and of invalid gains it was handed (all should stay 0 where expected).
public final class FakeCameraWhiteBalanceDevice: CameraWhiteBalanceConfiguring {
    public var supportedModes: Set<CameraWhiteBalanceMode>
    /// The gains the device reports (tests set out-of-range or non-finite values).
    public var currentWhiteBalanceGains: CameraWhiteBalanceGains
    public var maximumWhiteBalanceGain: Float
    public var supportsLockingWithGains: Bool
    /// The configuration cannot be taken (`lockForConfiguration` throws).
    public var refusesConfiguration = false
    public private(set) var currentWhiteBalanceMode: CameraWhiteBalanceMode = .continuousAuto
    /// The gains the last lock held (nil: never locked at given gains).
    public private(set) var lockedGains: CameraWhiteBalanceGains?
    public private(set) var configurations = 0
    public private(set) var changesOutsideConfiguration = 0
    /// Gains handed to a lock that the device would reject (AVFoundation raises; the fake refuses them).
    public private(set) var invalidGainsApplied = 0
    private var configuring = false

    /// `canLock` false: a camera without locked white balance (it still adjusts automatically).
    public init(canLock: Bool = true, gains: CameraWhiteBalanceGains = CameraWhiteBalanceGains(red: 1.9, green: 1, blue: 2.2),
                maximumGain: Float = 4, supportsLockingWithGains: Bool = true) {
        supportedModes = canLock ? [.locked, .continuousAuto] : [.continuousAuto]
        currentWhiteBalanceGains = gains
        maximumWhiteBalanceGain = maximumGain
        self.supportsLockingWithGains = supportsLockingWithGains
    }

    public func supportsWhiteBalance(_ mode: CameraWhiteBalanceMode) -> Bool { supportedModes.contains(mode) }

    public func beginWhiteBalanceConfiguration() -> Bool {
        guard !refusesConfiguration else { return false }
        configuring = true
        configurations += 1
        return true
    }

    public func applyWhiteBalanceLocked(gains: CameraWhiteBalanceGains?) {
        if !configuring { changesOutsideConfiguration += 1 }
        guard supportedModes.contains(.locked) else { return }
        if let gains {
            guard supportsLockingWithGains, gains.isValid(maximum: maximumWhiteBalanceGain) else {
                invalidGainsApplied += 1
                return
            }
            lockedGains = gains
            currentWhiteBalanceGains = gains
        }
        currentWhiteBalanceMode = .locked
    }

    public func applyWhiteBalanceContinuous() {
        if !configuring { changesOutsideConfiguration += 1 }
        guard supportedModes.contains(.continuousAuto) else { return }
        currentWhiteBalanceMode = .continuousAuto
    }

    public func endWhiteBalanceConfiguration() {
        configuring = false
    }
}
