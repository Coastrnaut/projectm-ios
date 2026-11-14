// SceneAutosaveCapture.swift — the app's current scene ↔ an SCN-001 document (SCN-002-R1, R8, R9;
// research SCN-002-D1, D2, D6; data-model "SceneInputs", "SceneAutosaveCarry").
//
// * `SceneInputs` is what the user can edit today (Settings): the visual, the spectra's bar count,
//   orientation and spacing, the glow, the Text visual's spec and the stored photo and video. Camera
//   is session only (CAM-001-R11): the visual chosen before it is recorded.
// * Layers per visual, bottom first (the hosts' fixed stacks): Circular `[spectrum.circular]`, Linear
//   `[spectrum.linear]`, Photo `[photo, spectrum.circular]`, Video `[video, spectrum.circular]`, Text
//   `[spectrum.circular, text]`, projectM `[]`. A photo or video layer is left out when none is stored.
// * The carry (the restored document) keeps what the app does not own: the scene ID and name, unknown
//   document fields, layers of kinds the app does not build (unknown kinds, materials, generator
//   graphs) at their index, matched layers' instance IDs, values and composites, the assets those
//   layers use and assets of unknown types, parameter values the app does not hold, the bindings when
//   no native spectrum is live, expressions, the modulation section and MOD-013's preserved edges.
// * FX-020 (specs/142-fx-020-effect-chains, research FX-020-D7): `SceneInputs.effects` is the live effect chain
//   (order, Color, Trails). The document's `effects` list is written when the opened scene had one (carried) or the
//   live chain is not the default; it keeps unknown entries at their index. A restore hands the list back (nil: none,
//   which restores the standard order and leaves the Color and Trails values alone).
// * Pure functions; the coordinator calls them on the main actor.
import Compositor
import Foundation
import ParameterGraph
import SceneFormat
import TextLayer
import VisualGenerators
import VisualParameters

struct SceneInputs: Equatable, Sendable {
    var visual: VisualChoice
    var bars: Int
    var orientation: LinearSpectrumOrientation
    var spacing: Double
    var glowEnabled: Bool
    var glowIntensity: Double
    var glowRadius: Double
    var glowThreshold: Double
    var text: TextOverlaySpec
    var photoID: UUID?
    var videoID: UUID?
    /// MED-003-R8: the stored video's loop region (nil: the whole file).
    var videoLoop: SceneVideoLoop? = nil
    /// MED-004-R7: the stored video's speed in percent (nil: 1×).
    var videoSpeedPercent: Int? = nil
    /// MED-006-R12: the image slideshow (nil: off and empty).
    var slideshow: SceneSlideshow? = nil
    /// CMP-015-R5 (research CMP-015-D2): the saved composite of each drawn layer kind (`photo`, `video`,
    /// `text`, `spectrum.circular`), edited in the layer inspector. nil keeps a matched layer's carried
    /// composite (callers that do not track composites); non-nil is authoritative, a missing kind
    /// writing the default composite. Default composites are never stored.
    var layerComposites: [String: SceneComposite]? = nil
    /// MED-010-R10: the logo overlay and its placement (nil: no logo). Recorded for every visual.
    var logo: SceneLogo? = nil
    /// FX-020: the live effect chain (nil: the caller does not track it; the carried list is kept).
    var effects: SceneEffectSettings? = nil
}

/// What a restore hands back to the app (contract A5).
struct SceneRestoredValues: Sendable, Equatable {
    /// The app-held parameter values present in the document, after MOD-001 restore (clamped).
    var parameters: [ParameterID: ParameterValue]
    var text: TextOverlaySpec?
    var bindings: [AudioFeatureBinding]
    /// MED-003-R8: the first video layer's stored-video ID and loop (nil: none).
    var videoStoreID: String? = nil
    var videoLoop: SceneVideoLoop? = nil
    /// MED-004-R7: the video asset's speed in percent (nil: 1×).
    var videoSpeedPercent: Int? = nil
    /// MED-006-R12: the photo layer's slideshow (nil: no photo layer).
    var slideshow: SceneSlideshowRestore? = nil
    /// CMP-015: the document's drawn-layer composites (first layer of each kind; defaults left out).
    var layerComposites: [String: SceneComposite] = [:]
    /// MED-010-R10: the scene's logo (nil: none recorded; the current logo stays).
    var logo: SceneLogo? = nil
    /// FX-020: the document's effect chain (nil: no list).
    var effects: [SceneEffectEntry]? = nil
}

