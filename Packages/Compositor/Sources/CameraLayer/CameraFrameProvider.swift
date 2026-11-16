// CameraFrameProvider.swift — where camera pictures come from (CAM-001-R9, R13, R15; research
// CAM-001-D5, D7; contracts/camera-layer.md "CameraFrameProvider").
//
// A provider owns the camera (or a stand-in) and keeps only its newest picture, in a
// `LatestCameraFrame` slot: the camera's thread replaces it, the render thread reads it with a
// try-lock and never waits. Stopping closes the slot and drops the picture, so nothing is kept after
// the camera stops (CAM-001-R9). Pictures are never written or sent by any provider; the only analysis is
// CAM-008's on-device person mask, in memory, while the user chose it (ADR-0063).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import CoreVideo
import Metal
import os

/// CAM-009 (research CAM-009-D2, contract face-sources F4): something besides the layer that looks at the camera's
/// pictures on the device (the app's opt-in face analysis). `offer` is called on the camera's thread for every stored
/// picture and must return at once (it decides itself whether to analyse, and never keeps the picture beyond its
/// analysis); `reset` is called on the main thread when the camera stops or switches.
public protocol CameraPictureAnalyzing: AnyObject, Sendable {
    func offer(_ pixels: CVPixelBuffer, rotation: CameraRotation, position: CameraPosition)
    func reset()
}

/// CAM-010 (research CAM-010-D2, contract hand-sources H4): several analyzers behind the provider's one slot (face and
/// hand analysis). The list is fixed at creation; `offer` and `reset` go to each member in order, and each member
/// decides itself whether to analyse.
public final class CameraPictureAnalyzerGroup: CameraPictureAnalyzing {
    public let analyzers: [any CameraPictureAnalyzing]

    public init(_ analyzers: [any CameraPictureAnalyzing]) {
        self.analyzers = analyzers
    }

    public func offer(_ pixels: CVPixelBuffer, rotation: CameraRotation, position: CameraPosition) {
        for analyzer in analyzers { analyzer.offer(pixels, rotation: rotation, position: position) }
    }

    public func reset() {
        for analyzer in analyzers { analyzer.reset() }
    }
}

/// One camera picture: a read-only `.bgra8Unorm_srgb` texture (sampling decodes to linear light).
public struct CameraFrame {
    public let texture: MTLTexture
    public let width: Int
    public let height: Int
    /// Clockwise turn that makes the picture upright.
    public let rotation: CameraRotation
    /// Increases with every stored picture.
    public let sequence: UInt64
    /// CAM-002 (research CAM-002-D3): the camera the picture came from. The layer draws a picture only
    /// when this equals the provider's current position, so no picture of the previous camera is drawn
    /// after a switch.
    public let position: CameraPosition
    /// Keeps the texture's backing (e.g. a CoreVideo texture) alive while the picture is held.
    let owner: AnyObject?

    public init(texture: MTLTexture, rotation: CameraRotation, sequence: UInt64, position: CameraPosition = .back, owner: AnyObject? = nil) {
        self.texture = texture
        width = texture.width
        height = texture.height
        self.rotation = rotation
        self.sequence = sequence
        self.position = position
        self.owner = owner
    }
}

