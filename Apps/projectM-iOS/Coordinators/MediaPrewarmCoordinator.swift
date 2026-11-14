// MediaPrewarmCoordinator.swift — PERF-005 in the app: the next cues' media decoded ahead without blocking the
// live frame (specs/179-perf-005-prewarm-scheduler, R5, R6, R9 to R12; research PERF-005-D5, D8, D9).
//
// * Owns the plain-Swift `PrewarmScheduler` (PresentationLifecycle) with the device-class budget, the default
//   utility executor and the 0.5 s settle delay, and a `PhotoPrewarmLoader`.
// * `replan(show:photoURL:liveURL:)`: the next cue and the one after it (no wrap; standby → cue 1); each cue's
//   scene is read from the show folder (the same small read a step makes) and its photo resolved by the app
//   (the scene's slideshow first slide, else the stored photo). Rank 0 = the next cue. The live photo is the
//   live key: never evicted and never loaded again.
// * `attach(_:)` gives a photo layer the lookup: setting its content to a prewarmed URL takes the texture out of
//   the cache (the layer owns it from then on) and starts no load.
// * Presentation-bound (PERF-011): suspension pauses, cancels the in-flight item before its GPU step, waits for
//   a running GPU step and releases the cache; resume replans after the settle delay. PERF-006: a cache-tier
//   responder releases every non-live entry. Thermal serious or critical pauses; Low Power keeps the next cue.
//   PERF-008-R2: a power budget without background warm-up (Battery saver) also keeps only the next cue.
// * Preset picks pass through `forwardPresets` to the unchanged SC-104 warm-up (2.5 s delay).
// Video and logo are not loaded here (spec Clarifications); the loader refuses those kinds.
import Foundation
import ImageLayer
import Metal
import PresentationLifecycle
import Rendering
import SceneFormat
import ShowControl

@MainActor
final class MediaPrewarmCoordinator: PresentationBoundResource, MemoryPressureResponder {
    let scheduler: PrewarmScheduler
    let loader: PhotoPrewarmLoader
    private var observers: [NSObjectProtocol] = []
    /// The thermal state used (DEBUG tests inject one).
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    init(scheduler: PrewarmScheduler, loader: PhotoPrewarmLoader) {
        self.scheduler = scheduler
        self.loader = loader
    }

    /// The app's coordinator: system default device, device-class budget, default executor and clock.
    static func makeDefault() -> MediaPrewarmCoordinator {
        let loader = PhotoPrewarmLoader(device: MTLCreateSystemDefaultDevice())
        let coordinator = MediaPrewarmCoordinator(scheduler: PrewarmScheduler(budgetBytes: PrewarmBudget.current, loader: loader),
                                                  loader: loader)
        coordinator.observeSystem()
        return coordinator
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        scheduler.shutdown()
    }

    // MARK: Plan

    /// The photo items of the next cues (rank 0 = the next cue), no wrap.
    static func photoItems(cues: [ShowCue], activeIndex: Int?, scene: (String) -> SceneDocument?,
                           photoURL: (SceneDocument) -> URL?) -> [PrewarmItem] {
        let upcoming: [Int] = PrewarmLookahead.upcoming(activeIndex: activeIndex, count: cues.count)
        var items: [PrewarmItem] = []
        for (rank, index) in upcoming.enumerated() {
            guard let document = scene(cues[index].sceneID), let url = photoURL(document) else { continue }
            items.append(PrewarmItem.photo(url, rank: rank))
        }
        return items
    }

    /// Replans from the show's position (R12). `liveURL`: the photo the live scene shows (nil: none).
    func replan(show: ShowCoordinator, photoURL: (SceneDocument) -> URL?, liveURL: URL?) {
        let store = show.store
        let items = Self.photoItems(cues: show.list.cues, activeIndex: show.list.activeIndex,
                                    scene: { (id: String) -> SceneDocument? in try? store?.scene(id).document },
                                    photoURL: photoURL)
        scheduler.plan(items, live: liveURL.map { (url: URL) -> Set<PrewarmKey> in [PrewarmKey.photo(url)] } ?? [])
    }

    /// The texture prewarmed for `url`, handed over to the live scene (nil: not prewarmed).
    func takeTexture(_ url: URL) -> MTLTexture? {
        scheduler.take(.photo(url)).flatMap { (asset: PrewarmedAsset) -> MTLTexture? in asset.payload as? MTLTexture }
    }

