// AppCoordinator+ScenePacks.swift — SCN-014: creates Scene Folders' scene pack coordinator over the app's
// photo, video and show stores (specs/187-scn-014-dependency-pack).
import Foundation

extension AppCoordinator {
    func connectScenePacks(defaults: UserDefaults) {
        show.scenePacks = ScenePackCoordinator.makeDefault(show: show, defaults: defaults)
        #if DEBUG
        UITestScenePackFixture.seedIfRequested(self)   // SCN-014: ScenePackUITests
        #endif
    }
}
