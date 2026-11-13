// SceneFixtures.swift — the all-kinds fixture and shared helpers (SCN-001-T08).
import Compositor
import Foundation
import GeneratorGraph
import ParameterGraph
import ProceduralMaterials
@testable import SceneFormat
import TextLayer
import VisualParameters

enum SceneFixtures {
    static let sceneID = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
    static let photoID = "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"
    static let videoID = "F0E1D2C3-B4A5-9687-7869-5A4B3C2D1E0F"

    /// The visual catalog (VIS, FX) plus the material catalog (SHD-001), as the app combines them.
    static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: VisualParameterCatalog.descriptors + ProceduralMaterialCatalog.descriptors)
    }

    static func json(_ text: String) throws -> SceneJSON {
        try SceneJSONParser.parse(Array(text.utf8), maximumDepth: 32)
    }

    static func json(_ data: Data) throws -> SceneJSON {
        try SceneJSONParser.parse(Array(data), maximumDepth: 32)
    }

    static func textSpec() throws -> SceneJSON {
        try json(TextOverlaySpec(message: "Night \"Drive\"\nLive").encodedForStorage())
    }

    static func graphDocument() throws -> SceneJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try json(try encoder.encode(GeneratorGraphExamples.emberDrift))
    }

    static func transform(_ tx: Double, _ ty: Double, scale: (Double, Double), rotation: Double, anchor: (Double, Double)) throws -> LayerTransform {
        try LayerTransform(translation: LayerPoint(x: tx, y: ty), scale: LayerPoint(x: scale.0, y: scale.1), rotation: rotation,
                           anchor: LayerPoint(x: anchor.0, y: anchor.1))
    }

    /// Every layer kind (8 layers: the stack's limit), composite settings and transforms, parameters of
    /// every value kind, two bindings (mapping, envelope, mix, an expression), a modulation generator
    /// and connection, assets of every type and an unknown future layer kind with extra fields.
    static func allKinds() throws -> SceneDocument {
        let layers: [SceneLayer] = [
            SceneLayer(instance: 1, content: .camera),
            SceneLayer(instance: 2, content: .circularSpectrum, values: ["glowBoost": 0.75],
                       composite: SceneComposite(opacity: 0.8, transform: try transform(0, 0, scale: (1, 1), rotation: 0.3, anchor: (0.5, 0.5)))),
            SceneLayer(instance: 9, content: .photo(asset: "photo1"),
                       composite: SceneComposite(opacity: 0.5, transform: try transform(0.1, -0.2, scale: (1.5, 1.25),
                                                                                         rotation: -0.7853981633974483, anchor: (0.25, 0.75)))),
            SceneLayer(instance: 10, content: .video(asset: "clip"), composite: SceneComposite(opacity: 1.0 / 3.0)),
            SceneLayer(instance: 11, content: .text(asset: "caption")),
            SceneLayer(instance: 12, content: .material(id: "material.plasma"), values: ["mix": 1e-7]),
            SceneLayer(instance: 13, content: .generatorGraph(asset: "graph1"),
                       composite: SceneComposite(opacity: 0.25, transform: try transform(-1.5, 2, scale: (0.05, 20), rotation: 12.5, anchor: (0, 1)))),
            SceneLayer(instance: 40, content: .unknown(kind: "particles.v9"), values: ["rate": 30],
                       extra: ["content": try json("{\"emitters\":3,\"seed\":42,\"shape\":\"ring\",\"weights\":[0.5,1e-300,123456789012345678901]}"),
                               "futureFlag": .bool(true)]),
        ]
        let parameters: [ParameterID: ParameterValue] = [
            VisualParameterIDs.circularSpectrumBarCount: .enumeration("64"),
            VisualParameterIDs.circularSpectrumGap: .continuous(0.1),
            VisualParameterIDs.linearSpectrumOrientation: .enumeration("horizontal"),
            VisualParameterIDs.bloomEnabled: .boolean(true),
            "material.gradient.colorA": .color(ParameterColor(red: 1, green: 0.5, blue: 0, alpha: 1)),
            "material.noiseFlow.octaves": .integer(4),
            "material.plasma.speed": .continuous(0.25),
        ]
        let bindings: [SceneBinding] = [
            SceneBinding(source: .band(2), target: VisualParameterIDs.circularSpectrumGap,
                         mapping: LinearMapping(inputMinimum: 0, inputMaximum: 0.8, outputStart: 0, outputEnd: 0.5),
                         mix: .replace, envelope: AudioFeatureEnvelope(attackSeconds: 0.05, releaseSeconds: 0.3),
                         expression: "audio.onset * 2"),
            SceneBinding(source: .onset, target: VisualParameterIDs.bloomIntensity,
                         mapping: LinearMapping(outputStart: 1, outputEnd: 0.25), mix: .multiply,
                         extra: ["futureCurve": .string("easeIn")]),
        ]
        let modulation = SceneModulation(
            generators: [ModulationGenerator(id: "lfo.one", displayName: "LFO One", inputs: ["rate"])],
            connections: [ModulationEdge(source: .generator("lfo.one"), target: .parameter(VisualParameterIDs.bloomRadius))])
        let assets: [String: SceneAsset] = [
            "photo1": .photo(storeID: photoID),
            "clip": SceneAsset(.video(storeID: videoID), extra: ["futureNote": .string("kept")]),
            "caption": SceneAsset(.text(spec: try textSpec())),
            "graph1": SceneAsset(.generatorGraph(document: try graphDocument())),
        ]
        return SceneDocument(id: sceneID, name: "Night Drive ✨", layers: layers, parameters: parameters, bindings: bindings,
                             modulation: modulation, assets: assets, extra: ["futureTopLevel": try json("{\"a\":[1,2]}")])
    }

    /// A minimal valid document's canonical text, for hand-edited variants in tests.
    static let minimalText = "{\"assets\":{},\"bindings\":[],\"format\":\"projectm-ios.scene\",\"id\":\"\(sceneID)\",\"layers\":[],\"name\":\"Empty\",\"parameters\":{},\"version\":1}"
}

/// The app's stores, faked: which photo and video identifiers exist on this device.
struct FakeAvailability: SceneAssetAvailability {
    var photos: Set<String> = [SceneFixtures.photoID]
    var videos: Set<String> = [SceneFixtures.videoID]
    func containsPhoto(storeID: String) -> Bool { photos.contains(storeID) }
    func containsVideo(storeID: String) -> Bool { videos.contains(storeID) }
}

extension Array where Element == UInt8 {
    var text: String { String(decoding: self, as: UTF8.self) }
}

extension String {
    var bytes: [UInt8] { Array(utf8) }
}
