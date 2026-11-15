// VideoReverseDriver.swift — one reverse cache build and its hand-over to the render thread (MED-005-R3, R6, R9;
// research MED-005-D5).
//
// * The build runs once per request on a utility-priority queue (`AVReverseFrameDecoder` + `VideoReverseCacheBuilder`);
//   `cancel()` makes it stop before the next picture and drop what it decoded.
// * The result sits behind an `OSAllocatedUnfairLock`; the render thread only ever tries that lock
//   (`readyCache()`, MED-008's rule), so it never waits for the build.
// * `VideoReverseStateSlot` carries the layer's reverse state with a generation: a cancelled build's late result is
//   ignored, and each change reaches the main actor's handler.
#if canImport(AVFoundation) && canImport(Metal) && !COMPOSITOR_NO_METAL
import Dispatch
import Foundation
import Metal
import os

/// `@unchecked Sendable`: the cache's textures are written once by the build, then only read.
final class VideoReverseDriver: @unchecked Sendable {
    private enum Phase {
        case building
        case ready(VideoReverseCache<MTLTexture>)
        case finished
    }

    private let phase = OSAllocatedUnfairLock<Phase>(uncheckedState: .building)
    private let cancelled = OSAllocatedUnfairLock<Bool>(initialState: false)
    private let done = DispatchGroup()

    /// Starts building the cache of `url`; `onFinish` (build thread) gets `.playing` or `.unsupported` (not on cancel).
    init(url: URL, device: MTLDevice, limits: VideoReverseLimits, budgetBytes: Int,
         onFinish: @escaping @Sendable (VideoReverseState) -> Void) {
        let deviceBox = DeviceBox(device: device)
        done.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { done.leave() }
            let decoder = AVReverseFrameDecoder(url: url, device: deviceBox.device)
            let outcome = VideoReverseCacheBuilder.build(decoder, limits: limits, budgetBytes: budgetBytes) { () -> Bool in
                cancelled.withLock { $0 }
            }
            switch outcome {
            case .built(let cache):
                let kept: Bool = phase.withLockUnchecked { (p: inout Phase) -> Bool in
                    guard !cancelled.withLock({ $0 }) else { p = .finished; return false }
                    p = .ready(cache)
                    return true
                }
                if kept { onFinish(.playing) }
            case .unsupported(let reason):
                phase.withLockUnchecked { $0 = .finished }
                if !cancelled.withLock({ $0 }) { onFinish(.unsupported(reason)) }
            case .cancelled:
                phase.withLockUnchecked { $0 = .finished }
            }
        }
    }

    /// Render thread: the cache when it is ready and the lock is free this instant; nil otherwise.
    func readyCache() -> VideoReverseCache<MTLTexture>? {
        phase.withLockIfAvailableUnchecked { (p: inout Phase) -> VideoReverseCache<MTLTexture>? in
            if case .ready(let cache) = p { return cache }
            return nil
        } ?? nil
    }

    /// Stops the build and drops the cache.
    func cancel() {
        cancelled.withLock { $0 = true }
        phase.withLockUnchecked { $0 = .finished }
    }

    /// Tests: waits until the build ended (ceiling, not a timing assertion).
    func waitUntilFinished(timeout: Double) -> Bool {
        done.wait(timeout: .now() + timeout) == .success
    }
}

private struct DeviceBox: @unchecked Sendable {
    let device: MTLDevice
}

/// The layer's reverse state, shared between build threads and the compositor's thread.
final class VideoReverseStateSlot: Sendable {
    struct State {
        var generation: UInt64 = 0
        var state: VideoReverseState = .off
        var handler: (@MainActor @Sendable (VideoReverseState) -> Void)?
    }
    let lock = OSAllocatedUnfairLock(uncheckedState: State())

    /// A new request: later results of older generations are ignored. Returns the new generation.
    func begin(_ state: VideoReverseState) -> UInt64 {
        let (generation, changed): (UInt64, Bool) = lock.withLockUnchecked { s in
            s.generation &+= 1
            let changed: Bool = s.state != state
            s.state = state
            return (s.generation, changed)
        }
        if changed { notify() }
        return generation
    }

    /// A build's result for `generation`.
    func report(_ state: VideoReverseState, generation: UInt64) {
        let changed: Bool = lock.withLockUnchecked { s in
            guard s.generation == generation, s.state != state else { return false }
            s.state = state
            return true
        }
        if changed { notify() }
    }

    private func notify() {
        guard lock.withLockUnchecked({ $0.handler != nil }) else { return }
        Task { @MainActor [self] in
            let (state, handler) = lock.withLockUnchecked { ($0.state, $0.handler) }
            handler?(state)
        }
    }
}
#endif
