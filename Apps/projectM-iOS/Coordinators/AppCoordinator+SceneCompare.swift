// AppCoordinator+SceneCompare.swift — SCN-009: the A/B compare's link to the app (specs/222-scn-009-scene-ab-compare;
// R2, R8; research SCN-009-D5, D8).
//
// * The compare model reads and writes through the snapshot coordinator's Settings targets, restores through the
//   history's apply (`applySceneInputs`), and suspends the app's autosave and history.
// * Starting closes Settings so the output is visible; announcements go to the library lane (ACC-004).
import Foundation

extension AppCoordinator {
    func connectSceneCompare() {
        sceneCompare.connect(snapshots: sceneSnapshots, autosave: sceneAutosave, history: sceneHistory, lock: sceneLock,
                             inputs: { [weak self] () -> SceneInputs? in self?.sceneInputs },
                             announce: { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .library) })
        sceneCompare.onStarted = { [weak self] () -> Void in self?.showSettings = false }
    }
}
