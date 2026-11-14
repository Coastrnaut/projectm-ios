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
#endif
