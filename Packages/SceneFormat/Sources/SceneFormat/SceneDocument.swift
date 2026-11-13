// SceneDocument.swift — the scene model, version 1 (SCN-001-R1 to R6, R13; data-model.md;
// contract C1, C3).
//
// Equality is semantic equality (contract C3), defined as equality of the canonical JSON values:
// maps compare without order, arrays (layers, bindings, connections) in order, numbers by their
// shortest round-trip text, which is one-to-one with the double's bits (so −0 ≠ 0), and preserved
// unknown content exactly as written.
import Compositor
import ParameterGraph

public enum SceneLimits {
    /// Checked on the byte count before anything is parsed.
    public static let maximumBytes = 1_048_576
    /// Checked while parsing (the document object is level 1).
    public static let maximumDepth = 32
    /// CMP-002: at most 8 layers in a stack.
    public static let maximumLayers = LayerStack.maximumLayerCount
    /// MOD-002-R7: at most 32 bindings.
    public static let maximumBindings = AudioFeatureModulator.maximumBindings
    public static let maximumParameterValues = 1_024
    public static let maximumAssets = 16
    public static let maximumValuesPerLayer = 64
    public static let maximumGenerators = 64
    public static let maximumConnections = 256
    /// Scene name length in characters (grapheme clusters).
    public static let maximumNameLength = 120
    /// Layer value names, in UTF-8 bytes.
    public static let maximumValueNameBytes = 64
    /// Asset keys, in UTF-8 bytes.
    public static let maximumAssetKeyBytes = 64
    /// 2^53 − 1: the largest integer every JSON reader keeps exactly.
    public static let maximumInstanceID: UInt64 = 9_007_199_254_740_991
}

public struct SceneDocument: Sendable, Hashable {
    public static let formatName = "projectm-ios.scene"
    public static let currentVersion = 1

    /// Canonical uppercase UUID text.
    public var id: String
    public var name: String
    /// Bottom first (CMP-002).
    public var layers: [SceneLayer]
    /// MOD-001 values by registry ID (as written; applied with `ParameterStore.restore`).
    public var parameters: [ParameterID: ParameterValue]
    /// In order (MOD-002 evaluates bindings in the order first bound).
    public var bindings: [SceneBinding]
    public var modulation: SceneModulation
    /// Scene-local asset keys.
    public var assets: [String: SceneAsset]
    /// Unknown top-level fields, kept verbatim (SCN-001-R10).
    public var extra: [String: SceneJSON]

    public init(id: String, name: String, layers: [SceneLayer] = [], parameters: [ParameterID: ParameterValue] = [:],
                bindings: [SceneBinding] = [], modulation: SceneModulation = SceneModulation(),
                assets: [String: SceneAsset] = [:], extra: [String: SceneJSON] = [:]) {
        self.id = id
        self.name = name
        self.layers = layers
        self.parameters = parameters
        self.bindings = bindings
        self.modulation = modulation
        self.assets = assets
        self.extra = extra
    }

    /// Semantic equality (contract C3).
    public static func == (lhs: SceneDocument, rhs: SceneDocument) -> Bool { lhs.json == rhs.json }

    public func hash(into hasher: inout Hasher) { hasher.combine(json) }
}

public struct SceneLayer: Sendable, Hashable {
    /// 1 … 2^53 − 1, unique in the document (CMP-002 instance ID).
    public var instance: UInt64
    public var content: SceneLayerContent
    /// The layer's own numbers (`LayerDescriptor.parameters`).
    public var values: [String: Double]
    public var composite: SceneComposite
    /// Unknown layer fields (and every other field of an unknown kind), kept verbatim.
    public var extra: [String: SceneJSON]

    public init(instance: UInt64, content: SceneLayerContent, values: [String: Double] = [:],
                composite: SceneComposite = SceneComposite(), extra: [String: SceneJSON] = [:]) {
        self.instance = instance
        self.content = content
        self.values = values
        self.composite = composite
        self.extra = extra
    }

    public var kind: String { content.kind }

    public static func == (lhs: SceneLayer, rhs: SceneLayer) -> Bool {
        SceneEncoder.layer(lhs) == SceneEncoder.layer(rhs)
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(SceneEncoder.layer(self)) }
}

/// A layer's kind and its kind-specific content (contract C1 table).
public enum SceneLayerContent: Sendable, Hashable {
    case camera
    case circularSpectrum
    case linearSpectrum
    case photo(asset: String)
    case video(asset: String)
    case text(asset: String)
    /// An SHD-001 material by its ID (`material.<name>`).
    case material(id: String)
    case generatorGraph(asset: String)
    /// A kind this version does not know; the layer's other fields stay in its `extra`.
    case unknown(kind: String)

    public var kind: String {
        switch self {
        case .camera: "camera"
        case .circularSpectrum: "spectrum.circular"
        case .linearSpectrum: "spectrum.linear"
        case .photo: "photo"
        case .video: "video"
        case .text: "text"
        case .material: "material"
        case .generatorGraph: "generator.graph"
        case let .unknown(kind): kind
        }
    }

    /// The asset key a content refers to, if any.
    public var assetKey: String? {
        switch self {
        case let .photo(key), let .video(key), let .text(key), let .generatorGraph(key): key
        default: nil
        }
    }

    /// The asset type a content's asset must have.
    var requiredAssetType: String? {
        switch self {
        case .photo: "photo"
        case .video: "video"
        case .text: "text"
        case .generatorGraph: "generatorGraph"
        default: nil
        }
    }

    public var isKnown: Bool { if case .unknown = self { false } else { true } }

