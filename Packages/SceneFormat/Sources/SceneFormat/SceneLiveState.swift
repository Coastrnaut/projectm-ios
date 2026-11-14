// SceneLiveState.swift — adapters between a document and the live compositor stack, parameters
// and bindings (SCN-001-R11, R12; research SCN-001-D7; contract C6).
//
// The app (SCN-002) captures what its visual hosts hold — the `LayerStack` they apply, each
// entry's content (which photo, text, material or graph), the `ParameterStore` snapshot and the
// `AudioFeatureModulator` bindings — and restores them from a validated document. Nothing here
// touches files, stores or the GPU.
//
// MOD-013: modulation is restored per edge (`restoreModulation`): only restored and rewritten edges
// are live; orphaned and rejected edges ride along in `preserved` and capture writes them back after
// the live ones (contract M5, M6), so capture → encode → decode → restore → capture is a fixed point.
import Compositor
import ParameterGraph

public struct SceneLiveState: Sendable, Equatable {
    /// Saved instance IDs and order; unknown kinds are not in it.
    public var stack: LayerStack
    /// Every live entry's content (camera and spectra included), by instance ID.
    public var contents: [LayerInstanceID: SceneLayerContent]
    /// Values as written; apply with `ParameterStore.restore` (MOD-001 clamping and reports).
    public var parameters: ParameterSnapshot
    /// Live bindings in order; apply with `apply(to:)`.
    public var bindings: [AudioFeatureBinding]
    /// SHD-009 source text by bound target (evaluation is a later row).
    public var expressions: [ParameterID: String]
    /// Declared generators and live connections (binding edges are in `bindings`).
    public var modulation: ModulationGraph
    /// Orphaned and rejected edges, kept verbatim for re-save (MOD-013-R9).
    public var preserved: SceneModulationPreserved
    public var assets: [String: SceneAsset]

    public init(stack: LayerStack, contents: [LayerInstanceID: SceneLayerContent] = [:],
                parameters: ParameterSnapshot = ParameterSnapshot(values: [:]), bindings: [AudioFeatureBinding] = [],
                expressions: [ParameterID: String] = [:], modulation: ModulationGraph = ModulationGraph(),
                preserved: SceneModulationPreserved = SceneModulationPreserved(), assets: [String: SceneAsset] = [:]) {
        self.stack = stack
        self.contents = contents
        self.parameters = parameters
        self.bindings = bindings
        self.expressions = expressions
        self.modulation = modulation
        self.preserved = preserved
        self.assets = assets
    }

    /// Replaces `modulator`'s bindings with the live ones, in order (contract M5). They were
    /// validated against the same registry on load, so this throws only for another registry.
    public func apply(to modulator: AudioFeatureModulator) throws(AudioFeatureBindingError) {
        modulator.unbindAll()
        for binding in bindings { try modulator.bind(binding) }
    }

    /// The MOD-014 validated graph of the live binding edges plus `modulation` (contract M5).
    public func validatedGraph(registry: ParameterRegistry) throws(ModulationGraphError) -> ValidatedModulationGraph {
        let bindingEdges = bindings.map { (b: AudioFeatureBinding) -> ModulationEdge in
            ModulationEdge(source: .audio(b.source), target: .parameter(b.target))
        }
        return try ValidatedModulationGraph(ModulationGraph(generators: modulation.generators, edges: bindingEdges + modulation.edges),
                                            registry: registry)
    }
}

/// What `liveState` returns: the live state and the warnings that did not prevent it.
public struct SceneLoadResult: Sendable {
    public let state: SceneLiveState
    public let warnings: [SceneIssue]
    /// Every binding and connection with its outcome and path (MOD-013-R7).
    public let modulationReport: SceneModulationReport
}

extension SceneDocument {
    /// Captures a live state as a document (contract C6). Camera and spectrum entries need no
    /// content; every other entry needs one of its own kind.
    public init(capturing live: SceneLiveState, id: String, name: String) throws(SceneCaptureError) {
        var layers: [SceneLayer] = []
        for entry in live.stack.entries {
            let kind = entry.descriptor.kind.identifier
            let content: SceneLayerContent
            if let given = live.contents[entry.id] {
                content = given
            } else {
                switch kind {
                case "camera": content = .camera
                case "spectrum.circular": content = .circularSpectrum
                case "spectrum.linear": content = .linearSpectrum
                default: throw .missingContent(instance: entry.id.rawValue)
                }
            }
            guard content.kind == kind else {
                throw .contentMismatch(instance: entry.id.rawValue, stackKind: kind, contentKind: content.kind)
            }
            let settings = entry.settings
            let blend = settings.blendMode.rawValue
            layers.append(SceneLayer(instance: entry.id.rawValue, content: content, values: entry.descriptor.parameters,
                                     composite: SceneComposite(opacity: settings.opacity, blendMode: blend, transform: settings.transform)))
        }
        // Canonical order (MOD-013-R10): live edges in live order, then preserved edges as stored.
        let bindings = live.bindings.map { (b: AudioFeatureBinding) -> SceneBinding in
            SceneBinding(b, expression: live.expressions[b.target])
        } + live.preserved.bindings
        let connections = live.modulation.edges.map { (e: ModulationEdge) -> SceneConnection in SceneConnection(e) }
            + live.preserved.connections
        self.init(id: id, name: name, layers: layers, parameters: live.parameters.values, bindings: bindings,
                  modulation: SceneModulation(generators: live.modulation.generators, connections: connections), assets: live.assets)
    }

    /// The live state of a document without errors (contract C6). Errors refuse it whole
    /// (SCN-001-R11); warnings are returned with it. Unknown kinds are left out of the stack.
    public func liveState(registry: ParameterRegistry,
                          assets availability: (any SceneAssetAvailability)? = nil) throws(SceneLoadError) -> SceneLoadResult {
        let issues = validate(registry: registry, assets: availability)
        let restore = restoreModulation(registry: registry)
        let errors = issues.filter(\.isError)
        guard errors.isEmpty else { throw .invalid(errors) }
        var entries: [LayerStackEntry] = []
        var contents: [LayerInstanceID: SceneLayerContent] = [:]
        for layer in layers {
            guard let kind = layer.content.layerKind else { continue }
            let id = LayerInstanceID(rawValue: layer.instance)
            let settings = LayerCompositeSettings(opacity: layer.composite.opacity, blendMode: .normal,
                                                  transform: layer.composite.transform)
            entries.append(LayerStackEntry(id: id, descriptor: LayerDescriptor(kind: kind, parameters: layer.values), settings: settings))
            contents[id] = layer.content
        }
        let stack: LayerStack
        do {
            stack = try LayerStack(restoring: entries)
        } catch {
            // Unreachable after validation (duplicate IDs and kind limits are errors there).
            throw .invalid([SceneIssue(.duplicateInstance, path: "$.layers", "The layers cannot be restored: \(error).")])
        }
        let state = SceneLiveState(stack: stack, contents: contents, parameters: ParameterSnapshot(values: parameters),
                                   bindings: restore.bindings, expressions: restore.expressions, modulation: restore.graph,
                                   preserved: restore.preserved, assets: assets)
        return SceneLoadResult(state: state, warnings: issues, modulationReport: restore.report)
    }
}
