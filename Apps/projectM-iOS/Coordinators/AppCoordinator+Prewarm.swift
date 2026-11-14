// AppCoordinator+Prewarm.swift — PERF-005 wiring (specs/179-perf-005-prewarm-scheduler, R8, R11, R12).
//
// * `connectMediaPrewarm()` (end of init): registers the coordinator with the presentation registry (PERF-011)
//   and memory-pressure recovery (PERF-006), then plans from the show's position (standby → cue 1).
// * Every applied cue replans (`AppCoordinator+Show`), after the scene is live, so the live photo is pinned.
// * Each new Photo visual's layer gets the lookup (`preparePhotoVisualIfNeeded`), so a prewarmed picture is
//   adopted with no second decode.
// * Preset picks go through `forwardPresets` to the unchanged SC-104 warm-up (`RendererPresetLoader.prewarm`).
import Foundation
import ImageLayer
import SceneFormat

extension AppCoordinator {
    func connectMediaPrewarm() {
        presentation.register(mediaPrewarm)
        memoryPressure.register(mediaPrewarm)
        replanMediaPrewarm()
    }

    /// Plans the next cues' photos; the live scene's photo is the live key.
    func replanMediaPrewarm() {
        let live: URL? = settings.visual.usesPhoto ? Self.fileURL(photoLayerContent) : nil
        mediaPrewarm.replan(show: show, photoURL: { [unowned self] (document: SceneDocument) -> URL? in
            prewarmPhotoURL(for: document)
        }, liveURL: live)
    }

    /// The picture a scene's Photo visual would show first (research PERF-005-D8): its slideshow's first slide when
    /// it restores one with slides, else the stored photo. Nil for other visuals.
    func prewarmPhotoURL(for document: SceneDocument) -> URL? {
        guard let registry = try? SceneArchiveService.appRegistry() else { return nil }
        let apply = ShowSceneSnapshot.apply(of: document, warnings: [], registry: registry)
        guard apply.visual.usesPhoto else { return nil }
        if let restore = apply.slideshow {
            return slideshow.firstURL(restoring: restore.value) ?? photos.photo?.url
        }
        return Self.fileURL(photoLayerContent)
    }

    static func fileURL(_ content: ImageLayerContent) -> URL? {
        if case .file(let url) = content { return url }
        return nil
    }
}
