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
        // A UI test that resets starts with empty thumbnail, colour and motion caches, so pictures cached by an
        // earlier build (without PRE-004 colours or PRE-005 motion scores) are drawn again (post-merge 2026-11-14).
        if FixtureThumbnailRenderer.isEnabled, ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            for folder in [PresetThumbnailModel.defaultDirectory(), PresetThumbnailModel.defaultColorDirectory(),
                           PresetThumbnailModel.defaultMotionDirectory()] {
                try? FileManager.default.removeItem(at: folder)
            }
        }
        #endif
        let cache = PresetThumbnailCache(directory: PresetThumbnailModel.defaultDirectory(), renderer: thumbnailRenderer)
        let colors = PresetColorStore(directory: PresetThumbnailModel.defaultColorDirectory())   // PRE-004
        let motion = PresetMotionStore(directory: PresetThumbnailModel.defaultMotionDirectory())   // PRE-005
        return PresetThumbnailModel(cache: cache, colors: colors, motion: motion) { [weak loader] (preset: IndexedPreset) async throws -> Data in
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
