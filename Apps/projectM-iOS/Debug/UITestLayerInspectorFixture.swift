// UITestLayerInspectorFixture.swift — DEBUG only (CMP-015-T08; contracts/layer-inspector.md L5).
// `-uitestLayerInspectorSeed` (with `-uitestSeedPhoto solid`) makes a three-layer scene before the scene
// history starts: the Photo visual, the photo at 80 % with fit "Fit", the circular spectrum at 60 %
// with Screen and position X 0.25, and a carried `material.plasma` layer on top at 50 % with Add (a kind
// this version keeps but does not draw). Not compiled into Release builds.
#if DEBUG
import Compositor
import Foundation
import SceneFormat

@MainActor
enum UITestLayerInspectorFixture {
    static let argument = "-uitestLayerInspectorSeed"

    static var composites: [String: SceneComposite] {
        let moved: LayerTransform = (try? LayerTransform(translation: LayerPoint(x: 0.25, y: 0))) ?? .identity
        return [
            "photo": SceneComposite(opacity: 0.8, fit: SceneFit(mode: LayerFitMode.fit.rawValue)),
            "spectrum.circular": SceneComposite(opacity: 0.6, blendMode: LayerBlendMode.screen.rawValue, transform: moved),
        ]
    }

    /// Bottom first: photo, spectrum, material.
    static var carriedLayers: [SceneLayer] {
        [
            SceneLayer(instance: 1, content: .photo(asset: SceneAutosaveCapture.photoKey)),
            SceneLayer(instance: 2, content: .circularSpectrum),
            SceneLayer(instance: 3, content: .material(id: "material.plasma"),
                       composite: SceneComposite(opacity: 0.5, blendMode: LayerBlendMode.add.rawValue)),
        ]
    }

    static func seedIfRequested(_ coordinator: AppCoordinator) {
        guard ProcessInfo.processInfo.arguments.contains(argument) else { return }
        coordinator.settings.visual = .photo
        coordinator.sceneAutosave?.seedCarriedLayersForUITest(carriedLayers)
        coordinator.layers.restore(composites)
    }
}
#endif
