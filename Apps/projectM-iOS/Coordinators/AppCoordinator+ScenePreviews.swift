// AppCoordinator+ScenePreviews.swift — roadmap SCN-006: creates and wires the scene previews (specs/
// 153-scn-006-scene-preview; plan "App"). The capture is REC-001's frame grab of the shown visual
// (DEBUG `-uitestScenePreviewFixture`: a fixed picture); a capture needs the output live, not paused, a
// visual shown and no Save Frame in progress. ShowCoordinator reports scene file writes and removals;
// the launch reconciliation keeps only pictures that match the stored show.
import Foundation
import PresetLibrary

extension AppCoordinator {
    func makeScenePreviews() -> ScenePreviewModel {
        var capture: ScenePreviewModel.Capture = ScenePreviewCapture.live { [weak self] () -> (any FrameCaptureSource)? in
            self?.activeFrameCaptureSource
        }
        #if DEBUG
        if ScenePreviewCapture.fixtureEnabled { capture = ScenePreviewCapture.fixture() }
        #endif
        let show: ShowCoordinator = show
        return ScenePreviewModel(store: ScenePreviewStore(directory: ScenePreviewModel.defaultDirectory()), capture: capture,
                                 sceneFile: { [weak show] (id: String) -> URL? in show?.sceneFileURL(id) },
                                 context: { [weak self] () -> ScenePreviewContext in
                                     self?.scenePreviewContext ?? ScenePreviewContext(appliedSceneID: nil, look: nil, canCapture: false)
                                 })
    }

    /// What a pending capture must still match (SCN-006-R3).
    var scenePreviewContext: ScenePreviewContext {
        let live: Bool = externalDisplay.blackoutPhase == .live && !userPaused
        let canCapture: Bool = live && activeFrameCaptureSource != nil && !frameCapture.isCapturing
        return ScenePreviewContext(appliedSceneID: show.appliedSceneID, look: showLook, canCapture: canCapture)
    }

    /// Called once from `connectShow()`.
    func connectScenePreviews() {
        show.previews = scenePreviews
        show.sceneFilesChanged = { [weak self] (ids: Set<String>) in self?.scenePreviews.scenesChanged(ids) }
        scenePreviews.reconcile(sceneIDs: show.list.sceneIDs)
    }
}
