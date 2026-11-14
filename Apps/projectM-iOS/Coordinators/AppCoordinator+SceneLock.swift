// AppCoordinator+SceneLock.swift — SCN-015: the scene lock's link to the app (specs/197-scn-015-scene-lock; R3, R8;
// research SCN-015-D1, D5).
//
// * The lock lives in `AppSettings` (so the Settings targets, macros and snapshots see it); here the show and the
//   undo history get the same lock, and its announcements go to the announcer's library lane (ACC-004).
// * Nothing here touches navigation: cue steps, blackout, tempo, presets and MIDI/OSC values never consult the lock.
import Foundation

extension AppCoordinator {
    var sceneLock: SceneLock { settings.sceneLock }

    func connectSceneLock() {
        show.sceneLock = sceneLock
        sceneHistory.sceneLock = sceneLock
        sceneLock.announce = { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .library) }
    }
}