/// The restored document's content the app does not own (research SCN-002-D6).
struct SceneAutosaveCarry: Sendable {
    var id: String
    var name: String
    var extra: [String: SceneJSON] = [:]
    var layers: [SceneLayer] = []
    var assets: [String: SceneAsset] = [:]
    var parameters: [ParameterID: ParameterValue] = [:]
    var bindings: [AudioFeatureBinding] = []
    var expressions: [ParameterID: String] = [:]
    var modulation = ModulationGraph()
    var preserved = SceneModulationPreserved()
    /// FX-020: the opened scene's effect list (nil: none).
    var effects: [SceneEffectEntry]?
    /// MOD-006: the opened scene's threshold triggers as stored (nil: none); written back unchanged.
    var triggers: [SceneTriggerEntry]?
    /// MOD-007: the opened scene's oscillators as stored (nil: none); written back unchanged.
    var lfos: [SceneLFOEntry]?
    /// SCN-008: the current scene's snapshots as stored (nil: none); written back unchanged, edited by
    /// `SceneAutosaveCoordinator.replaceSnapshots`.
    var snapshots: [SceneSnapshotEntry]?

    static let defaultName = "Current Scene"

    /// A new current scene (first save): a fresh canonical UUID.
    static func fresh() -> SceneAutosaveCarry {
        SceneAutosaveCarry(id: UUID().uuidString, name: defaultName)
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(document: SceneDocument, live: SceneLiveState) {
        id = document.id
        name = document.name
        extra = document.extra
        layers = document.layers
        assets = document.assets
        parameters = document.parameters
        bindings = live.bindings
        expressions = live.expressions
        modulation = live.modulation
        preserved = live.preserved
        effects = document.effects   // FX-020
        triggers = document.triggers   // MOD-006
        lfos = document.lfos   // MOD-007
        snapshots = document.snapshots   // SCN-008
    }
}

enum SceneAutosaveCapture {
    /// The parameters the app holds in AppSettings (MOD-001 IDs).
    static let appParameterIDs: [ParameterID] = [
        VisualParameterIDs.circularSpectrumBarCount, VisualParameterIDs.linearSpectrumOrientation,
        VisualParameterIDs.linearSpectrumSpacing, VisualParameterIDs.bloomEnabled, VisualParameterIDs.bloomIntensity,
        VisualParameterIDs.bloomRadius, VisualParameterIDs.bloomThreshold,
    ]
    /// Layer kinds the app builds; layers of every other kind are carried.
    static let appLayerKinds: Set<String> = ["camera", "spectrum.circular", "spectrum.linear", "photo", "video", "text"]
    static let photoKey = "photo"
    static let videoKey = "video"
    static let textKey = "text"

    /// The visual a scene records: Camera is session only (CAM-001-R11), so the one chosen before it.
    static func recordedVisual(_ visual: VisualChoice, beforeCamera: VisualChoice) -> VisualChoice {
        visual.usesCamera ? (beforeCamera.usesCamera ? .projectM : beforeCamera) : visual
    }

    // MARK: Capture

