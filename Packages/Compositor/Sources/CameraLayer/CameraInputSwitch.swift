// CameraInputSwitch.swift — replacing a running session's camera input safely (CAM-003-R6, R7;
// contracts/lens-selection.md C2; research CAM-003-D2).
//
// One platform-free routine, written against `CameraInputConfiguring`, which `AVCaptureSession`
// conforms to on iOS (AVCameraLensInventory.swift) and `FakeCameraCaptureSession` implements for the
// stand-in camera and tests. So the code that switches the real camera is the code the Mac tests run.
//
// 1. The new input is created first: when it cannot be (lens in use or gone) nothing is touched.
// 2. Inside one begin/commitConfiguration the old input is removed and the new one added.
// 3. When the session refuses it, the old input is put back; failing that, the wide lens; only when
//    nothing can be added is the outcome `noInput` (the provider then reports `unavailable`).
// The routine never throws and never traps; commitConfiguration always runs.
import Foundation

/// The part of a capture session a camera switch needs.
public protocol CameraInputConfiguring: AnyObject {
    associatedtype Input: AnyObject
    /// The session's current inputs.
    var configuredInputs: [Input] { get }
    func beginConfiguration()
    func commitConfiguration()
    func canAddInput(_ input: Input) -> Bool
    func addInput(_ input: Input)
    func removeInput(_ input: Input)
}

/// What a switch did (data-model.md).
public enum CameraInputSwitchOutcome: String, Sendable, Equatable {
    /// The new input is the session's input.
    case switched
    /// The new input could not be created or added; the previous input is still in place.
    case keptPrevious
    /// Neither the new nor the previous input could be added; the wide lens is in place.
    case fellBackToWide
    /// Nothing could be added; the session has no input.
    case noInput
}

public enum CameraInputSwitch {
    /// Replaces the session's inputs with `makeInput()` (contract C2). `makeFallback` creates the wide
    /// lens's input, asked for only when neither the new nor the previous input can be added.
    public static func replace<Session: CameraInputConfiguring>(
        in session: Session, makeInput: () -> Session.Input?, makeFallback: () -> Session.Input?
    ) -> CameraInputSwitchOutcome {
        let old: [Session.Input] = session.configuredInputs
        let input: Session.Input? = makeInput()
        if input == nil, !old.isEmpty { return .keptPrevious }   // nothing touched
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for previous in old { session.removeInput(previous) }
        if let input, session.canAddInput(input) {
            session.addInput(input)
            return .switched
        }
        var restored = false
        for previous in old where session.canAddInput(previous) {
            session.addInput(previous)
            restored = true
        }
        if restored { return .keptPrevious }
        if let wide = makeFallback(), session.canAddInput(wide) {
            session.addInput(wide)
            return .fellBackToWide
        }
        return .noInput
    }
}

/// A camera input of the fake session: the lens it opens (or the front camera).
public final class FakeCameraInput {
    public let lens: CameraLens
    public let position: CameraPosition
    /// CAM-004: the camera's exposure controls (one device per camera, as on iOS).
    public let device: FakeCameraExposureDevice
    /// CAM-005: the camera's focus controls (one device per camera, as on iOS).
    public let focusDevice: FakeCameraFocusDevice
    /// CAM-006: the camera's white balance controls (one device per camera, as on iOS).
    public let whiteBalanceDevice: FakeCameraWhiteBalanceDevice

    public init(lens: CameraLens, position: CameraPosition = .back, device: FakeCameraExposureDevice = FakeCameraExposureDevice(),
                focusDevice: FakeCameraFocusDevice = FakeCameraFocusDevice(),
                whiteBalanceDevice: FakeCameraWhiteBalanceDevice = FakeCameraWhiteBalanceDevice()) {
        self.lens = lens
        self.position = position
        self.device = device
        self.focusDevice = focusDevice
        self.whiteBalanceDevice = whiteBalanceDevice
    }
}

/// A capture session stand-in (CAM-003-R10): one camera input at most, as a single-camera
/// `AVCaptureSession`; lenses can be made to fail at input creation or be refused by the session.
/// Counts configuration changes and any input change made outside a configuration (should stay 0).
public final class FakeCameraCaptureSession: CameraInputConfiguring {
    public private(set) var configuredInputs: [FakeCameraInput] = []
    public private(set) var isRunning = false
    /// Lenses whose input cannot be created (`AVCaptureDeviceInput(device:)` throws).
    public var failingLenses: Set<CameraLens>
    /// Lenses whose input the session refuses (`canAddInput` false).
    public var refusedLenses: Set<CameraLens> = []
    public private(set) var configurations = 0
    public private(set) var changesOutsideConfiguration = 0
    private var configuring = false
    /// CAM-004: the cameras that can lock exposure (`nil`: every camera). Read when a camera's device is
    /// first made, so set it before the first start.
    public var exposureLockCameras: Set<FakeCameraKey>?
    private var devices: [FakeCameraKey: FakeCameraExposureDevice] = [:]
    /// CAM-005: the cameras that can focus on a point (`nil`: every camera). Read when a camera's focus
    /// device is first made, so set it before the first start.
    public var focusPointCameras: Set<FakeCameraKey>?
    private var focusDevices: [FakeCameraKey: FakeCameraFocusDevice] = [:]
    /// CAM-006: the cameras that can lock white balance (`nil`: every camera). Read when a camera's white
    /// balance device is first made, so set it before the first start.
    public var whiteBalanceLockCameras: Set<FakeCameraKey>?
    private var whiteBalanceDevices: [FakeCameraKey: FakeCameraWhiteBalanceDevice] = [:]

