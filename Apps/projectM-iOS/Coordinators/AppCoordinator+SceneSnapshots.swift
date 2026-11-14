// AppCoordinator+SceneSnapshots.swift — SCN-008: the snapshot list's link to the app (SCN-008-R5 to R9;
// research SCN-008-D5, D6).
//
// * The list lives in SCN-002's carry (`SceneAutosaveCoordinator.snapshotEntries` / `replaceSnapshots`).
// * Values are read and written through `ParameterInspectorTargets`, the same `AppSettings` properties the
//   Settings controls bind (UIX-003); `VisualizerView`'s `onChange` then updates the visual as for any
//   Settings edit. Nothing here reaches the photo, video, logo, slideshow, visual choice or preset.
// * One SCN-010 step per recall; announcements on the library lane (ACC-004).
import Foundation
import ParameterGraph
import SceneFormat

extension AppCoordinator {
    func connectSceneSnapshots() {
        sceneSnapshots.connect(settings: settings, autosave: sceneAutosave, history: sceneHistory,
                               announce: { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .library) })
    }
}

extension SceneSnapshotCoordinator {
    /// The app's wiring (also used by SceneSnapshotAcceptanceTests, so the tests exercise this exact path).
    func connect(settings: AppSettings, autosave: SceneAutosaveCoordinator?, history: SceneHistoryCoordinator?,
                 announce: @escaping (String) -> Void) {
        if let registry = autosave?.registry { self.registry = registry }   // the registry the scene was validated with
        load = { [weak autosave] () -> [SceneSnapshotEntry] in autosave?.snapshotEntries ?? [] }
        store = { [weak autosave] (entries: [SceneSnapshotEntry]) -> Void in autosave?.replaceSnapshots(entries) }
        read = { (id: ParameterID) -> ParameterValue? in ParameterInspectorTargets.target(for: id, settings: settings)?.get() }
        write = { (id: ParameterID, value: ParameterValue) -> Bool in
            guard let target = ParameterInspectorTargets.target(for: id, settings: settings) else { return false }
            target.set(value)
            return true
        }
        self.history = history
        self.announce = announce
        sceneLock = settings.sceneLock   // SCN-015
        reload()
    }
}
