// AppCoordinator+Guide.swift — UIX-001: what the guided first scene does to the app (UIX-001-R5, R8,
// R9, R10; research UIX-001-D4).
//
// * Play sets exactly what Settings sets (the visual, the spectra's glow or the Text message), commits
//   the scene at once through SCN-002, and starts In-App Playback with the built-in reference track
//   only from the chooser (the chooser row's own path). On the visualizer the running source is kept;
//   VisualizerView's existing onChange hooks switch the visual.
// * Nothing here requests a permission, opens a picker, touches OSC or the camera, or adds show cues.
import Foundation

extension AppCoordinator {
    /// Play (contract G3).
    func finishGuidedFirstScene() {
        let draft = guide.finish()
        Self.apply(draft, settings: settings, texts: texts)
        sceneAutosave?.commitNow()   // SCN-002: committed at once (catches up with the change)
        if screen == .chooser { select(.inAppPlayback) }   // the reference track; no permission
    }

    /// The Settings row: closes Settings, then opens the tutorial from step 1 (UIX-001-R8).
    func openGuidedFirstScene() {
        showSettings = false
        guide.open()
    }

    /// What Play changes, and nothing else (unit-tested).
    static func apply(_ draft: GuidedFirstSceneDraft, settings: AppSettings, texts: TextOverlayCoordinator) {
        settings.visual = draft.visual.choice
        if draft.visual.usesGlow {
            settings.glowEnabled = draft.glow
        } else {
            texts.setMessage(draft.message)
        }
    }
}
