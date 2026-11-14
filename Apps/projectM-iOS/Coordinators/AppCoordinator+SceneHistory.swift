// AppCoordinator+SceneHistory.swift — the scene history's link to the app (SCN-010-R7 to R10;
// research SCN-010-D5, D6).
//
// * A state is applied exactly as Settings and cues set it: the spectra's options, the glow, the Text
//   visual's spec, then the visual (only when it differs from the recorded one, so an undo that keeps
//   the visual leaves Camera running), then the same `visualSettingsChanged()` and
//   `glowSettingsChanged()`. The audio source is never touched; the stored photo and video are not
//   applied (they are not undoable). MED-003: the stored video's loop region is applied when the
//   state's video is the stored one.
// * The keyboard shortcuts (⌘Z, ⇧⌘Z) do not show the controls.
import Foundation
import VisualGenerators

extension AppCoordinator {
    /// Wires the history (called once at the end of init, after the launch restore).
    func connectSceneHistory() {
        sceneHistory.inputs = { [unowned self] () -> SceneInputs in self.sceneInputs }
        sceneHistory.carry = { [weak self] () -> SceneAutosaveCarry in
            self?.sceneAutosave?.carrySnapshot ?? SceneAutosaveCarry(id: SceneHistoryCoordinator.fallbackID, name: SceneAutosaveCarry.defaultName)
        }
        sceneHistory.apply = { [weak self] (inputs: SceneInputs) -> Void in self?.applySceneInputs(inputs) }
        sceneHistory.start()
    }

    /// Sets a history state through the Settings path (R7).
    func applySceneInputs(_ inputs: SceneInputs) {
        if settings.circularSpectrumBars != inputs.bars { settings.circularSpectrumBars = inputs.bars }
        if settings.linearSpectrumOrientation != inputs.orientation { settings.linearSpectrumOrientation = inputs.orientation }
        if settings.linearSpectrumSpacing != inputs.spacing { settings.linearSpectrumSpacing = inputs.spacing }
        if settings.glowEnabled != inputs.glowEnabled { settings.glowEnabled = inputs.glowEnabled }
        if settings.glowIntensity != inputs.glowIntensity { settings.glowIntensity = inputs.glowIntensity }
        if settings.glowRadius != inputs.glowRadius { settings.glowRadius = inputs.glowRadius }
        if settings.glowThreshold != inputs.glowThreshold { settings.glowThreshold = inputs.glowThreshold }
        if texts.spec != inputs.text { texts.spec = inputs.text }
        if let composites = inputs.layerComposites { layers.restore(composites) }   // CMP-015-R6
        if let id = inputs.videoID {
            videos.restoreLoop(storeID: id.uuidString, loop: inputs.videoLoop)   // MED-003-R8
            videos.restoreSpeed(storeID: id.uuidString, speedPercent: inputs.videoSpeedPercent)   // MED-004-R7
        }
        let recorded = SceneAutosaveCapture.recordedVisual(settings.visual, beforeCamera: settings.visualBeforeCamera)
        if recorded != inputs.visual { settings.visual = inputs.visual }
        visualSettingsChanged()
        glowSettingsChanged()
    }

    func undoSceneEdit() { sceneHistory.undo() }
    func redoSceneEdit() { sceneHistory.redo() }
}
