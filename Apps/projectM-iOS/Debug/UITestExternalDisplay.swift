// UITestExternalDisplay.swift — a fake external display for ExternalDisplayUITests (OUT-001-T06,
// T10). DEBUG builds only, and only with the launch argument `-uitestExternalDisplay`; Release
// builds contain none of this.
//
// The XCUITest runner cannot connect a display (the simulator's TVOut screen is turned on from the
// host with `simctl io … screenConfig`, quickstart B), so these buttons drive the same
// ExternalDisplayCoordinator calls that ExternalDisplaySceneDelegate makes. The fake display is an
// off-screen 1920 × 1080 window on the app's own window scene with display scale 1, so the moved
// visual really renders at an external size. Never device evidence (OUT-001-T15 is).
#if DEBUG
import PresentationLifecycle
import SwiftUI
import UIKit

@MainActor
final class UITestExternalDisplay {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-uitestExternalDisplay") }
    static let shared = UITestExternalDisplay()
    static let id = "uitest-external-display"

    private var window: UIWindow?
    private(set) var connects = 0

    func connect(_ coordinator: ExternalDisplayCoordinator) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }).first
        else { return }
        let controller = ExternalDisplayViewController()
        controller.slot.traitOverrides.displayScale = 1
        let window = UIWindow(windowScene: scene)
        // Off screen, below the app's window: it takes no touches and covers nothing.
        window.frame = CGRect(x: 100_000, y: 0, width: 1920, height: 1080)
        window.windowLevel = .normal - 1
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        self.window = window
        connects += 1
        coordinator.externalConnected(id: Self.id, slot: controller.slot, geometry: controller.slot.geometry, foreground: true)
    }

    func disconnect(_ coordinator: ExternalDisplayCoordinator) {
        guard window != nil else { return }
        coordinator.externalDisconnected(id: Self.id)
        window?.isHidden = true
        window = nil
    }
}

struct UITestExternalDisplayPanel: View {
    let coordinator: ExternalDisplayCoordinator

    var body: some View {
        HStack(spacing: 2) {
            Button("ext+") { UITestExternalDisplay.shared.connect(coordinator) }
                .accessibilityIdentifier("uitestConnectExternal")
            Button("ext-") { UITestExternalDisplay.shared.disconnect(coordinator) }
                .accessibilityIdentifier("uitestDisconnectExternal")
        }
        .font(.caption2)
        .buttonStyle(.bordered)
    }
}
#endif
