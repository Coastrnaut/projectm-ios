// SceneHistoryCoordinator.swift — undo and redo of scene edits (SCN-010-R1 to R10;
// specs/077-scn-010-scene-undo-redo, contracts/scene-history.md H2; research SCN-010-D2 to D7).
//
// * Observes the app's `SceneInputs` (the same values SCN-002 autosaves) and records each change in a
//   `SceneHistory` (SceneFormat). A state's bytes are the canonical scene document captured over a
//   carry snapshot taken when the history (re)starts, so they are a pure function of the inputs and
//   cover the ordered layer stack and every app-held parameter.
// * Undoable: the visual, bars, orientation, spacing, glow and the Text visual's spec. Not undoable:
//   everything outside `SceneInputs` (audio source, Reduce flashing, overlay, OSC, blackout, camera).
//   A photo or video replacement, a cue, launch restore and Reopen restart the history (R9).
// * Sliders and typing coalesce by key until a boundary (another control, undo/redo, the slider drag
//   ending, Settings closing). No clock.
// * Undo/redo hand the state to `apply` (AppCoordinator: the Settings/cue path). The change is then
//   observed like any other: its bytes equal the history's current state, so nothing is recorded, and
//   SCN-002 commits it under its own rules. The history is in memory only.
import Compositor
import Foundation
import Observation
import SceneFormat
import TextLayer
import VisualGenerators

@MainActor
@Observable
final class SceneHistoryCoordinator {
    private(set) var history: SceneHistory<SceneInputs>?

    var canUndo: Bool { history?.canUndo ?? false }
    var canRedo: Bool { history?.canRedo ?? false }
    var undoLabel: String? { history?.undoLabel }
    var redoLabel: String? { history?.redoLabel }
    /// "Undo Bars 16" (FR-070), "Undo" when there is nothing to undo.
    var undoAccessibilityLabel: String { undoLabel.map { (label: String) -> String in "Undo \(label)" } ?? "Undo" }
    var redoAccessibilityLabel: String { redoLabel.map { (label: String) -> String in "Redo \(label)" } ?? "Redo" }

    @ObservationIgnored let limits: SceneHistoryLimits
    /// The app's current inputs (main actor).
    @ObservationIgnored var inputs: () -> SceneInputs = { fatalError("SceneHistoryCoordinator.inputs not set") }
    /// The content the scene carries but the app does not edit (SCN-002's carry); read at each (re)start.
    @ObservationIgnored var carry: () -> SceneAutosaveCarry = { () -> SceneAutosaveCarry in SceneAutosaveCarry(id: SceneHistoryCoordinator.fallbackID, name: SceneAutosaveCarry.defaultName) }
    /// Sets a state through the Settings path.
    @ObservationIgnored var apply: (SceneInputs) -> Void = { (_: SceneInputs) -> Void in }
    @ObservationIgnored private var carrySnapshot = SceneAutosaveCarry(id: SceneHistoryCoordinator.fallbackID, name: SceneAutosaveCarry.defaultName)
    @ObservationIgnored private var observes = false

    static let fallbackID = "00000000-0000-4000-8000-000000000010"

    init(limits: SceneHistoryLimits = .standard) {
        self.limits = limits
    }

    /// Starts the history from the current scene (after the launch restore) and, unless a test drives
    /// `capture()` itself, observes the inputs.
    func start(observing: Bool = true) {
        begin()
        guard observing, !observes else { return }
        observes = true
        track()
    }

    /// A non-edit changed the scene (cue, Reopen, photo or video replaced): start again from it.
    func restart() {
        guard history != nil else { return }   // not started yet: `start` reads the scene
        begin()
    }

    private func begin() {
        carrySnapshot = carry()
        history = SceneHistory(current: state(inputs()), limits: limits)
    }

    private func state(_ inputs: SceneInputs) -> SceneHistoryState<SceneInputs> {
        let document = SceneAutosaveCapture.document(inputs, carry: carrySnapshot, liveBindings: nil).document
        return SceneHistoryState(bytes: document.encoded(), value: inputs)
    }

