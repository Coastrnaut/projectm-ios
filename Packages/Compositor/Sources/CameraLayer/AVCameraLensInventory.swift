// AVCameraLensInventory.swift — the device's back lenses from AVFoundation (CAM-003-R1, R3;
// research CAM-003-D1). iOS only.
//
// A DiscoverySession for the three physical back lens types: no virtual multi-lens camera is asked
// for, so none is ever offered. Discovery needs no authorization, opens no camera and captures
// nothing (R3). The list is read on demand (no cache that could go stale).
#if canImport(AVFoundation) && os(iOS)
import AVFoundation

public final class AVCameraLensInventory: CameraLensInventory {
    public init() {}

    /// The device types asked for, one per lens.
    static func deviceType(for lens: CameraLens) -> AVCaptureDevice.DeviceType {
        switch lens {
        case .ultraWide: .builtInUltraWideCamera
        case .wide: .builtInWideAngleCamera
        case .telephoto: .builtInTelephotoCamera
        }
    }

    static func lens(of type: AVCaptureDevice.DeviceType) -> CameraLens? {
        switch type {
        case .builtInUltraWideCamera: .ultraWide
        case .builtInWideAngleCamera: .wide
        case .builtInTelephotoCamera: .telephoto
        default: nil
        }
    }

    public var backLenses: [CameraLens] {
        let types: [AVCaptureDevice.DeviceType] = CameraLens.allCases.map(Self.deviceType(for:))
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .back)
        let found: [CameraLens] = discovery.devices.compactMap { (device: AVCaptureDevice) -> CameraLens? in
            Self.lens(of: device.deviceType)
        }
        return CameraLens.ordered(found)
    }

    /// The back camera of a lens kind, if this device has it.
    public static func backCamera(_ lens: CameraLens) -> AVCaptureDevice? {
        AVCaptureDevice.default(deviceType(for: lens), for: .video, position: .back)
    }
}

extension AVCaptureSession: CameraInputConfiguring {
    public typealias Input = AVCaptureInput
    public var configuredInputs: [AVCaptureInput] { inputs }
}

/// CAM-004 (contract C1; research CAM-004-D1): the device's exposure through the documented
/// `lockForConfiguration` / `unlockForConfiguration` pair. Called on the provider's session queue.
extension AVCaptureDevice: CameraExposureConfiguring {
    static func avMode(_ mode: CameraExposureMode) -> AVCaptureDevice.ExposureMode? {
        switch mode {
        case .locked: .locked
        case .continuousAuto: .continuousAutoExposure
        case .other: nil
        }
    }

    public func supportsExposure(_ mode: CameraExposureMode) -> Bool {
        Self.avMode(mode).map { (avMode: AVCaptureDevice.ExposureMode) -> Bool in isExposureModeSupported(avMode) } ?? false
    }

    public var currentExposureMode: CameraExposureMode {
        switch exposureMode {
        case .locked: .locked
        case .continuousAutoExposure: .continuousAuto
        default: .other
        }
    }

    public func beginExposureConfiguration() -> Bool {
        (try? lockForConfiguration()) != nil
    }

    public func applyExposureMode(_ mode: CameraExposureMode) {
        guard let avMode = Self.avMode(mode), isExposureModeSupported(avMode) else { return }
        exposureMode = avMode
    }

    public func endExposureConfiguration() {
        unlockForConfiguration()
    }
}
/// CAM-005 (contract C2; research CAM-005-D3): the device's focus point and mode through the documented
/// `lockForConfiguration` / `unlockForConfiguration` pair; the point is set before the mode, as
/// AVFoundation applies a point when the mode is set. Called on the provider's session queue.
extension AVCaptureDevice: CameraFocusConfiguring {
    static func avFocusMode(_ mode: CameraFocusMode) -> AVCaptureDevice.FocusMode? {
        switch mode {
        case .autoFocus: .autoFocus
        case .continuousAuto: .continuousAutoFocus
        case .locked: .locked
        case .other: nil
        }
    }