/// The source of camera pictures. `start`, `stop`, `state` and `onStateChange` belong to the main
/// thread; `latestFrame` may be called from the render thread and never blocks.
public protocol CameraFrameProvider: AnyObject {
    /// QA-011 (DEBUG): capture-path counters (a requirement so the AV provider's are reached through `any`).
    var debugCaptureSummary: String { get }
    /// The current state (main thread).
    var state: CameraFeedState { get }
    /// Called on the main thread after every change of `state`.
    var onStateChange: ((CameraFeedState) -> Void)? { get set }
    /// Starts the feed. Asks for camera access only when it was never decided and a rear camera
    /// exists (CAM-001-R4, R6). A no-op while starting or running.
    func start()
    /// Stops at once: no more pictures, the newest one is dropped, state `idle`. Idempotent.
    func stop()
    /// The newest picture; nil before the first, after `stop`, or when the slot is busy this instant.
    func latestFrame() -> CameraFrame?
    /// CAM-002: the camera the feed uses (main thread).
    var position: CameraPosition { get }
    /// CAM-002: chooses the camera (main thread). Idle, denied or restricted: only recorded. Starting
    /// or running: switches, and no picture of the previous camera is returned afterwards.
    /// Unavailable, interrupted or failed: starts again with the new camera. Same position: no-op.
    func select(_ position: CameraPosition)
    /// CAM-013 (contracts/camera-recovery.md C1): why the feed is `interrupted` or `failed` (main
    /// thread). Set before `onStateChange` reports that state; nil while running, after `stop()` and
    /// after a camera switch.
    var stopReason: CameraStopReason? { get }
    /// CAM-003 (contracts/lens-selection.md C1): the back lens in use, or to be used (main thread).
    var lens: CameraLens { get }
    /// CAM-003: the back lenses this device has, in display order (reading it starts nothing).
    var availableLenses: [CameraLens] { get }
    /// CAM-003-R6, R7: chooses the back lens (main thread). A lens not listed means the wide lens; the
    /// same lens is a no-op. With the back camera starting or running, the lens is switched on the
    /// running session; when its input cannot be opened the previous lens keeps running and `lens`
    /// returns to it. Otherwise recorded (front, idle, denied, restricted, asking) or started again
    /// (unavailable, interrupted, failed). Never crashes.
    func selectLens(_ lens: CameraLens)
    /// CAM-004 (contracts/exposure-lock.md C3): the current camera's exposure, read back from the camera
    /// (main thread). `canLock` is known without starting the camera; `isRunning` only while running.
    var exposure: CameraExposureState { get }
    /// CAM-004: called on the main thread after every change of `exposure`.
    var onExposureChange: ((CameraExposureState) -> Void)? { get set }
    /// CAM-004-R4: locks (true) or releases (false) the running camera's exposure. Unsupported or not
    /// running: nothing is configured. A lens or position switch and every stop release the lock (R6, R7).
    func setExposureLocked(_ locked: Bool)
    /// CAM-005 (contracts/focus-point.md C3): the current camera's focus, read back from the camera
    /// (main thread). `canFocus` is known without starting the camera; `isRunning` only while running.
    var focus: CameraFocusState { get }
    /// CAM-005: called on the main thread after every change of `focus`.
    var onFocusChange: ((CameraFocusState) -> Void)? { get set }
    /// CAM-005-R1, R4: focuses the running camera at `point` (camera point-of-interest space).
    /// Unsupported or not running: nothing is configured (R5). A lens or position switch and every stop
    /// return the camera to continuous automatic focus at the centre (R8).
    func setFocusPoint(_ point: CameraFocusPoint)
    /// CAM-006 (contracts/white-balance-lock.md C3): the current camera's white balance, read back from
    /// the camera (main thread). `canLock` is known without starting the camera; `isRunning` only while running.
    var whiteBalance: CameraWhiteBalanceState { get }
    /// CAM-006: called on the main thread after every change of `whiteBalance`.
    var onWhiteBalanceChange: ((CameraWhiteBalanceState) -> Void)? { get set }
    /// CAM-006-R4: locks (true) at the current, validated gains or releases (false) the running camera's
    /// white balance. Unsupported or not running: nothing is configured. An interruption keeps the lock;
    /// a lens or position switch and every stop release it (R7 to R9).
    func setWhiteBalanceLocked(_ locked: Bool)
    /// CAM-008 (contracts/person-mask.md C4): the masker the provider offers its pictures to (main thread
    /// sets it; the camera's thread reads it). Nil: no masking. Pictures offered are never kept by the masker
    /// beyond the analysis; masks stay in memory.
    var personMasker: PersonMasker? { get set }
    /// CAM-009 (contract F4): the analyzer the provider also offers its pictures to (main thread sets it; the camera's
    /// thread reads it). Nil: none.
    var pictureAnalyzer: (any CameraPictureAnalyzing)? { get set }
}

extension CameraFrameProvider {
    /// QA-011 (DEBUG device diagnosis of a camera switch): what the capture path did; "" for providers without counters.
    public var debugCaptureSummary: String { "" }

