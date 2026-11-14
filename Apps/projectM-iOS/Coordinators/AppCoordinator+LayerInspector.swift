// AppCoordinator+LayerInspector.swift — the layer inspector's link to the app (CMP-015-R1, R4, R5, R8;
// research CMP-015-D1 to D3).
//
// * The inspector's scene is the document the autosave would save now (the scene inputs over the
//   carry), so its rows are exactly what is saved.
// * Composites and solo/mute are applied to the shown compositor visual (Photo, Video, Text) when they
//   change and when a host is made. Camera is session only and keeps its default stack.
import Compositor
import Foundation
import SceneFormat

extension AppCoordinator {
    /// Wires the inspector (once, in init, before the scene history starts).
    func connectLayerInspector() {
        layers.onCompositesChange = { [weak self] () -> Void in self?.layerCompositesChanged() }
        layers.onSoloMuteChange = { [weak self] () -> Void in self?.layerSoloMuteChanged() }
        layers.onEditEnded = { [weak self] () -> Void in self?.sceneHistory.endCoalescing() }
        let announcer: AccessibilityAnnouncer = statusEvents.announcer
        layers.announce = { (text: String) -> Void in announcer.announce(text, kind: .layer) }
        layers.visualShown(settings.visual)
    }

    /// The compositor visuals that draw scene layers.
    private var sceneCompositors: [Compositor] {
        [photoVisual?.compositor, videoVisual?.compositor, textVisual?.compositor].compactMap { (c: Compositor?) -> Compositor? in c }
    }

    func layerCompositesChanged() {
        for compositor in sceneCompositors { compositor.applyLayerComposites(layers.composites) }
    }

    func layerSoloMuteChanged() {
        for compositor in sceneCompositors { compositor.applySoloMute(soloed: layers.soloed, muted: layers.muted) }
    }

    /// A new host's stack gets the scene's composites and the current solo/mute.
    func applyLayerState(to compositor: Compositor) {
        compositor.applyLayerComposites(layers.composites)
        compositor.applySoloMute(soloed: layers.soloed, muted: layers.muted)
    }

    /// The current scene as the autosave would save it.
    var layerInspectorDocument: SceneDocument {
        let carry: SceneAutosaveCarry = sceneAutosave?.carrySnapshot
            ?? SceneAutosaveCarry(id: SceneHistoryCoordinator.fallbackID, name: SceneAutosaveCarry.defaultName)
        return SceneAutosaveCapture.document(sceneInputs, carry: carry, liveBindings: nil).document
    }

    /// Top first (contract L1).
    var layerInspectorRows: [LayerInspectorRow] {
        LayerInspectorScene.rows(document: layerInspectorDocument, visual: sceneInputs.visual)
    }

    var layerInspectorGroups: [LayerInspectorGroupRow] { LayerInspectorScene.groups(document: layerInspectorDocument) }
}