    /// The document for `inputs` over `carry`. `liveBindings` nil: no native spectrum, keep the
    /// carried bindings. Events report content dropped or renumbered while merging.
    static func document(_ inputs: SceneInputs, carry: SceneAutosaveCarry, liveBindings: [AudioFeatureBinding]?)
        -> (document: SceneDocument, events: [SceneAutosaveEvent]) {
        var events: [SceneAutosaveEvent] = []
        var assets: [String: SceneAsset] = [:]
        var contents: [SceneLayerContent] = []
        let spectrumOver: [SceneLayerContent] = [.circularSpectrum]
        switch inputs.visual {
        case .projectM, .camera, .oscilloscope, .lissajous:
            break   // camera never reaches here (mapped by the caller); projectM, the oscilloscope (VIS-003-R12) and the Lissajous (VIS-004-R12) are no compositor layer
        case .circularSpectrum:
            contents = spectrumOver
        case .linearSpectrum:
            contents = [.linearSpectrum]
        case .photo:
            if let asset = SceneSlideshowBridge.photoAsset(photoID: inputs.photoID, slideshow: inputs.slideshow) {   // MED-006
                assets[photoKey] = asset
                contents = [.photo(asset: photoKey)]
            }
            contents += spectrumOver
        case .video:
            if let id = inputs.videoID {
                assets[videoKey] = SceneVideoLoopBridge.asset(storeID: id, loop: inputs.videoLoop, speedPercent: inputs.videoSpeedPercent)   // MED-003, MED-004
                contents = [.video(asset: videoKey)]
            }
            contents += spectrumOver
        case .text:
            contents = spectrumOver
            if let spec = try? SceneJSON.parse([UInt8](inputs.text.encodedForStorage())) {
                assets[textKey] = SceneAsset(.text(spec: spec))
                contents.append(.text(asset: textKey))
            }
        }

        // Known layers: reuse a carried layer of the same kind (in order) for its instance, values,
        // composite and unknown fields.
        var unmatched = carry.layers.filter { (l: SceneLayer) -> Bool in appLayerKinds.contains(l.kind) }
        var largest = carry.layers.map(\.instance).max() ?? 0
        var layers: [SceneLayer] = []
        for content in contents {
            var layer: SceneLayer
            if let i = unmatched.firstIndex(where: { (l: SceneLayer) -> Bool in l.kind == content.kind }) {
                layer = unmatched.remove(at: i)
                layer.content = content
            } else {
                largest += 1
                layer = SceneLayer(instance: largest, content: content)
            }
            if let composites = inputs.layerComposites {   // CMP-015-R5: the inspector's composite is authoritative
                layer.composite = composites[content.kind] ?? SceneComposite()
            }
            layers.append(layer)
        }

        // Carried layers (kinds the app does not build) at their index; renumber on collision; cap at 8.
        var used = Set(layers.map(\.instance))
        var kept: [String: SceneAsset] = [:]
        var dropped = 0
        for (index, original) in carry.layers.enumerated() where !appLayerKinds.contains(original.kind) {
            guard layers.count < SceneLimits.maximumLayers else { dropped += 1; continue }
            var layer = original
            if used.contains(layer.instance) {
                largest = max(largest, used.max() ?? 0) + 1
                layer.instance = largest
                events.append(.renumberedLayer(original.instance))
            }
            used.insert(layer.instance)
            layers.insert(layer, at: min(index, layers.count))
            if let key = layer.content.assetKey, let asset = carry.assets[key] { kept[key] = asset }
        }
        if dropped > 0 { events.append(.droppedLayers(dropped)) }
        for (key, asset) in carry.assets where assets[key] == nil {
            if case .unknown = asset.kind { kept[key] = asset }
        }
        assets.merge(kept) { (mine: SceneAsset, _: SceneAsset) -> SceneAsset in mine }
        if let logo = inputs.logo {   // MED-010-R10: the overlay's asset (a carried asset under the key yields)
            assets[SceneLogo.assetKey] = .logo(storeID: logo.storeID, placement: logo.placement)
        }

        var parameters = carry.parameters
        for (id, value) in parameterValues(inputs) { parameters[id] = value }

        let bindings = liveBindings ?? carry.bindings
        let sceneBindings = bindings.map { (b: AudioFeatureBinding) -> SceneBinding in
            SceneBinding(b, expression: carry.expressions[b.target])
        } + carry.preserved.bindings
        let connections = carry.modulation.edges.map { (e: ModulationEdge) -> SceneConnection in SceneConnection(e) }
            + carry.preserved.connections
        let document = SceneDocument(id: carry.id, name: carry.name, layers: layers, parameters: parameters,
                                     bindings: sceneBindings,
                                     modulation: SceneModulation(generators: carry.modulation.generators, connections: connections),
                                     assets: assets, effects: effects(inputs.effects, carry: carry.effects),
                                     triggers: carry.triggers, lfos: carry.lfos, snapshots: carry.snapshots,
                                     extra: carry.extra)   // MOD-006, MOD-007, SCN-008: as stored
        return (document, events)
    }

    /// FX-020 (research FX-020-D7): the list to write, or nil to leave the field out.
    static func effects(_ live: SceneEffectSettings?, carry: [SceneEffectEntry]?) -> [SceneEffectEntry]? {
        guard let live, carry != nil || !live.isDefault else { return carry }
        return live.entries(over: carry)
    }

    /// FX-020: a restored list on the settings: order, Color and Trails as the list gives them (each setter keeps its own
    /// range rules; ACC-012 caps still apply when rendering); nil restores the standard order only.
    @MainActor
    static func applyEffects(_ entries: [SceneEffectEntry]?, chain: EffectChainSetting, grade: ColorGradeSetting,
                             trails: MotionFeedbackSetting) {
        guard let entries else {
            chain.order = .standard
            return
        }
        applyEffects(SceneEffectSettings.read(entries).settings, chain: chain, grade: grade, trails: trails)
    }

    @MainActor
    static func applyEffects(_ settings: SceneEffectSettings, chain: EffectChainSetting, grade: ColorGradeSetting,
                             trails: MotionFeedbackSetting) {
        chain.order = settings.order
        if let g = settings.grade {
            if grade.temperature != g.temperature { grade.temperature = g.temperature }
            if grade.lift != g.lift { grade.lift = g.lift }
            if grade.gamma != g.gamma { grade.gamma = g.gamma }
            if grade.gain != g.gain { grade.gain = g.gain }
            if grade.saturation != g.saturation { grade.saturation = g.saturation }
            if grade.hue != g.hue { grade.hue = g.hue }
        }
        if let enabled = settings.gradeEnabled { grade.isEnabled = enabled }
        if let t = settings.trails {
            if trails.halfLifeSeconds != t.halfLifeSeconds { trails.halfLifeSeconds = t.halfLifeSeconds }
            trails.isEnabled = t.isEnabled
        }
    }

