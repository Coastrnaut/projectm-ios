// PersonMasker.swift — runs person segmentation on camera pictures at a bounded rate and keeps the
// newest mask (CAM-008-R4 to R7; research CAM-008-D4, D5, D7; contracts/person-mask.md C2).
//
// The camera's thread offers every picture; the schedule starts an analysis on at most every
// `stride`-th one and never while one is in flight, so work never queues up. Analyses run on one
// utility-QoS serial queue (tests inject a synchronous runner). The newest mask sits in one slot that
// the render thread reads with a try-lock (never waits); the camera thread never waits either. Masks are
// memory only: `reset()` (camera stop or switch) and disabling drop the held one, and nothing is ever
// written, logged or sent. A failed analysis makes the masker `failed` for the rest of its life (a broken
// segmenter is not retried every frame); an unsupported segmenter is never called.
#if canImport(CoreVideo) && canImport(Metal) && !COMPOSITOR_NO_METAL
import CoreVideo
import Dispatch
import os

/// The newest mask with the camera it came from.
public struct PersonMask: Sendable {
    public let bitmap: PersonMaskBitmap
    /// Increases with every stored mask (the layer uploads only a new one).
    public let serial: UInt64
    public let position: CameraPosition
}

/// A picture handed to the analysis queue (CoreVideo buffers are thread-safe to read).
private struct OfferedPicture: @unchecked Sendable {
    let pixels: CVPixelBuffer
    let rotation: CameraRotation
    let position: CameraPosition
    let quality: PersonSegmentationQuality
    let generation: UInt64
}

public final class PersonMasker: @unchecked Sendable {
    /// Runs one analysis job (default: the masker's own serial queue, asynchronously).
    public typealias Runner = @Sendable (@escaping @Sendable () -> Void) -> Void

    private struct State {
        var enabled = false
        var plan = PersonMaskPolicy.plan(thermal: .nominal, reducedPower: false)
        var schedule = PersonMaskSchedule(stride: PersonMaskPolicy.normalStride)
        var failed = false
        var mask: PersonMask?
        var serial: UInt64 = 0
        /// Bumped by `reset()` and disabling: a result of an older generation is dropped.
        var generation: UInt64 = 0
        var started = 0
    }

    public let segmenter: any PersonSegmenting
    private let lock = OSAllocatedUnfairLock(uncheckedState: State())
    private let runner: Runner
    /// Main thread: called after every change of `availability`.
    public var onAvailabilityChange: ((PersonMaskAvailability) -> Void)?
    private var reported: PersonMaskAvailability

    public init(segmenter: any PersonSegmenting, runner: Runner? = nil) {
        self.segmenter = segmenter
        if let runner {
            self.runner = runner
        } else {
            let queue = DispatchQueue(label: "org.projectmios.camera.personMask", qos: .utility)
            self.runner = { (job: @escaping @Sendable () -> Void) -> Void in queue.async(execute: job) }
        }
        reported = segmenter.isSupported ? .available : .unsupported
    }

    /// CAM-008-D5: what the layer may draw. Main thread for `onAvailabilityChange`; readable anywhere.
    public var availability: PersonMaskAvailability {
        guard segmenter.isSupported else { return .unsupported }
        return lock.withLockUnchecked { (s: inout State) -> PersonMaskAvailability in
            if s.failed { return .failed }
            if s.plan == .paused { return .paused }
            return .available
        }
    }

    /// True while the user's choice needs masks (main thread). Disabling drops the held mask.
    public var isEnabled: Bool {
        get { lock.withLockUnchecked { $0.enabled } }
        set {
            let dropped: PersonMask? = lock.withLockUnchecked { (s: inout State) -> PersonMask? in
                s.enabled = newValue
                guard !newValue else { return nil }
                s.generation &+= 1
                s.schedule.reset()
                defer { s.mask = nil }
                return s.mask
            }
            _ = dropped
        }
    }

    /// CAM-008-R6 (main thread): the plan from heat and power. Pausing keeps the held mask out of use
    /// (the layer checks `availability`).
    public var plan: PersonMaskPlan {
        get { lock.withLockUnchecked { $0.plan } }
        set {
            lock.withLockUnchecked { (s: inout State) -> Void in
                s.plan = newValue
                if case let .run(_, stride) = newValue { s.schedule.setStride(stride) }
            }
            reportAvailability()
        }
    }

    /// Analyses started so far (tests).
    public var analysesStarted: Int { lock.withLockUnchecked { $0.started } }

    /// Offers one camera picture (any thread; never blocks for long, never waits for an analysis).
    public func offer(_ pixels: CVPixelBuffer, rotation: CameraRotation, position: CameraPosition) {
        guard segmenter.isSupported else { return }
        let job: OfferedPicture? = lock.withLockUnchecked { (s: inout State) -> OfferedPicture? in
            guard s.enabled, !s.failed, case let .run(quality, _) = s.plan else { return nil }
            guard s.schedule.offer() else { return nil }
            s.started += 1
            return OfferedPicture(pixels: pixels, rotation: rotation, position: position, quality: quality, generation: s.generation)
        }
        guard let job else { return }
        runner { [self] () -> Void in analyse(job) }
    }

    /// The newest mask, or nil (none, disabled, or the slot is busy this instant). Render thread.
    public func latestMask() -> PersonMask? {
        lock.withLockIfAvailableUnchecked { (s: inout State) -> PersonMask? in s.enabled ? s.mask : nil } ?? nil
    }

    /// CAM-008-R7: the camera stopped or switched; the held mask is dropped and the schedule restarts.
    public func reset() {
        let dropped: PersonMask? = lock.withLockUnchecked { (s: inout State) -> PersonMask? in
            s.generation &+= 1
            s.schedule.reset()
            defer { s.mask = nil }
            return s.mask
        }
        _ = dropped
    }

    private func analyse(_ job: OfferedPicture) {
        let result: Result<PersonMaskBitmap, Error> = Result { () throws -> PersonMaskBitmap in
            try segmenter.segment(job.pixels, rotation: job.rotation, quality: job.quality)
        }
        let failedNow: Bool = lock.withLockUnchecked { (s: inout State) -> Bool in
            s.schedule.finish()
            switch result {
            case let .success(bitmap):
                guard s.enabled, job.generation == s.generation, !s.failed else { return false }
                s.serial &+= 1
                s.mask = PersonMask(bitmap: bitmap, serial: s.serial, position: job.position)
                return false
            case .failure:
                guard !s.failed else { return false }
                s.failed = true
                s.mask = nil
                return true
            }
        }
        if failedNow { DispatchQueue.main.async { [self] () -> Void in reportAvailability() } }
    }

    /// Main thread: posts `availability` when it changed.
    private func reportAvailability() {
        let now: PersonMaskAvailability = availability
        guard now != reported else { return }
        reported = now
        onAvailabilityChange?(now)
    }
}
#endif