    /// A provider without a front camera (CAM-001's stand-ins) stays on the rear camera.
    public var position: CameraPosition { .back }
    public func select(_ position: CameraPosition) {}
    /// CAM-013: a provider that reports no reasons.
    public var stopReason: CameraStopReason? { nil }
    /// CAM-003: a provider without lenses uses the wide lens.
    public var lens: CameraLens { .wide }
    public var availableLenses: [CameraLens] { [.wide] }
    public func selectLens(_ lens: CameraLens) {}
    /// CAM-004: a provider without exposure controls cannot lock.
    public var exposure: CameraExposureState { .notRunning(canLock: false) }
    public var onExposureChange: ((CameraExposureState) -> Void)? {
        get { nil }
        set {}
    }
    public func setExposureLocked(_ locked: Bool) {}
    /// CAM-005: a provider without focus controls cannot focus on a point.
    public var focus: CameraFocusState { .notRunning(canFocus: false) }
    public var onFocusChange: ((CameraFocusState) -> Void)? {
        get { nil }
        set {}
    }
    public func setFocusPoint(_ point: CameraFocusPoint) {}
    /// CAM-006: a provider without white balance controls cannot lock.
    public var whiteBalance: CameraWhiteBalanceState { .notRunning(canLock: false) }
    public var onWhiteBalanceChange: ((CameraWhiteBalanceState) -> Void)? {
        get { nil }
        set {}
    }
    public func setWhiteBalanceLocked(_ locked: Bool) {}
    /// CAM-008: a provider that offers no pictures to a masker.
    public var personMasker: PersonMasker? {
        get { nil }
        set {}
    }
    /// CAM-009: a provider that offers no pictures to an analyzer.
    public var pictureAnalyzer: (any CameraPictureAnalyzing)? {
        get { nil }
        set {}
    }
}

/// The newest-picture slot shared by a provider's camera thread and the render thread.
public final class LatestCameraFrame: @unchecked Sendable {
    private struct Slot {
        var frame: CameraFrame?
        var open = false
        var rotation = CameraRotation.none
        var position = CameraPosition.back
        var sequence: UInt64 = 0
    }

    private let lock = OSAllocatedUnfairLock(uncheckedState: Slot())

    public init() {}

    /// Accepts pictures from now on.
    public func open() {
        lock.withLockUnchecked { $0.open = true }
    }

    /// Refuses further pictures and drops the held one.
    public func close() {
        let dropped: CameraFrame? = lock.withLockUnchecked { slot in
            slot.open = false
            defer { slot.frame = nil }
            return slot.frame
        }
        _ = dropped   // released outside the lock
    }

    /// Drops the held picture but keeps accepting new ones (an interruption).
    public func clear() {
        let dropped: CameraFrame? = lock.withLockUnchecked { slot in
            defer { slot.frame = nil }
            return slot.frame
        }
        _ = dropped
    }

    public var isOpen: Bool { lock.withLockUnchecked { $0.open } }

    /// The rotation stamped on pictures stored from now on.
    public func setRotation(_ rotation: CameraRotation) {
        lock.withLockUnchecked { $0.rotation = rotation }
    }

    /// CAM-008: the rotation and position stamped on pictures stored now (the masker gets the same).
    public var stamp: (rotation: CameraRotation, position: CameraPosition) {
        lock.withLockUnchecked { (slot: inout Slot) -> (rotation: CameraRotation, position: CameraPosition) in (slot.rotation, slot.position) }
    }

    /// CAM-002: the position stamped on pictures stored from now on without their own position.
    public func setPosition(_ position: CameraPosition) {
        lock.withLockUnchecked { $0.position = position }
    }

    /// Replaces the newest picture; false (and nothing kept) when the slot is closed. `position` is the
    /// camera the picture came from (nil: the slot's position).
    @discardableResult
    public func store(_ texture: MTLTexture, owner: AnyObject? = nil, position: CameraPosition? = nil) -> Bool {
        let replaced: (stored: Bool, old: CameraFrame?) = lock.withLockUnchecked { slot in
            guard slot.open else { return (false, nil) }
            slot.sequence &+= 1
            let old = slot.frame
            slot.frame = CameraFrame(texture: texture, rotation: slot.rotation, sequence: slot.sequence,
                                     position: position ?? slot.position, owner: owner)
            return (true, old)
        }
        return replaced.stored   // the old picture is released here, outside the lock
    }

    /// The newest picture, or nil (none, closed, or the lock is busy this instant: never waits).
    public func read() -> CameraFrame? {
        lock.withLockIfAvailableUnchecked { $0.frame } ?? nil
    }
}
#endif
