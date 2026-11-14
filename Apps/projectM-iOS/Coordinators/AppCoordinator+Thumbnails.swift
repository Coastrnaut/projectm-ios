// AppCoordinator+Thumbnails.swift — roadmap PRE-001: creates the browser's thumbnail model. Built-in
// presets' bytes come from the bundle or the pack archive (`bundledData`); an imported preset's from
// the user library's playable copy only (PRE-012), so a waiting or quarantined preset is never drawn.
import Foundation
import PresetLibrary
import Rendering

extension AppCoordinator {
    static func makeThumbnails(loader: RendererPresetLoader,
                               renderer: @escaping @MainActor @Sendable () -> (any VisualizerRenderer)?) -> PresetThumbnailModel {
        let drawing: @MainActor @Sendable () -> (any PresetThumbnailDrawing)? = { renderer()?.presetThumbnails }
        var thumbnailRenderer: any PresetThumbnailRendering = RendererThumbnailRenderer(drawing: drawing)
        #if DEBUG
        if FixtureThumbnailRenderer.isEnabled { thumbnailRenderer = FixtureThumbnailRenderer() }
        #endif
        let cache = PresetThumbnailCache(directory: PresetThumbnailModel.defaultDirectory(), renderer: thumbnailRenderer)
        return PresetThumbnailModel(cache: cache) { [weak loader] (preset: IndexedPreset) async throws -> Data in
            guard let loader else { throw PresetThumbnailError.unavailable("No preset loader.") }
            if preset.source == PresetLibrary.userSource {
                guard let data = await loader.userPresetData?(preset.id) else {
                    throw PresetThumbnailError.unavailable("The preset is not playable now.")
                }
                return data
            }
            return try loader.bundledData(for: preset)
        }
    }
}
