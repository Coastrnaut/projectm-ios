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
    /// CMP-011: layer groups (SceneGroup.swift); written only when not empty.
    public var groups: [SceneGroup]
    /// FX-020: the effect chain (SceneEffectChain.swift); nil = no `effects` field (today's order, values untouched).
    public var effects: [SceneEffectEntry]?
    /// MOD-006: threshold triggers (SceneTriggers.swift), verbatim; nil = no `triggers` field.
    public var triggers: [SceneTriggerEntry]?
    /// Unknown top-level fields, kept verbatim (SCN-001-R10).
    public var extra: [String: SceneJSON]

    public init(id: String, name: String, layers: [SceneLayer] = [], parameters: [ParameterID: ParameterValue] = [:],
                bindings: [SceneBinding] = [], modulation: SceneModulation = SceneModulation(),
                assets: [String: SceneAsset] = [:], groups: [SceneGroup] = [], effects: [SceneEffectEntry]? = nil,
                triggers: [SceneTriggerEntry]? = nil, extra: [String: SceneJSON] = [:]) {
        self.id = id
        self.name = name
        self.layers = layers
        self.parameters = parameters
        self.bindings = bindings
        self.modulation = modulation
        self.assets = assets
        self.groups = groups
        self.effects = effects
        self.triggers = triggers
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

/// CMP-006: a layer's saved fit: a mode name (`fill`, `fit`, `stretch`, `pixelAccurate` are drawn; any
/// other name is kept, drawn as the layer's default and warned about, `unsupportedFitMode`) and an
/// anchor in content fractions (0…1; centre by default).
public struct SceneFit: Sendable, Hashable {
    public var mode: String
    public var anchor: LayerPoint

    public init(mode: String, anchor: LayerPoint = LayerPoint(x: 0.5, y: 0.5)) {
        self.mode = mode
        self.anchor = anchor
    }

    /// A live fit's saved form.
    public init(_ fit: LayerFit) {
        self.init(mode: fit.mode.rawValue, anchor: fit.anchor)
    }

    /// The live fit, nil for a mode name this version does not draw.
    public var layerFit: LayerFit? { LayerFitMode(rawValue: mode).map { LayerFit(mode: $0, anchor: anchor) } }

    public static func == (lhs: SceneFit, rhs: SceneFit) -> Bool { SceneEncoder.fit(lhs) == SceneEncoder.fit(rhs) }

    public func hash(into hasher: inout Hasher) { hasher.combine(SceneEncoder.fit(self)) }
}

/// CMP-007: a layer's saved shape mask: a live mask (`ellipse`, `rectangle`, `polygon`), or the whole
/// object of a shape kind this version does not draw, kept verbatim (drawn unmasked and warned about,
/// `unsupportedMaskShape`). Equality and hashing go through the saved form.
public enum SceneMask: Sendable, Hashable {
    case known(LayerMask)
    case unknown(shape: String, object: [String: SceneJSON])

    /// The saved `shape` name.
    public var shape: String {
        switch self {
        case let .known(mask): mask.shape.kindName
        case let .unknown(shape, _): shape
        }
    }

    /// The live mask, nil for a shape kind this version does not draw.
    public var layerMask: LayerMask? {
        if case let .known(mask) = self { return mask }
        return nil
    }

    public static func == (lhs: SceneMask, rhs: SceneMask) -> Bool { SceneEncoder.mask(lhs) == SceneEncoder.mask(rhs) }

    public func hash(into hasher: inout Hasher) { hasher.combine(SceneEncoder.mask(self)) }
}

/// Opacity, blend mode, transform, fit and mask (CMP-003, CMP-004, CMP-005, CMP-006, CMP-007).
public struct SceneComposite: Sendable, Hashable {
    /// 0…1.
    public var opacity: Double
    /// A `LayerBlendMode` name (`normal`, `add`, `screen`, `multiply`, `overlay`, `difference`; CMP-004)
    /// is drawn; any other name is kept, drawn as normal and warned about (`unsupportedBlendMode`).
    public var blendMode: String
    public var transform: LayerTransform
    /// CMP-006: nil when the layer has no fit set (the field is not written; the layer draws its default).
    public var fit: SceneFit?
    /// CMP-007: nil when the layer has no mask (the field is not written).
    public var mask: SceneMask?

    public static let normalBlendMode = "normal"

    public init(opacity: Double = 1, blendMode: String = SceneComposite.normalBlendMode, transform: LayerTransform = .identity,
                fit: SceneFit? = nil, mask: SceneMask? = nil) {
        self.opacity = opacity
        self.blendMode = blendMode
        self.transform = transform
        self.fit = fit
        self.mask = mask
    }

    public static func == (lhs: SceneComposite, rhs: SceneComposite) -> Bool {
        SceneEncoder.composite(lhs) == SceneEncoder.composite(rhs)
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(SceneEncoder.composite(self)) }
}

/// One MOD-002 binding as stored.
public struct SceneBinding: Sendable, Hashable {
    /// The audio feature's stable ID as written; an ID this version does not know is kept
    /// (MOD-013-R11) and the binding is orphaned.
    public var sourceID: String
    public var target: ParameterID
    public var mapping: LinearMapping
    public var mix: ModulationMixMode
    public var envelope: AudioFeatureEnvelope
    /// SHD-009 source text; compiled by validation, evaluated by a later row.
    public var expression: String?
    /// MOD-004: stored as the optional `curve` field, omitted for linear. A stored curve this version
    /// cannot read stays in `extra["curve"]` verbatim and restore rejects the binding (`unsupportedCurve`).
    public var curve: MappingCurve
    public var extra: [String: SceneJSON]

    public init(sourceID: String, target: ParameterID, mapping: LinearMapping, mix: ModulationMixMode = .replace,
                envelope: AudioFeatureEnvelope = .none, expression: String? = nil, curve: MappingCurve = .linear,
                extra: [String: SceneJSON] = [:]) {
        self.sourceID = sourceID
        self.target = target
        self.mapping = mapping
        self.mix = mix
        self.envelope = envelope
        self.expression = expression
        self.curve = curve
        self.extra = extra
    }

    public init(source: AudioFeatureSource, target: ParameterID, mapping: LinearMapping, mix: ModulationMixMode = .replace,
                envelope: AudioFeatureEnvelope = .none, expression: String? = nil, curve: MappingCurve = .linear,
                extra: [String: SceneJSON] = [:]) {
        self.init(sourceID: source.id, target: target, mapping: mapping, mix: mix, envelope: envelope, expression: expression,
                  curve: curve, extra: extra)
    }

    public init(_ binding: AudioFeatureBinding, expression: String? = nil) {
        self.init(source: binding.source, target: binding.target, mapping: binding.mapping, mix: binding.mixMode,
                  envelope: binding.envelope, expression: expression, curve: binding.curve)
    }

    /// The stored curve could not be read by this version (kept verbatim in `extra`).
    var hasUnreadableCurve: Bool { extra["curve"] != nil }

    /// The audio feature, when this version knows `sourceID`.
    public var source: AudioFeatureSource? {
        get { AudioFeatureSource(id: sourceID) }
        set { if let newValue { sourceID = newValue.id } }
    }

    /// The MOD-002 binding (the expression is carried separately), or nil for an unknown source.
    public var audioFeatureBinding: AudioFeatureBinding? {
        source.map { (s: AudioFeatureSource) -> AudioFeatureBinding in audioFeatureBinding(source: s, target: target) }
    }

    func audioFeatureBinding(source: AudioFeatureSource, target: ParameterID) -> AudioFeatureBinding {
        AudioFeatureBinding(source: source, target: target, inputMinimum: mapping.inputMinimum, inputMaximum: mapping.inputMaximum,
                            outputStart: mapping.outputStart, outputEnd: mapping.outputEnd, mixMode: mix, envelope: envelope,
                            curve: curve)
    }

    /// `audio.band.2 → visual.circularSpectrum.gap`.
    public var edgeText: String { sourceID + " → " + target.rawValue }

    public static func == (lhs: SceneBinding, rhs: SceneBinding) -> Bool {
        SceneEncoder.binding(lhs) == SceneEncoder.binding(rhs)
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(SceneEncoder.binding(self)) }
}

/// One end of a stored modulation connection: its kind and stable ID as written. Unlike
/// `ModulationNode`, an audio feature this version does not know is kept (MOD-013-R11).
public enum SceneNodeRef: Sendable, Hashable, CustomStringConvertible {
    case audio(String)
    case parameter(ParameterID)
    case generator(String)

    public init(_ node: ModulationNode) {
        switch node {
        case let .audio(source): self = .audio(source.id)
        case let .parameter(id): self = .parameter(id)
        case let .generator(id): self = .generator(id)
        }
    }

    public var kindName: String {
        switch self {
        case .audio: "audio"
        case .parameter: "parameter"
        case .generator: "generator"
        }
    }

    public var id: String {
        switch self {
        case let .audio(id), let .generator(id): id
        case let .parameter(id): id.rawValue
        }
    }

    /// The live node, or nil for an audio feature this version does not know.
    public var node: ModulationNode? {
        switch self {
        case let .audio(id): AudioFeatureSource(id: id).map { (s: AudioFeatureSource) -> ModulationNode in .audio(s) }
        case let .parameter(id): .parameter(id)
        case let .generator(id): .generator(id)
        }
    }

    public var description: String { id }
}

/// One stored modulation connection: `source` drives `input` of `target`.
public struct SceneConnection: Sendable, Hashable, CustomStringConvertible {
    public var source: SceneNodeRef
    public var target: SceneNodeRef
    public var input: String

    public init(source: SceneNodeRef, target: SceneNodeRef, input: String = ModulationEdge.valueInput) {
        self.source = source
        self.target = target
        self.input = input
    }

    public init(_ edge: ModulationEdge) {
        self.init(source: SceneNodeRef(edge.source), target: SceneNodeRef(edge.target), input: edge.input)
    }

    /// The live connection, or nil when an end is an unknown audio feature.
    public var edge: ModulationEdge? {
        guard let s = source.node, let t = target.node else { return nil }
        return ModulationEdge(source: s, target: t, input: input)
    }

    /// As `ModulationEdge` writes it: `lfo.one → effect.bloom.radius`, `x → lfo.one.rate`.
    public var description: String {
        source.id + " → " + (input == ModulationEdge.valueInput ? target.id : target.id + "." + input)
    }
}

/// Generators and connections beyond the bindings (MOD-014 types; MOD-013 wires them).
public struct SceneModulation: Sendable, Hashable {
    public var generators: [ModulationGenerator]
    public var connections: [SceneConnection]

    public init(generators: [ModulationGenerator] = [], connections: [SceneConnection] = []) {
        self.generators = generators
        self.connections = connections
    }

    public init(generators: [ModulationGenerator] = [], edges: [ModulationEdge]) {
        self.init(generators: generators, connections: edges.map { (e: ModulationEdge) -> SceneConnection in SceneConnection(e) })
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
    /// MED-010: the logo overlay's stored picture (a reference in the photo folder; uppercase UUID).
    /// Its placement is the optional `placement` object (`SceneAsset.logoPlacement`).
    case logo(storeID: String)
    /// MED-009 text overlay settings (version-1 JSON), embedded.
    case text(spec: SceneJSON)
    /// An SHD-002 generator graph document, embedded (SHD-011 rules on load).
    case generatorGraph(document: SceneJSON)
    case unknown(type: String)

    public var typeName: String {
        switch self {
        case .photo: "photo"
        case .video: "video"
        case .logo: "logo"
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
