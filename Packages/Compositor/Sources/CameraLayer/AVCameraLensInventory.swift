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
#endif
