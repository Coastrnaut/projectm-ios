// PresetWarmUpController.swift — when the preset warm-up runs (feature 002 SC-104; PERF-011-R7, R8).
//
// The warm-up (PresetPrewarmer) builds the GPU pipelines of the presets most likely to be chosen
// next. This controller decides when it may work:
//
// * A request starts after `delay`, once the visible switch's blend is over (warming during the
//   blend cost D1 a third of its frame rate, 2026-11-10). A newer request replaces an older one.
// * It is a presentation-bound resource. While the app cannot present frames (background, device
//   lock) nothing is warmed: a request waiting for its delay is cancelled, the worker is stopped
//   and has released its thread, context, engine and render target when suspension returns, and
//   new requests are only remembered. On resume the most recent request is issued again with the
//   normal delay; the worker skips presets it already warmed.
// * PERF-006 (memory pressure): two recovery steps. The cache step "preset warm-up context" cancels a
//   request waiting for its delay and stops the worker, which then holds no thread, context, engine
//   or target; the most recent request and the warmed presets are kept, and the next request starts
//   the worker again. The optional step "preset warm-up" does the same and then holds new requests
//   (remembering the newest) until the cool-down ends; the restore issues the newest with the normal
//   delay, unless presentation is suspended (then the PERF-011 resume issues it). The two states are
//   independent: a presentation resume during a shed schedules nothing.
import Foundation
import PresentationLifecycle
import Rendering

@MainActor
final class PresetWarmUpController: PresentationBoundResource {
    let presentationResourceName = "preset warm-up"

    /// Off: requests are ignored (automation runs that measure switches without warm-up).
    var enabled = true
    /// How long after a request the warm-up starts.
    var delay: Duration

    let worker: any PresetWarming
    private var pending: Task<Void, Never>?
    /// The most recent request, issued again after a suspension.
    private var lastRequest: (presets: [Preset], texturePaths: [String])?
    private(set) var isSuspended = false
    /// PERF-006: optional warm-up work is shed for a memory-pressure cool-down.
    private(set) var isShedForMemoryPressure = false
    /// Requests handed to the worker so far (tests).
    private(set) var startedRequests = 0

    init(worker: any PresetWarming, delay: Duration) {
        self.worker = worker
        self.delay = delay
    }

    /// Presets likely to be chosen next. Replaces any earlier request.
    func request(_ presets: [Preset], texturePaths: [String]) {
        pending?.cancel()
        pending = nil
        guard enabled, !presets.isEmpty else {
            lastRequest = nil
            return
        }
        lastRequest = (presets, texturePaths)
        guard !isSuspended, !isShedForMemoryPressure else { return }
        schedule(presets, texturePaths: texturePaths)
    }

    private func schedule(_ presets: [Preset], texturePaths: [String]) {
        let delay = delay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.isSuspended, !self.isShedForMemoryPressure, self.enabled else { return }
            self.pending = nil
            self.startedRequests += 1
            self.worker.request(presets, texturePaths: texturePaths)
        }
    }

    /// Presets whose pipelines were built so far.
    var warmedCount: Int { worker.warmedCount }

    /// Ends all warm-up work for good (the renderer is going away).
    func shutdown() {
        pending?.cancel()
        pending = nil
        lastRequest = nil
        worker.stop()
    }

    // MARK: - PresentationBoundResource

    func suspendForPresentationLoss() {
        guard !isSuspended else { return }
        isSuspended = true
        pending?.cancel()
        pending = nil
        worker.stop()   // waits: no warm-up work runs once this returns
    }

    func resumeForPresentation() {
        guard isSuspended else { return }
        isSuspended = false
        guard enabled, !isShedForMemoryPressure, let lastRequest else { return }
        schedule(lastRequest.presets, texturePaths: lastRequest.texturePaths)
    }

    // MARK: - Memory pressure (PERF-006-R9, R10)

    /// What the worker's resources are estimated at: its BGRA8 target. The engine and the EGL context
    /// have no public size, so this is a lower bound (research PERF-006-D5).
    static let estimatedWorkerBytes = PresetPrewarmer.targetSize * PresetPrewarmer.targetSize * 4

    /// The two recovery steps (held here; the recovery holds them weakly).
    private(set) lazy var memoryPressureResponders: [any MemoryPressureResponder] = [
        MemoryStep(controller: self, tier: .cache), MemoryStep(controller: self, tier: .optional),
    ]

    /// Cancels a waiting request and stops the worker (its thread, context, engine and target are
    /// gone when this returns). Keeps the last request and the warmed presets.
    func releaseForMemoryPressure() -> MemoryPressureRelease {
        let held = worker.holdsGraphicsResources
        pending?.cancel()
        pending = nil
        worker.stop()
        return held ? MemoryPressureRelease(bytes: Self.estimatedWorkerBytes, items: 1, bytesEstimated: true) : .none
    }

    /// Releases and then holds requests until `restoreAfterMemoryPressureShed()`.
    func shedForMemoryPressure() -> MemoryPressureRelease {
        isShedForMemoryPressure = true
        return releaseForMemoryPressure()
    }

    /// The cool-down ended: the newest request is issued with the normal delay (not while suspended).
    func restoreAfterMemoryPressureShed() {
        guard isShedForMemoryPressure else { return }
        isShedForMemoryPressure = false
        guard enabled, !isSuspended, let lastRequest else { return }
        schedule(lastRequest.presets, texturePaths: lastRequest.texturePaths)
    }

    @MainActor
    private final class MemoryStep: MemoryPressureResponder {
        weak var controller: PresetWarmUpController?
        let memoryPressureTier: MemoryPressureTier

        init(controller: PresetWarmUpController, tier: MemoryPressureTier) {
            self.controller = controller
            memoryPressureTier = tier
        }

        var memoryPressureName: String { memoryPressureTier == .cache ? "preset warm-up context" : "preset warm-up" }

        var reclaimableBytes: Int {
            memoryPressureTier == .cache && controller?.worker.holdsGraphicsResources == true ? PresetWarmUpController.estimatedWorkerBytes : 0
        }

        func releaseForMemoryPressure(_ level: MemoryPressureLevel) -> MemoryPressureRelease {
            guard let controller else { return .none }
            return memoryPressureTier == .cache ? controller.releaseForMemoryPressure() : controller.shedForMemoryPressure()
        }

        func restoreAfterMemoryPressure() {
            guard memoryPressureTier == .optional else { return }
            controller?.restoreAfterMemoryPressureShed()
        }
    }
}
