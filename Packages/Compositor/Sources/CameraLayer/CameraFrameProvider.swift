// CameraFrameProvider.swift — where camera pictures come from (CAM-001-R9, R13, R15; research
// CAM-001-D5, D7; contracts/camera-layer.md "CameraFrameProvider").
//
// A provider owns the camera (or a stand-in) and keeps only its newest picture, in a
// `LatestCameraFrame` slot: the camera's thread replaces it, the render thread reads it with a
// try-lock and never waits. Stopping closes the slot and drops the picture, so nothing is kept after
// the camera stops (CAM-001-R9). Pictures are never written, sent or analysed by any provider.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
import os

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
}

extension CameraFrameProvider {
    /// A provider without a front camera (CAM-001's stand-ins) stays on the rear camera.
    public var position: CameraPosition { .back }
    public func select(_ position: CameraPosition) {}
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