    private func track() {
        _ = withObservationTracking { inputs() } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.inputsChanged() }
        }
    }

    private func inputsChanged() {
        track()
        capture()
    }

    /// Records the current inputs (the observation callback, or a catch-up before a boundary).
    func capture() {
        guard var history else { return }
        let now = inputs()
        let previous = history.current.value
        if now.photoID != previous.photoID || now.videoID != previous.videoID {
            restart()   // R9: the stored media is not undoable
            return
        }
        let edit = SceneHistoryEdit.describe(from: previous, to: now)
        history.record(state(now), label: edit.label, coalescingKey: edit.key)
        self.history = history
    }

    /// A boundary: a slider drag ended or Settings closed.
    func endCoalescing() {
        capture()
        history?.endCoalescing()
    }

    func undo() {
        capture()
        guard let state = history?.undo() else { return }
        apply(state.value)
    }

    func redo() {
        capture()
        guard let state = history?.redo() else { return }
        apply(state.value)
    }
}

/// The name and coalescing key of an edit (research SCN-010-D3, D7).
@MainActor
enum SceneHistoryEdit {
    static func describe(from old: SceneInputs, to new: SceneInputs) -> (label: String, key: String?) {
        if let macro = MacroHistoryEdit.describe(from: old.macros, to: new.macros) { return macro }   // MOD-010: wins over its targets
        var changes: [(label: String, key: String?)] = []
        if old.visual != new.visual { changes.append(("Visual \(new.visual.title)", nil)) }
        if old.bars != new.bars { changes.append(("Bars \(new.bars)", nil)) }
        if old.orientation != new.orientation { changes.append(("Orientation \(new.orientation.title)", nil)) }
        if old.spacing != new.spacing {
            let title = AppSettings.linearSpectrumSpacingChoices.first { (c: (title: String, value: Double)) -> Bool in c.value == new.spacing }?.title
            changes.append(("Spacing \(title ?? percent(new.spacing))", nil))
        }
        if old.glowEnabled != new.glowEnabled { changes.append((new.glowEnabled ? "Glow On" : "Glow Off", nil)) }
        if old.glowIntensity != new.glowIntensity { changes.append(("Glow Intensity \(percent(new.glowIntensity))", "glow.intensity")) }
        if old.glowRadius != new.glowRadius { changes.append(("Glow Radius \(percent(new.glowRadius, decimals: 1))", "glow.radius")) }
        if old.glowThreshold != new.glowThreshold { changes.append(("Glow Threshold \(percent(new.glowThreshold))", "glow.threshold")) }
        if old.text != new.text { changes.append(text(from: old.text, to: new.text)) }
        if old.layerComposites != new.layerComposites {   // CMP-015-R6
            changes.append(LayerHistoryEdit.describe(from: old.layerComposites ?? [:], to: new.layerComposites ?? [:]))
        }
        return changes.count == 1 ? changes[0] : ("Scene", nil)
    }

    /// One text control changed: its own name and key; several at once (Reset Text): "Text".
    private static func text(from old: TextOverlaySpec, to new: TextOverlaySpec) -> (label: String, key: String?) {
        var message = old
        _ = message.setMessage(new.message)
        if message == new { return ("Text Message", "text.message") }
        var size = old
        size.size = new.size
        if size == new { return ("Text Size \(percent(new.size))", "text.size") }
        var outline = old
        outline.outlineWidth = new.outlineWidth
        if outline == new { return ("Text Outline \(percent(new.outlineWidth))", "text.outline") }
        return ("Text", nil)
    }

    /// "50%", or "2.0%" with one decimal (as Settings shows it).
    static func percent(_ value: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", value * 100)
    }
}