    public var supportsFocusPoint: Bool { isFocusPointOfInterestSupported }

    public func supportsFocus(_ mode: CameraFocusMode) -> Bool {
        Self.avFocusMode(mode).map { (avMode: AVCaptureDevice.FocusMode) -> Bool in isFocusModeSupported(avMode) } ?? false
    }

    public var currentFocusMode: CameraFocusMode {
        switch focusMode {
        case .autoFocus: .autoFocus
        case .continuousAutoFocus: .continuousAuto
        case .locked: .locked
        default: .other
        }
    }

    public var currentFocusPoint: CameraFocusPoint {
        let point: CGPoint = focusPointOfInterest
        return CameraFocusPoint(x: Double(point.x), y: Double(point.y))
    }

    public func beginFocusConfiguration() -> Bool {
        (try? lockForConfiguration()) != nil
    }

    public func applyFocus(point: CameraFocusPoint, mode: CameraFocusMode) {
        if isFocusPointOfInterestSupported { focusPointOfInterest = CGPoint(x: point.x, y: point.y) }
        guard let avMode = Self.avFocusMode(mode), isFocusModeSupported(avMode) else { return }
        focusMode = avMode
    }

    public func endFocusConfiguration() {
        unlockForConfiguration()
    }
}

/// CAM-006 (contract C1; research CAM-006-D1): the device's white balance through the documented
/// `lockForConfiguration` / `unlockForConfiguration` pair. Gains are re-checked against
/// `maxWhiteBalanceGain` right before `setWhiteBalanceModeLocked(with:)`, which raises on any gain
/// outside 1…maximum (R5). Called on the provider's session queue.
extension AVCaptureDevice: CameraWhiteBalanceConfiguring {
    static func avWhiteBalanceMode(_ mode: CameraWhiteBalanceMode) -> AVCaptureDevice.WhiteBalanceMode? {
        switch mode {
        case .locked: .locked
        case .continuousAuto: .continuousAutoWhiteBalance
        case .other: nil
        }
    }

    public func supportsWhiteBalance(_ mode: CameraWhiteBalanceMode) -> Bool {
        Self.avWhiteBalanceMode(mode).map { (avMode: AVCaptureDevice.WhiteBalanceMode) -> Bool in
            isWhiteBalanceModeSupported(avMode)
        } ?? false
    }

    public var currentWhiteBalanceMode: CameraWhiteBalanceMode {
        switch whiteBalanceMode {
        case .locked: .locked
        case .continuousAutoWhiteBalance: .continuousAuto
        default: .other
        }
    }

    public var currentWhiteBalanceGains: CameraWhiteBalanceGains {
        let gains: AVCaptureDevice.WhiteBalanceGains = deviceWhiteBalanceGains
        return CameraWhiteBalanceGains(red: gains.redGain, green: gains.greenGain, blue: gains.blueGain)
    }

    public var maximumWhiteBalanceGain: Float { maxWhiteBalanceGain }

    public var supportsLockingWithGains: Bool { isLockingWhiteBalanceWithCustomDeviceGainsSupported }

    public func beginWhiteBalanceConfiguration() -> Bool {
        (try? lockForConfiguration()) != nil
    }

    public func applyWhiteBalanceLocked(gains: CameraWhiteBalanceGains?) {
        guard isWhiteBalanceModeSupported(.locked) else { return }
        guard let gains else {
            whiteBalanceMode = .locked
            return
        }
        guard isLockingWhiteBalanceWithCustomDeviceGainsSupported, gains.isValid(maximum: maxWhiteBalanceGain) else { return }
        let avGains = AVCaptureDevice.WhiteBalanceGains(redGain: gains.red, greenGain: gains.green, blueGain: gains.blue)
        setWhiteBalanceModeLocked(with: avGains, completionHandler: nil)
    }

    public func applyWhiteBalanceContinuous() {
        guard isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) else { return }
        whiteBalanceMode = .continuousAutoWhiteBalance
    }

    public func endWhiteBalanceConfiguration() {
        unlockForConfiguration()
    }
}
#endif