    /// The kinds this version knows.
    public static let knownKinds: Set<String> = ["camera", "spectrum.circular", "spectrum.linear", "photo", "video", "text",
                                                 "material", "generator.graph"]
}

/// Opacity, blend mode and transform (CMP-003, CMP-004, CMP-005).
public struct SceneComposite: Sendable, Hashable {
    /// 0…1.
    public var opacity: Double
    /// `normal` is the only mode drawn today (CMP-004 adds more); any name is kept.
    public var blendMode: String
    public var transform: LayerTransform

    public static let normalBlendMode = "normal"

    public init(opacity: Double = 1, blendMode: String = SceneComposite.normalBlendMode, transform: LayerTransform = .identity) {
        self.opacity = opacity
        self.blendMode = blendMode
        self.transform = transform
    }

    public static func == (lhs: SceneComposite, rhs: SceneComposite) -> Bool {
        SceneEncoder.composite(lhs) == SceneEncoder.composite(rhs)
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(SceneEncoder.composite(self)) }
}

/// One MOD-002 binding as stored.
public struct SceneBinding: Sendable, Hashable {
    public var source: AudioFeatureSource
    public var target: ParameterID
    public var mapping: LinearMapping
    public var mix: ModulationMixMode
    public var envelope: AudioFeatureEnvelope
    /// SHD-009 source text; compiled by validation, evaluated by a later row.
    public var expression: String?
    public var extra: [String: SceneJSON]

    public init(source: AudioFeatureSource, target: ParameterID, mapping: LinearMapping, mix: ModulationMixMode = .replace,
                envelope: AudioFeatureEnvelope = .none, expression: String? = nil, extra: [String: SceneJSON] = [:]) {
        self.source = source
        self.target = target
        self.mapping = mapping
        self.mix = mix
        self.envelope = envelope
        self.expression = expression
        self.extra = extra
    }

    public init(_ binding: AudioFeatureBinding, expression: String? = nil) {
        self.init(source: binding.source, target: binding.target, mapping: binding.mapping, mix: binding.mixMode,
                  envelope: binding.envelope, expression: expression)
    }

    /// The MOD-002 binding (the expression is carried separately).
    public var audioFeatureBinding: AudioFeatureBinding {
        AudioFeatureBinding(source: source, target: target, inputMinimum: mapping.inputMinimum, inputMaximum: mapping.inputMaximum,
                            outputStart: mapping.outputStart, outputEnd: mapping.outputEnd, mixMode: mix, envelope: envelope)
    }

    public static func == (lhs: SceneBinding, rhs: SceneBinding) -> Bool {
        SceneEncoder.binding(lhs) == SceneEncoder.binding(rhs)
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(SceneEncoder.binding(self)) }
}

/// Generators and connections beyond the bindings (MOD-014 types; MOD-013 wires them).
public struct SceneModulation: Sendable, Hashable {
    public var generators: [ModulationGenerator]
    public var connections: [ModulationEdge]

    public init(generators: [ModulationGenerator] = [], connections: [ModulationEdge] = []) {
        self.generators = generators
        self.connections = connections
    }

    public var isEmpty: Bool { generators.isEmpty && connections.isEmpty }
}

public struct SceneAsset: Sendable, Hashable {
    public var kind: SceneAssetKind
    /// Unknown asset fields (and every field of an unknown type but `type`), kept verbatim.
    public var extra: [String: SceneJSON]

    public init(_ kind: SceneAssetKind, extra: [String: SceneJSON] = [:]) {
        self.kind = kind
        self.extra = extra
    }

    public static func photo(storeID: String) -> SceneAsset { SceneAsset(.photo(storeID: storeID)) }
    public static func video(storeID: String) -> SceneAsset { SceneAsset(.video(storeID: storeID)) }
}

public enum SceneAssetKind: Sendable, Hashable {
    /// The app's stored photo by its identifier (MED-001; uppercase UUID).
    case photo(storeID: String)
    /// The app's stored video by its identifier (MED-002; uppercase UUID).
    case video(storeID: String)
    /// MED-009 text overlay settings (version-1 JSON), embedded.
    case text(spec: SceneJSON)
    /// An SHD-002 generator graph document, embedded (SHD-011 rules on load).
    case generatorGraph(document: SceneJSON)
    case unknown(type: String)

    public var typeName: String {
        switch self {
        case .photo: "photo"
        case .video: "video"
        case .text: "text"
        case .generatorGraph: "generatorGraph"
        case let .unknown(type): type
        }
    }
}

extension SceneDocument {
    /// Asset keys: a lowercase ASCII letter, then ASCII letters and digits, at most 64 bytes.
    public static func isValidAssetKey(_ key: String) -> Bool {
        let u = Array(key.utf8)
        guard let first = u.first, first >= 0x61, first <= 0x7A, u.count <= SceneLimits.maximumAssetKeyBytes else { return false }
        return u.allSatisfy { (b: UInt8) -> Bool in
            (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) || (b >= 0x30 && b <= 0x39)
        }
    }

    /// Canonical UUID text: 8-4-4-4-12 uppercase hexadecimal digits (as `UUID().uuidString` writes).
    public static func isCanonicalUUID(_ text: String) -> Bool {
        let u = Array(text.utf8)
        guard u.count == 36 else { return false }
        for (i, b) in u.enumerated() {
            if i == 8 || i == 13 || i == 18 || i == 23 {
                guard b == UInt8(ascii: "-") else { return false }
            } else {
                guard (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46) else { return false }
            }
        }
        return true
    }
}
