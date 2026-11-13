// GoldenLayerFactory.swift — a golden scene's live state → compositor layers (QA-002-R4; contract G1,
// G2). Only the native layers whose output is a pure function of time and audio are supported; camera
// and video (live input, decoded movie timing) and unknown kinds are refused. Graphs go through SHD-011's
// importer like any imported file; photos are generated from the run's seed and loaded through the photo
// layer from a temporary file, as a stored copy would be.
//
// Spectra: the bottom layer keeps the generator's default (opaque black) background; a spectrum above
// other layers is drawn on a transparent background so it does not hide them (research D10).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import GeneratorGraph
import GeneratorGraphImport
import GoldenImages
import ImageLayer
import Metal
import ParameterGraph
import ProceduralMaterials
import SceneFormat
import SpectrumLayers
import TextLayer
import VisualGenerators

public enum GoldenRenderError: Error, Equatable, CustomStringConvertible {
    case noMetalDevice
    case sceneInvalid(String)
    case unsupportedLayer(String)
    case assetMissing(String)
    case layerFailed(String)
    case renderFailed(String)
    case captureFailed(String)

    public var description: String {
        switch self {
        case .noMetalDevice: "no Metal device"
        case let .sceneInvalid(s): "scene invalid: \(s)"
        case let .unsupportedLayer(s): "unsupported layer: \(s)"
        case let .assetMissing(s): "asset missing: \(s)"
        case let .layerFailed(s): "layer failed: \(s)"
        case let .renderFailed(s): "render failed: \(s)"
        case let .captureFailed(s): "capture failed: \(s)"
        }
    }
}

/// The layers of one scene, built before the stack is applied, plus the ones that load asynchronously.
final class GoldenSceneLayers {
    var byID: [LayerInstanceID: any LayerSource] = [:]
    var photos: [ImageLayerSource] = []
    var texts: [TextLayerSource] = []
    /// Temporary photo files, removed with `cleanUp()`.
    var files: [URL] = []

    /// Waits for every asynchronous load and rasterization started so far.
    func settle() {
        for p in photos { p.waitUntilLoaded() }
        for t in texts { t.waitUntilRendered() }
    }

    func cleanUp() {
        for f in files { try? FileManager.default.removeItem(at: f) }
        files.removeAll()
    }
}

enum GoldenLayerFactory {
    static func build(state: SceneLiveState, run: GoldenSceneRun, store: ParameterStore, device: MTLDevice,
                      graphPipeline: () throws(LayerSourceError) -> GeneratorGraphPipeline) throws(GoldenRenderError) -> GoldenSceneLayers {
        let layers = GoldenSceneLayers()
        for (index, entry) in state.stack.entries.enumerated() {
            guard let content = state.contents[entry.id] else {
                throw .sceneInvalid("no content for layer \(entry.id.rawValue)")
            }
            let isBottom = index == 0
            let layer: any LayerSource
            switch content {
            case let .material(id):
                guard let material = ProceduralMaterialLayer(materialID: id) else { throw .unsupportedLayer("material \(id)") }
                material.update(from: store)
                layer = material
            case let .generatorGraph(key):
                guard case let .generatorGraph(json)? = state.assets[key]?.kind else { throw .assetMissing(key) }
                do {
                    let imported = try GeneratorGraphImporter.importGraph(Data(json.canonicalBytes))
                    layer = GeneratorGraphLayer(compiled: imported.compiled, pipeline: try graphPipeline())
                } catch {
                    throw .layerFailed("graph \(key): \(error)")
                }
            case .circularSpectrum:
                var configuration = CircularSpectrumConfiguration()
                if !isBottom { configuration.background = LinearColor(red: 0, green: 0, blue: 0, alpha: 0) }
                do {
                    let generator = try CircularSpectrumGenerator(device: device, pixelFormat: LayerPictureDescriptor.metalPixelFormat,
                                                                  configuration: configuration)
                    layer = try SpectrumLayerSource(device: device, generator: generator, name: "spectrum.circular")
                } catch {
                    throw .layerFailed("circular spectrum: \(error)")
                }
            case .linearSpectrum:
                var configuration = LinearSpectrumConfiguration()
                if !isBottom { configuration.background = LinearColor(red: 0, green: 0, blue: 0, alpha: 0) }
                do {
                    let generator = try LinearSpectrumGenerator(device: device, pixelFormat: LayerPictureDescriptor.metalPixelFormat,
                                                                configuration: configuration)
                    layer = try SpectrumLayerSource(device: device, generator: generator, name: "spectrum.linear")
                } catch {
                    throw .layerFailed("linear spectrum: \(error)")
                }
            case let .photo(key):
                guard case let .photo(storeID)? = state.assets[key]?.kind else { throw .assetMissing(key) }
                guard let recipe = run.photos[storeID] else { throw .assetMissing("no generated photo for \(storeID)") }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("qa002-\(run.name)-\(storeID)-\(UUID().uuidString).png")
                do {
                    try GoldenPNG.encode(recipe.image()).write(to: url)
                } catch {
                    throw .layerFailed("photo \(key): \(error)")
                }
                layers.files.append(url)
                let photo = ImageLayerSource(device: device)
                photo.content = .file(url)
                layers.photos.append(photo)
                layer = photo
            case let .text(key):
                guard case let .text(json)? = state.assets[key]?.kind else { throw .assetMissing(key) }
                guard case let .spec(spec) = TextOverlaySpec.decodeStored(Data(json.canonicalBytes)) else {
                    throw .layerFailed("text \(key): not a version-1 text spec")
                }
                let text = TextLayerSource(device: device)
                text.spec = spec
                layers.texts.append(text)
                layer = text
            case .camera, .video, .unknown:
                throw .unsupportedLayer(content.kind)
            }
            layers.byID[entry.id] = layer
        }
        return layers
    }
}
#endif