    /// Gives a photo layer the prewarm lookup (R11).
    func attach(_ layer: ImageLayerSource) {
        layer.prewarmedTexture = { [weak self] (url: URL) -> MTLTexture? in
            guard let self else { return nil }
            // The layer's content is set on the main thread (the compositor's thread in the app).
            nonisolated(unsafe) var texture: MTLTexture?
            MainActor.assumeIsolated { texture = self.takeTexture(url) }
            return texture
        }
    }

    // MARK: Thermal and Low Power (PERF-003 signals; research PERF-005-D9)

    func update(thermal: ProcessInfo.ThermalState, lowPower: Bool, budget: PowerBudget = .standard) {
        thermalState = thermal
        if thermal == .serious || thermal == .critical {
            scheduler.pause(.thermal)
        } else {
            scheduler.resume(.thermal)
        }
        scheduler.lowPower = lowPower || !budget.allowsBackgroundWarmUp   // PERF-008-R2
    }

    private func observeSystem() {
        let refresh: @MainActor (MediaPrewarmCoordinator) -> Void = { (c: MediaPrewarmCoordinator) in
            let lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
            c.update(thermal: Self.injectedThermal ?? ProcessInfo.processInfo.thermalState,
                     lowPower: lowPower, budget: PowerProfileState.budget(lowPower: lowPower))
        }
        refresh(self)
        for name in QualityGovernor.changeNotifications {   // thermal, Low Power and the power profile (PERF-008)
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] (_: Notification) in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    refresh(self)
                }
            })
        }
    }

    /// DEBUG: PERF-003's `-uitestThermalState` also holds the prewarm (nil in Release or without the argument).
    static var injectedThermal: ProcessInfo.ThermalState? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uitestThermalState"), index + 1 < arguments.count else { return nil }
        switch arguments[index + 1] {
        case "serious": return .serious
        case "critical": return .critical
        case "fair": return .fair
        default: return .nominal
        }
        #else
        return nil
        #endif
    }

    // MARK: PresentationBoundResource (PERF-011)

    let presentationResourceName = "media prewarm"

    func suspendForPresentationLoss() { scheduler.pause(.presentation) }

    func resumeForPresentation() { scheduler.resume(.presentation) }

    // MARK: MemoryPressureResponder (PERF-006, R10)

    let memoryPressureName = "media prewarm cache"
    let memoryPressureTier = MemoryPressureTier.cache
    var reclaimableBytes: Int { scheduler.heldBytes }

    func releaseForMemoryPressure(_ level: MemoryPressureLevel) -> MemoryPressureRelease {
        let freed = scheduler.releaseForMemoryPressure()
        return MemoryPressureRelease(bytes: freed.bytes, items: freed.items)
    }
}

/// Decodes a photo off the main thread and uploads it inside the scheduler's graphics gate (research PERF-005-D5).
final class PhotoPrewarmLoader: PrewarmLoading, @unchecked Sendable {
    let device: MTLDevice?
    private let lock = NSLock()
    private var decodeCount = 0

    init(device: MTLDevice?) {
        self.device = device
    }

    /// Pictures decoded so far (tests).
    var decodes: Int { lock.withLock { decodeCount } }

    func load(_ item: PrewarmItem, context: PrewarmLoadContext) -> PrewarmLoadResult {
        guard item.key.kind == .photo, let url = item.source, let device, !context.isCancelled else { return .refused }
        lock.withLock { decodeCount += 1 }
        let image: DecodedImage
        switch ImageLayerSource.decodeStored(url) {
        case .success(let decoded): image = decoded
        case .failure: return .failed
        }
        let bytes = ImageLayerSource.textureBytes(width: image.width, height: image.height)
        guard bytes <= context.maxBytes, !context.isCancelled else { return .refused }
        let texture: MTLTexture?? = context.graphicsStep { () -> MTLTexture? in ImageLayerSource.makeLayerTexture(image, device: device) }
        guard let made = texture else { return .refused }   // cancelled, or presentation lost
        guard let made else { return .failed }
        return .loaded(bytes: bytes, payload: made as AnyObject)
    }
}