/// CMP-015 (research CMP-015-D4): a layer edit's name and coalescing key. One parameter of one layer: its
/// own name ("Photo Opacity 40%") and, for a slider, the key `layer.<kind>.<parameter>`; anything else
/// ("Reset Photo", several layers) is its own step.
@MainActor
enum LayerHistoryEdit {
    static func describe(from old: [String: SceneComposite], to new: [String: SceneComposite]) -> (label: String, key: String?) {
        let kinds: Set<String> = Set(old.keys).union(new.keys)
        let changed: [String] = kinds.filter { (k: String) -> Bool in old[k] != new[k] }.sorted()
        guard changed.count == 1, let kind = changed.first else { return ("Layers", nil) }
        let before: SceneComposite = old[kind] ?? SceneComposite()
        let after: SceneComposite = new[kind] ?? SceneComposite()
        let title: String = layerTitle(kind)
        let parameters: [LayerInspectorParameter] = changedParameters(from: before, to: after)
        guard parameters.count == 1, let parameter = parameters.first else {
            return (after == SceneComposite() ? "Reset \(title)" : "\(title) Layer", nil)
        }
        let label: String = "\(title) \(parameter.title) \(LayerCompositeEdit.text(parameter, of: after))"
        let key: String? = LayerInspectorParameter.sliders.contains(parameter) ? "layer.\(kind).\(parameter.rawValue)" : nil
        return (label, key)
    }

    static func layerTitle(_ kind: String) -> String {
        switch kind {
        case "photo": "Photo"
        case "video": "Video"
        case "text": "Text"
        case "spectrum.circular": "Circular Spectrum"
        default: kind
        }
    }

    static func changedParameters(from old: SceneComposite, to new: SceneComposite) -> [LayerInspectorParameter] {
        var result: [LayerInspectorParameter] = []
        for parameter in LayerInspectorParameter.sliders
        where LayerCompositeEdit.value(parameter, of: old) != LayerCompositeEdit.value(parameter, of: new) {
            result.append(parameter)
        }
        if old.blendMode != new.blendMode { result.append(.blendMode) }
        let anchorMoved: Bool = result.contains(.fitAnchorX) || result.contains(.fitAnchorY)
        let fitAppeared: Bool = old.fit == nil && new.fit?.mode == LayerFitMode.fill.rawValue
        if old.fit?.mode != new.fit?.mode && !(anchorMoved && fitAppeared) { result.append(.fitMode) }   // an anchor drag sets the default fit
        if old.mask?.shape != new.mask?.shape { result.append(.maskShape) }
        let wasInverted: Bool = LayerCompositeEdit.knownMask(old)?.inverted ?? false
        let isInverted: Bool = LayerCompositeEdit.knownMask(new)?.inverted ?? false
        if wasInverted != isInverted { result.append(.maskInverted) }
        if result.isEmpty && old != new { result.append(.maskShape) }   // e.g. an unknown mask replaced
        return result
    }
}

/// MOD-010 (research MOD-010-D4): one macro's value changed: "Macro <name> <percent>", key `macro.<index>`, whatever
/// targets changed with it (one drag or step = one undo step). Nil when the macro list did not change that way.
@MainActor
enum MacroHistoryEdit {
    static func describe(from old: [SceneMacroEntry]?, to new: [SceneMacroEntry]?) -> (label: String, key: String?)? {
        guard old != new else { return nil }
        let before: [SceneMacroEntry] = old ?? []
        let after: [SceneMacroEntry] = new ?? []
        guard before.count == after.count else { return ("Macros", nil) }
        var changed: [Int] = []
        for index in after.indices where before[index] != after[index] { changed.append(index) }
        guard changed.count == 1, let index = changed.first else { return ("Macros", nil) }
        let entry: SceneMacroEntry = after[index]
        let name: String = entry.fields["name"]?.stringValue ?? "\(index + 1)"
        let value: Double = entry.fields["value"]?.numberValue?.doubleValue ?? 0
        return ("Macro \(name) \(SceneHistoryEdit.percent(value))", "macro.\(index)")
    }
}
