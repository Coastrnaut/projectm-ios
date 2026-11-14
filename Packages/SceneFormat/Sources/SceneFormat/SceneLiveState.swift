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
//
// CMP-004: the six blend mode names map to `LayerBlendMode`; any other `composite.blend` string is drawn
// as normal and kept in `preservedBlendModes`, which capture writes back while that layer is still
// drawn as normal (CMP-004-R8), so an unknown mode also survives load → capture.
//
// CMP-006: `composite.fit` with one of the four mode names maps to `LayerCompositeSettings.fit`; an
// unknown name maps to nil (the layer's default) and the saved fit is kept in `preservedFits`, which
// capture writes back while that layer still has no live fit (CMP-006-R10).
//
// CMP-007: a known `composite.mask` maps to `LayerCompositeSettings.mask`; an unknown shape maps to nil
// (drawn unmasked) and the saved mask is kept in `preservedMasks`, which capture writes back while that
// layer still has no live mask (CMP-007-R10).
//
// CMP-011: valid `groups` become the stack's groups (membership on each entry); invalid ones, and valid
// ones none of whose layers is live (unknown kinds), stay in `preservedGroups`, which capture writes
// back verbatim after the live groups (live groups in stack order, children in stack order).
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
    /// CMP-004: unknown blend mode names by instance, kept verbatim for re-save.
    public var preservedBlendModes: [LayerInstanceID: String]
    /// CMP-006: saved fits with an unknown mode name, by instance, kept verbatim for re-save.
    public var preservedFits: [LayerInstanceID: SceneFit]
    /// CMP-007: saved masks with an unknown shape kind, by instance, kept verbatim for re-save.
    public var preservedMasks: [LayerInstanceID: SceneMask]
    /// CMP-008: saved gradient masks with an unknown kind, by instance, kept verbatim for re-save.
    public var preservedGradientMasks: [LayerInstanceID: SceneGradientMask] = [:]
    /// CMP-011: saved groups that are not live (damaged, or without live layers), kept verbatim.
    public var preservedGroups: [SceneGroup]
    /// FX-020: the document's effect chain as stored (apply `SceneEffectSettings.read`; capture writes it back).
    public var effects: [SceneEffectEntry]?
    /// MOD-006: the document's threshold triggers as stored (apply `SceneTriggerEntry.read`; capture writes them back).
    public var triggers: [SceneTriggerEntry]?
    /// MOD-007: the document's oscillators as stored (apply `SceneLFOEntry.read`; capture writes them back).
    public var lfos: [SceneLFOEntry]?
    /// MOD-010: the document's macros as stored (apply `SceneMacroEntry.read`; capture writes them back).
    public var macros: [SceneMacroEntry]?
    /// SCN-008: the document's snapshots as stored (apply `SceneSnapshotEntry.read`; capture writes them back).
    public var snapshots: [SceneSnapshotEntry]?

    public init(stack: LayerStack, contents: [LayerInstanceID: SceneLayerContent] = [:],
                parameters: ParameterSnapshot = ParameterSnapshot(values: [:]), bindings: [AudioFeatureBinding] = [],
                expressions: [ParameterID: String] = [:], modulation: ModulationGraph = ModulationGraph(),
                preserved: SceneModulationPreserved = SceneModulationPreserved(), assets: [String: SceneAsset] = [:],
                preservedBlendModes: [LayerInstanceID: String] = [:], preservedFits: [LayerInstanceID: SceneFit] = [:],
                preservedMasks: [LayerInstanceID: SceneMask] = [:], preservedGroups: [SceneGroup] = [],
                effects: [SceneEffectEntry]? = nil, triggers: [SceneTriggerEntry]? = nil, lfos: [SceneLFOEntry]? = nil, macros: [SceneMacroEntry]? = nil,
                snapshots: [SceneSnapshotEntry]? = nil) {
        self.stack = stack
        self.contents = contents
        self.parameters = parameters
        self.bindings = bindings
        self.expressions = expressions
        self.modulation = modulation
        self.preserved = preserved
        self.assets = assets
        self.preservedBlendModes = preservedBlendModes
        self.preservedFits = preservedFits
        self.preservedMasks = preservedMasks
        self.preservedGroups = preservedGroups
        self.effects = effects
        self.triggers = triggers
        self.lfos = lfos
        self.macros = macros
        self.snapshots = snapshots
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
            let preserved = settings.blendMode == .normal ? live.preservedBlendModes[entry.id] : nil
            let blend = preserved ?? settings.blendMode.rawValue
            let fit: SceneFit? = settings.fit.map(SceneFit.init) ?? live.preservedFits[entry.id]   // CMP-006
            let mask: SceneMask? = settings.mask.map(SceneMask.known) ?? live.preservedMasks[entry.id]   // CMP-007
            let gradient: SceneGradientMask? = settings.gradientMask.map(SceneGradientMask.known)
                ?? live.preservedGradientMasks[entry.id]   // CMP-008
            layers.append(SceneLayer(instance: entry.id.rawValue, content: content, values: entry.descriptor.parameters,
                                     composite: SceneComposite(opacity: settings.opacity, blendMode: blend, transform: settings.transform,
                                                               fit: fit, mask: mask, gradientMask: gradient)))
        }
        // Canonical order (MOD-013-R10): live edges in live order, then preserved edges as stored.
        let bindings = SceneBinding.list(live.bindings, expressions: live.expressions) + live.preserved.bindings
        let connections = live.modulation.edges.map { (e: ModulationEdge) -> SceneConnection in SceneConnection(e) }
            + live.preserved.connections
        let groups = live.stack.groups.map { (g: LayerGroup) -> SceneGroup in SceneGroup(g, members: live.stack.members(of: g.id)) }
            + live.preservedGroups   // CMP-011
        self.init(id: id, name: name, layers: layers, parameters: live.parameters.values, bindings: bindings,
                  modulation: SceneModulation(generators: live.modulation.generators, connections: connections), assets: live.assets,
                  groups: groups, effects: live.effects, triggers: live.triggers, lfos: live.lfos, macros: live.macros,
                  snapshots: live.snapshots)   // FX-020, MOD-006, MOD-007, MOD-010, SCN-008
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
        var unknownBlends: [LayerInstanceID: String] = [:]
        var unknownFits: [LayerInstanceID: SceneFit] = [:]
        var unknownMasks: [LayerInstanceID: SceneMask] = [:]
        var unknownGradients: [LayerInstanceID: SceneGradientMask] = [:]
        for layer in layers {
            guard let kind = layer.content.layerKind else { continue }
            let id = LayerInstanceID(rawValue: layer.instance)
            let mode = LayerBlendMode(rawValue: layer.composite.blendMode)
            if mode == nil { unknownBlends[id] = layer.composite.blendMode }
            let fit: LayerFit? = layer.composite.fit?.layerFit
            if let saved = layer.composite.fit, fit == nil { unknownFits[id] = saved }
            let mask: LayerMask? = layer.composite.mask?.layerMask
            if let saved = layer.composite.mask, mask == nil { unknownMasks[id] = saved }
            let gradient: LayerGradientMask? = layer.composite.gradientMask?.layerGradientMask   // CMP-008
            if let saved = layer.composite.gradientMask, gradient == nil { unknownGradients[id] = saved }
            let settings = LayerCompositeSettings(opacity: layer.composite.opacity, blendMode: mode ?? .normal,
                                                  transform: layer.composite.transform, fit: fit, mask: mask, gradientMask: gradient)
            entries.append(LayerStackEntry(id: id, descriptor: LayerDescriptor(kind: kind, parameters: layer.values), settings: settings))
            contents[id] = layer.content
        }
        // CMP-011: valid groups with at least one live layer; the rest are preserved verbatim.
        var liveGroups: [LayerGroup] = []
        var preservedGroups: [SceneGroup] = []
        let valid = Set(analyzeGroups().valid)
        for (g, group) in groups.enumerated() {
            var members: Set<LayerInstanceID> = []
            for child in group.children {
                if case let .layer(instance) = child, contents[LayerInstanceID(rawValue: instance)] != nil {
                    members.insert(LayerInstanceID(rawValue: instance))
                }
            }
            guard valid.contains(g), !members.isEmpty else {
                preservedGroups.append(group)
                continue
            }
            let id = LayerGroupID(rawValue: group.id)
            for k in entries.indices where members.contains(entries[k].id) { entries[k].group = id }
            liveGroups.append(LayerGroup(id: id, settings: group.settings))
        }
        let stack: LayerStack
        do {
            stack = try LayerStack(restoring: entries, groups: liveGroups)
        } catch {
            // Unreachable after validation (duplicate IDs and kind limits are errors there).
            throw .invalid([SceneIssue(.duplicateInstance, path: "$.layers", "The layers cannot be restored: \(error).")])
        }
        let state = SceneLiveState(stack: stack, contents: contents, parameters: ParameterSnapshot(values: parameters),
                                   bindings: restore.bindings, expressions: restore.expressions, modulation: restore.graph,
                                   preserved: restore.preserved, assets: assets, preservedBlendModes: unknownBlends,
                                   preservedFits: unknownFits, preservedMasks: unknownMasks, preservedGroups: preservedGroups,
                                   effects: effects, triggers: triggers, lfos: lfos, macros: macros,
                                   snapshots: snapshots)   // FX-020, MOD-006, MOD-007, MOD-010, SCN-008
        var withGradients = state
        withGradients.preservedGradientMasks = unknownGradients   // CMP-008
        return SceneLoadResult(state: withGradients, warnings: issues, modulationReport: restore.report)
    }
}
