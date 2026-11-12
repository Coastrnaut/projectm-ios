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
        guard !isSuspended else { return }
        schedule(presets, texturePaths: texturePaths)
    }

    private func schedule(_ presets: [Preset], texturePaths: [String]) {
        let delay = delay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.isSuspended, self.enabled else { return }
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
        guard enabled, let lastRequest else { return }
        schedule(lastRequest.presets, texturePaths: lastRequest.texturePaths)
    }
}