    public init(failingLenses: Set<CameraLens> = []) {
        self.failingLenses = failingLenses
    }

    /// CAM-004: the exposure device of a camera (the same object every time, as `AVCaptureDevice`).
    public func exposureDevice(lens: CameraLens, position: CameraPosition = .back) -> FakeCameraExposureDevice {
        let key = FakeCameraKey(lens: lens, position: position)
        if let device = devices[key] { return device }
        let device = FakeCameraExposureDevice(canLock: exposureLockCameras?.contains(key) ?? true)
        devices[key] = device
        return device
    }

    /// CAM-005: the focus device of a camera (the same object every time, as `AVCaptureDevice`).
    public func focusDevice(lens: CameraLens, position: CameraPosition = .back) -> FakeCameraFocusDevice {
        let key = FakeCameraKey(lens: lens, position: position)
        if let device = focusDevices[key] { return device }
        let device = FakeCameraFocusDevice(canFocusOnPoint: focusPointCameras?.contains(key) ?? true)
        focusDevices[key] = device
        return device
    }

    /// CAM-006: the white balance device of a camera (the same object every time, as `AVCaptureDevice`).
    public func whiteBalanceDevice(lens: CameraLens, position: CameraPosition = .back) -> FakeCameraWhiteBalanceDevice {
        let key = FakeCameraKey(lens: lens, position: position)
        if let device = whiteBalanceDevices[key] { return device }
        let device = FakeCameraWhiteBalanceDevice(canLock: whiteBalanceLockCameras?.contains(key) ?? true)
        whiteBalanceDevices[key] = device
        return device
    }

    /// The input for a lens, or nil when that lens fails (stands in for `AVCaptureDeviceInput(device:)`).
    public func makeInput(lens: CameraLens, position: CameraPosition = .back) -> FakeCameraInput? {
        let effective: CameraLens = position == .back ? lens : .wide
        guard position == .front || !failingLenses.contains(effective) else { return nil }
        return FakeCameraInput(lens: effective, position: position, device: exposureDevice(lens: effective, position: position),
                               focusDevice: focusDevice(lens: effective, position: position),
                               whiteBalanceDevice: whiteBalanceDevice(lens: effective, position: position))
    }

    public func beginConfiguration() {
        configuring = true
    }

    public func commitConfiguration() {
        configuring = false
        configurations += 1
    }

    public func canAddInput(_ input: FakeCameraInput) -> Bool {
        configuredInputs.isEmpty && !(input.position == .back && refusedLenses.contains(input.lens))
    }

    public func addInput(_ input: FakeCameraInput) {
        if !configuring { changesOutsideConfiguration += 1 }
        guard canAddInput(input) else { return }   // AVFoundation would raise; the fake refuses
        configuredInputs.append(input)
    }

    public func removeInput(_ input: FakeCameraInput) {
        if !configuring { changesOutsideConfiguration += 1 }
        configuredInputs.removeAll { (candidate: FakeCameraInput) -> Bool in candidate === input }
    }

    public func startRunning() {
        isRunning = !configuredInputs.isEmpty
    }

    public func stopRunning() {
        isRunning = false
    }

    /// Stops and removes every input (a released session).
    public func reset() {
        isRunning = false
        configuredInputs.removeAll()
    }
}

/// CAM-004: a stand-in camera: a back lens, or the front camera (its lens is always wide).
public struct FakeCameraKey: Hashable, Sendable {
    public let lens: CameraLens
    public let position: CameraPosition

    public init(lens: CameraLens, position: CameraPosition = .back) {
        self.lens = position == .front ? .wide : lens
        self.position = position
    }

    /// A comma-separated list of lens raw values and `front` ("wide,front"); `none` or unknown names add
    /// nothing (DEBUG `-uitestCameraExposureLock`, CAM-005 `-uitestCameraFocusPoint`, CAM-006
    /// `-uitestCameraWhiteBalanceLock`).
    public static func list(_ text: String) -> Set<FakeCameraKey> {
        var keys = Set<FakeCameraKey>()
        for name in text.split(separator: ",") {
            let trimmed: String = name.trimmingCharacters(in: .whitespaces)
            if trimmed == "front" {
                keys.insert(FakeCameraKey(lens: .wide, position: .front))
            } else if let lens = CameraLens(rawValue: trimmed) {
                keys.insert(FakeCameraKey(lens: lens))
            }
        }
        return keys
    }
}
