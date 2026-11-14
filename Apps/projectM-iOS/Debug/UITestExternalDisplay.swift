// UITestExternalDisplay.swift — a fake external display for ExternalDisplayUITests (OUT-001-T06,
// T10). DEBUG builds only, and only with the launch argument `-uitestExternalDisplay`; Release
// builds contain none of this.
//
// The XCUITest runner cannot connect a display (the simulator's TVOut screen is turned on from the
// host with `simctl io … screenConfig`, quickstart B), so these buttons drive the same
// ExternalDisplayCoordinator calls that ExternalDisplaySceneDelegate makes. The fake display is an
// off-screen 1920 × 1080 window on the app's own window scene with display scale 1, so the moved
// visual really renders at an external size. Never device evidence (OUT-001-T15 is).
// OUT-002-T10: the fake drives the coordinator through `ExternalDisplayEventSink` like the real
// scenes; "ext~" connects and disconnects at once (a bounce inside the settle time), and the hidden
// `externalResources` probe reads what the external side holds.
// OUT-004-T08: the hidden `externalPlacement` probe reads the visual's placement on the fake display
// ("fit=… shape=… par=… frame=W×H bars=…", or "none" while the visual is on the device).
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

    func connect(_ coordinator: any ExternalDisplayEventSink) {
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

    func disconnect(_ coordinator: any ExternalDisplayEventSink) {
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
            Button("ext~") {   // OUT-002: a connection that drops inside the settle time
                UITestExternalDisplay.shared.connect(coordinator)
                UITestExternalDisplay.shared.disconnect(coordinator)
            }
            .accessibilityIdentifier("uitestBounceExternal")
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let probe: String = Self.probe(coordinator)
                Text(probe)
                    .opacity(0.01)
                    .accessibilityIdentifier("externalResources")
                    .accessibilityValue(probe)
                let placement: String = coordinator.externalPlacementSummary ?? "none"
                Text(placement)
                    .opacity(0.01)
                    .accessibilityIdentifier("externalPlacement")
                    .accessibilityValue(placement)
            }
        }
        .font(.caption2)
        .buttonStyle(.bordered)
    }

    /// "slots=<n> pending=<n> holding=<n> cancelled=<n>" (OUT-002-R8).
    static func probe(_ coordinator: ExternalDisplayCoordinator) -> String {
        let counts: ExternalResourceCounts = coordinator.externalResources
        let cancelled: Int = coordinator.settle.cancelled
        return "slots=\(counts.slots) pending=\(counts.pending) holding=\(counts.slotsHoldingVisual) cancelled=\(cancelled)"
    }
}
#endif
