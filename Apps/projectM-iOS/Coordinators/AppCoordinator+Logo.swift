// AppCoordinator+Logo.swift — the MED-010 logo's links to the app (MED-010-R5, R10 to R12).
//
// * Announcements go through the shared announcer (kind `library`), like the slideshow's.
// * The logo layer is attached to each compositor visual when it is made (prepare functions); scenes carry
//   the logo through `SceneInputs.logo` and `SceneRestoredValues.logo`.
import Foundation
import ImageLayer
import SceneFormat

extension AppCoordinator {
    /// Wires the logo (called once in init).
    func connectLogo() {
        logo.announce = { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .library) }
    }
}

extension LogoCoordinator {
    /// The current logo as a scene records it (nil: no logo).
    var sceneLogo: SceneLogo? {
        sceneValue.map { (value: (storeID: String, placement: LogoPlacement)) -> SceneLogo in
            SceneLogo(storeID: value.storeID, placement: value.placement)
        }
    }
}
