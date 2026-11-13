// ExternalDisplaySceneDelegate.swift — OUT-001-D1 on iOS 26: the window of a non-interactive
// external display scene (contracts/external-display.md).
//
// * Info.plist (project.yml `UIApplicationSceneManifest`) names this delegate for
//   `UIWindowSceneSessionRoleExternalDisplayNonInteractive` (iOS 16+) and configures no other role,
//   so SwiftUI keeps the application role. (A `UIApplicationDelegateAdaptor` returning the session's
//   own configuration for the application role left SwiftUI's window empty on the iOS 27.2
//   simulator, so the plist is used instead.) Without it the system mirrors the device screen.
// * On iOS 27 the SwiftUI scene accessory (ExternalDisplayAccessory.swift) is the documented path;
//   if both deliver a window, the routing keeps the first (OUT-001 data model).
// * The external window holds one black `VisualSlotView` and nothing else: no controls, badges,
//   banners or text (OUT-001-R1). Its size and scale reach the coordinator from the slot's layout and
//   display-scale trait changes, so a resolution change re-lays out the visual (OUT-001-R7).
import OSLog
import PresentationLifecycle
import UIKit

final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var id = ""

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Logger(subsystem: "org.projectmios.ProjectMiOS", category: "ExternalDisplay")
            .info("external display scene connecting (role \(session.role.rawValue, privacy: .public))")
        id = session.persistentIdentifier
        let controller = ExternalDisplayViewController()
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = controller
        window.isHidden = false
        self.window = window
        controller.view.layoutIfNeeded()
        ExternalDisplayCoordinator.shared.externalConnected(id: id, slot: controller.slot, geometry: controller.slot.geometry,
                                                           foreground: Self.isForeground(scene.activationState))
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        ExternalDisplayCoordinator.shared.externalForeground(id: id, true)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        ExternalDisplayCoordinator.shared.externalForeground(id: id, false)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ExternalDisplayCoordinator.shared.externalDisconnected(id: id)
        window = nil
    }

    static func isForeground(_ state: UIScene.ActivationState) -> Bool {
        state == .foregroundActive || state == .foregroundInactive
    }
}

/// The external window's root: one black slot filling the screen.
final class ExternalDisplayViewController: UIViewController {
    let slot = VisualSlotView(role: .external)

    override func loadView() {
        view = slot
    }
}
