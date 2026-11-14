// LayerInspectorCoordinator.swift — the layer inspector's state (CMP-015-R4 to R6, R8; research
// CMP-015-D2 to D4; data-model "LayerInspectorCoordinator"; contracts/layer-inspector.md L3, L4).
//
// * `composites`: the saved composite of each drawn layer kind — a scene input (`SceneInputs.layerComposites`),
//   so SCN-002 saves it and SCN-010 records and undoes it. Default composites are never stored.
//   `restore` sets it from a document or a history state; it is not an edit of its own (the history sees
//   the inputs equal its state and records nothing).
// * `soloed` / `muted`: CMP-012's transient overlay, by kind, for the shown visual only. Never part of
//   the scene inputs, the document or the history; cleared when the recorded visual changes.
// * The app wires the callbacks: the shown host applies changes (AppCoordinator+LayerInspector.swift),
//   a slider release ends the history's coalescing, solo and mute are announced through the shared
//   announcer.
import Foundation
import Observation
import SceneFormat

@MainActor
@Observable
final class LayerInspectorCoordinator {
    private(set) var composites: [String: SceneComposite] = [:]
    private(set) var soloed: Set<String> = []
    private(set) var muted: Set<String> = []

    @ObservationIgnored var onCompositesChange: () -> Void = {}
    @ObservationIgnored var onSoloMuteChange: () -> Void = {}
    /// A slider drag ended (SCN-010-R4: the history's coalescing boundary).
    @ObservationIgnored var onEditEnded: () -> Void = {}
    @ObservationIgnored var announce: (String) -> Void = { (_: String) -> Void in }
    @ObservationIgnored private var soloMuteVisual: VisualChoice?

    func composite(for kind: String) -> SceneComposite { composites[kind] ?? SceneComposite() }

    /// Sets a kind's composite (an edit).
    func set(_ composite: SceneComposite, for kind: String) {
        var next = composites
        next[kind] = composite
        let normalized = LayerCompositeMapping.normalized(next)
        guard normalized != composites else { return }
        composites = normalized
        onCompositesChange()
    }

    func setValue(_ parameter: LayerInspectorParameter, _ value: Double, kind: String) {
        set(LayerCompositeEdit.setting(parameter, to: value, on: composite(for: kind)), for: kind)
    }

    func setBlend(_ name: String, kind: String) { set(LayerCompositeEdit.settingBlend(name, on: composite(for: kind)), for: kind) }
    func setFit(_ name: String?, kind: String) { set(LayerCompositeEdit.settingFit(name, on: composite(for: kind)), for: kind) }
    func setMask(_ name: String?, kind: String) { set(LayerCompositeEdit.settingMask(name, on: composite(for: kind)), for: kind) }

    // CMP-008: the gradient mask (kind; stops by index in position order).
    func setGradientKind(_ name: String?, kind: String) { set(LayerGradientEdit.settingKind(name, on: composite(for: kind)), for: kind) }
    func setGradientStop(_ index: Int, _ field: LayerGradientField, _ value: Double, kind: String) {
        set(LayerGradientEdit.settingStop(index, field, to: value, on: composite(for: kind)), for: kind)
    }
    func addGradientStop(kind: String) { set(LayerGradientEdit.addingStop(on: composite(for: kind)), for: kind) }
    func removeGradientStop(_ index: Int, kind: String) { set(LayerGradientEdit.removingStop(index, on: composite(for: kind)), for: kind) }

    /// Reset Layer: one edit back to the default composite.
    func reset(kind: String) { set(SceneComposite(), for: kind) }

    /// A slider drag ended.
    func endEdit() { onEditEnded() }

    /// A document's or a history state's composites (not an edit).
    func restore(_ restored: [String: SceneComposite]) {
        let normalized = LayerCompositeMapping.normalized(restored)
        guard normalized != composites else { return }
        composites = normalized
        onCompositesChange()
    }

    // MARK: - Solo and mute (CMP-012; never saved, never undoable)

    func isSoloed(_ kind: String) -> Bool { soloed.contains(kind) }
    func isMuted(_ kind: String) -> Bool { muted.contains(kind) }

    func toggleSolo(kind: String, title: String) {
        let on = !soloed.contains(kind)
        if on { soloed.insert(kind) } else { soloed.remove(kind) }
        onSoloMuteChange()
        announce(on ? "\(title) soloed" : "\(title) not soloed")
    }

    func toggleMute(kind: String, title: String) {
        let on = !muted.contains(kind)
        if on { muted.insert(kind) } else { muted.remove(kind) }
        onSoloMuteChange()
        announce(on ? "\(title) muted" : "\(title) unmuted")
    }

    func clearSoloMute() {
        guard !soloed.isEmpty || !muted.isEmpty else { return }
        soloed = []
        muted = []
        onSoloMuteChange()
    }

    /// The recorded visual is `visual` now: a different one clears solo and mute (CMP-015-R8).
    func visualShown(_ visual: VisualChoice) {
        defer { soloMuteVisual = visual }
        guard let previous = soloMuteVisual, previous != visual else { return }
        clearSoloMute()
    }
}