    /// The seven app-held values as MOD-001 values.
    static func parameterValues(_ inputs: SceneInputs) -> [ParameterID: ParameterValue] {
        [
            VisualParameterIDs.circularSpectrumBarCount: .enumeration(String(inputs.bars)),
            VisualParameterIDs.linearSpectrumOrientation: .enumeration(inputs.orientation.rawValue),
            VisualParameterIDs.linearSpectrumSpacing: .continuous(inputs.spacing),
            VisualParameterIDs.bloomEnabled: .boolean(inputs.glowEnabled),
            VisualParameterIDs.bloomIntensity: .continuous(inputs.glowIntensity),
            VisualParameterIDs.bloomRadius: .continuous(inputs.glowRadius),
            VisualParameterIDs.bloomThreshold: .continuous(inputs.glowThreshold),
        ]
    }

    // MARK: Restore

    /// What a validated document restores (contract A5): app-held parameter values through a scratch
    /// MOD-001 store (clamping; orphaned and rejected values are not applied), the text of its first
    /// text layer, and the live bindings.
    static func restoredValues(_ document: SceneDocument, live: SceneLiveState, registry: ParameterRegistry) -> SceneRestoredValues {
        let scratch = ParameterStore(registry: registry)
        let present = appParameterIDs.filter { (id: ParameterID) -> Bool in document.parameters[id] != nil }
        let report = scratch.restore(ParameterSnapshot(values: document.parameters.filter { (entry: (key: ParameterID, value: ParameterValue)) -> Bool in
            present.contains(entry.key)
        }))
        var parameters: [ParameterID: ParameterValue] = [:]
        for id in report.applied {
            if let value = scratch.value(for: id) { parameters[id] = value }
        }
        var text: TextOverlaySpec?
        if let key = document.layers.first(where: { (l: SceneLayer) -> Bool in l.kind == "text" })?.content.assetKey,
           case let .text(spec)? = document.assets[key]?.kind,
           case let .spec(decoded) = TextOverlaySpec.decodeStored(Data(spec.canonicalBytes)) {
            text = decoded
        }
        let video = SceneVideoLoopBridge.video(in: document)   // MED-003-R8
        return SceneRestoredValues(parameters: parameters, text: text, bindings: live.bindings,
                                   videoStoreID: video?.storeID, videoLoop: video?.loop, videoSpeedPercent: video?.speedPercent,
                                   slideshow: SceneSlideshowBridge.restore(in: document),   // MED-006
                                   layerComposites: layerComposites(in: document),
                                   logo: document.logo,   // MED-010
                                   effects: document.effects)   // FX-020
    }

    /// CMP-015: the composite of the first layer of each kind the app draws in a compositor, defaults
    /// left out (so a reset removes the key and equal scenes give equal inputs).
    static func layerComposites(in document: SceneDocument) -> [String: SceneComposite] {
        var composites: [String: SceneComposite] = [:]
        var seen: Set<String> = []
        let defaultComposite = SceneComposite()
        for layer in document.layers where LayerInspectorScene.composedKinds.contains(layer.kind) {
            guard seen.insert(layer.kind).inserted else { continue }
            if layer.composite != defaultComposite { composites[layer.kind] = layer.composite }
        }
        return composites
    }

    /// Applies restored parameter values to the settings (each setter keeps its own range rules).
    @MainActor
    static func apply(_ values: SceneRestoredValues, to settings: AppSettings) {
        typealias IDs = VisualParameterIDs
        if let bars = values.parameters[IDs.circularSpectrumBarCount]?.enumCaseID.flatMap({ (s: String) -> Int? in Int(s) }) {
            settings.circularSpectrumBars = bars
        }
        if let raw = values.parameters[IDs.linearSpectrumOrientation]?.enumCaseID,
           let orientation = LinearSpectrumOrientation(rawValue: raw) {
            settings.linearSpectrumOrientation = orientation
        }
        if let spacing = values.parameters[IDs.linearSpectrumSpacing]?.doubleValue { settings.linearSpectrumSpacing = spacing }
        if let enabled = values.parameters[IDs.bloomEnabled]?.boolValue { settings.glowEnabled = enabled }
        if let v = values.parameters[IDs.bloomIntensity]?.doubleValue { settings.glowIntensity = v }
        if let v = values.parameters[IDs.bloomRadius]?.doubleValue { settings.glowRadius = v }
        if let v = values.parameters[IDs.bloomThreshold]?.doubleValue { settings.glowThreshold = v }
    }
}
