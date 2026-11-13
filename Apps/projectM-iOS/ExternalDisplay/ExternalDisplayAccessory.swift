// ExternalDisplayAccessory.swift — OUT-001-D1 on iOS 27: the external display as a SwiftUI scene
// accessory (`View.sceneAccessory { ExternalNonInteractiveAccessory { … } }`, iOS 27.0 SDK).
//
// iOS 27 added scene accessories: "supplementary content that the system presents on the app's
// behalf when an associated piece of system functionality becomes available, for example when an
// external display is connected" (UISceneAccessory.h). On the iOS 27.2 simulator, the iOS 16 scene
// role configured in Info.plist (ExternalDisplaySceneDelegate.swift) got no scene for a SwiftUI app.
// SpringBoard registered the app's non-interactive presentation and then mirrored the device
// (research OUT-001-D1). So on iOS 27 the app registers the accessory. The Info.plist role stays for
// iOS 26, where accessories do not exist.
//
// The accessory's content is one external `VisualSlotView`. It joins the coordinator when it enters
// a window on the external display and leaves when that window goes away. The scene's background and
// foreground notifications for its own window scene set its foreground state.
//
// Compiled only with the iOS 27 SDK (Swift 6.4, Xcode 27): CI's Xcode 26 / iOS SDK 26.5 job has no
// accessory types, and the app then uses only the Info.plist role. At run time it is guarded with
// `#available(iOS 27.0, *)`.
import PresentationLifecycle
import SwiftUI
import UIKit

#if compiler(>=6.4)
extension View {
    /// Adds the external display accessory on iOS 27 and later; on iOS 26 the view is unchanged.
    @ViewBuilder
    func externalDisplayAccessory(_ external: ExternalDisplayCoordinator) -> some View {
        if #available(iOS 27.0, *) {
            sceneAccessory {
                ExternalNonInteractiveAccessory {
                    ExternalAccessorySlot(external: external)
                        .ignoresSafeArea()
                }
            }
        } else {
            self
        }
    }
}
#else
extension View {
    func externalDisplayAccessory(_ external: ExternalDisplayCoordinator) -> some View { self }
}
#endif

/// The accessory's content: an external slot that reports its window's connection, size and
/// foreground state to the coordinator.
struct ExternalAccessorySlot: UIViewRepresentable {
    let external: ExternalDisplayCoordinator

    @MainActor
    final class Link {
        let external: ExternalDisplayCoordinator
        let id = "scene-accessory-\(UUID().uuidString)"
        private var connected = false
        private var observers: [NSObjectProtocol] = []

        init(external: ExternalDisplayCoordinator) { self.external = external }

        func windowChanged(_ slot: VisualSlotView) {
            if let scene = slot.window?.windowScene {
                guard !connected else { return }
                connected = true
                external.externalConnected(id: id, slot: slot, geometry: slot.geometry,
                                           foreground: ExternalDisplaySceneDelegate.isForeground(scene.activationState))
                observe(scene)
            } else {
                leave()
            }
        }

        func leave() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard connected else { return }
            connected = false
            external.externalDisconnected(id: id)
        }

        private func observe(_ scene: UIWindowScene) {
            let center = NotificationCenter.default
            let states: [(Notification.Name, Bool)] = [(UIScene.willEnterForegroundNotification, true),
                                                       (UIScene.didEnterBackgroundNotification, false)]
            for (name, foreground) in states {
                observers.append(center.addObserver(forName: name, object: scene, queue: .main) { [weak self] (_: Notification) in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.external.externalForeground(id: self.id, foreground)
                    }
                })
            }
        }
    }

    func makeCoordinator() -> Link { Link(external: external) }

    func makeUIView(context: Context) -> VisualSlotView {
        let slot = VisualSlotView(role: .external)
        let link = context.coordinator
        slot.onWindowChange = { [weak link] (slot: VisualSlotView) in link?.windowChanged(slot) }
        return slot
    }

    func updateUIView(_ slot: VisualSlotView, context: Context) {}

    static func dismantleUIView(_ slot: VisualSlotView, coordinator: Link) {
        slot.onWindowChange = nil
        coordinator.leave()
    }
}
