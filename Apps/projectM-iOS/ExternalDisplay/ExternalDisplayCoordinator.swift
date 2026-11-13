// ExternalDisplayCoordinator.swift — OUT-001: puts the one visualization on the device or on a
// connected external display (spec specs/049-out-001-external-display-scene; research OUT-001-D2,
// D3; contracts/external-display.md).
//
// * Scene events from ExternalDisplaySceneDelegate (or the DEBUG fake, UITestExternalDisplay.swift)
//   and the visualizer state from AppCoordinator go into `ExternalDisplayRouting`
//   (PresentationLifecycle), which decides the target.
// * `place()` moves the current visual's own view (the ANGLE renderer's view, or the native spectrum,
//   Camera or Photo host's view) into the target's `VisualSlotView`, inside the call. Every visual
//   lays out its drawable from its view's bounds and trait display scale, so it then renders at the
//   external screen's size and scale with the same renderer or compositor and the same flash
//   limiting. Nothing is drawn twice and no second context or engine exists (OUT-001-R3).
// * SwiftUI owns only the slots, never a visual view (OUT-001-D3).
// * Nothing here touches the audio source, the renderer's pause state or the presentation registry
//   (OUT-001-R4, R10): a move is a view moving between windows.
import OSLog
import PresentationLifecycle
import SwiftUI
import UIKit

@MainActor
@Observable
final class ExternalDisplayCoordinator {
    /// The app's coordinator; the external scene delegates report to it.
    static let shared = ExternalDisplayCoordinator()

    @ObservationIgnored private(set) var routing = ExternalDisplayRouting()
    /// The visualization is drawn on an external display; the device shows the note instead.
    private(set) var showsVisualExternally = false
    /// Times the visual view changed slot (tests; an Int, no allocation).
    @ObservationIgnored private(set) var placements = 0

    @ObservationIgnored private weak var deviceSlot: VisualSlotView?
    @ObservationIgnored private var externalSlots: [String: WeakSlot] = [:]
    @ObservationIgnored private weak var visual: UIView?

    var target: VisualOutputTarget { routing.target }
    /// Connection and routing changes (no user data), for diagnostics and the simulator check.
    @ObservationIgnored private let log = Logger(subsystem: "org.projectmios.ProjectMiOS", category: "ExternalDisplay")

    // MARK: - Device side (VisualSlotHost, AppCoordinator)

    func registerDeviceSlot(_ slot: VisualSlotView) {
        guard deviceSlot !== slot else { return }
        deviceSlot = slot
        place()
    }

    /// Forgets the slot if it is the current one; the visual is not moved (SwiftUI may already have
    /// registered the next slot).
    func unregisterDeviceSlot(_ slot: VisualSlotView) {
        if deviceSlot === slot { deviceSlot = nil }
    }

    /// The current visual's view; nil when there is none.
    func show(_ view: UIView?) {
        guard visual !== view else { return }
        if let old = visual, old !== view, old.superview is VisualSlotView { old.removeFromSuperview() }
        visual = view
        place()
    }

    /// The visualizer screen is shown (true) or left (false).
    func visualizerActive(_ active: Bool) {
        if routing.apply(.visualizing(active)) || !active { place() }
    }

    // MARK: - External scenes

    func externalConnected(id: String, slot: VisualSlotView, geometry: ExternalDisplayGeometry, foreground: Bool) {
        externalSlots[id] = WeakSlot(slot: slot)
        slot.onGeometryChange = { [weak self] (geometry: ExternalDisplayGeometry) in self?.externalResized(id: id, geometry: geometry) }
        routing.apply(.connected(id: id, geometry: geometry, foreground: foreground))
        log.info("external display connected: \(geometry.width, privacy: .public) × \(geometry.height, privacy: .public) @\(geometry.scale, privacy: .public), foreground \(foreground, privacy: .public)")
        place()
    }

    func externalResized(id: String, geometry: ExternalDisplayGeometry) {
        guard routing.apply(.resized(id: id, geometry: geometry)) else { return }
        log.info("external display size: \(geometry.width, privacy: .public) × \(geometry.height, privacy: .public) @\(geometry.scale, privacy: .public)")
        place()
    }

    func externalForeground(id: String, _ foreground: Bool) {
        log.info("external display foreground: \(foreground, privacy: .public)")
        if routing.apply(.foreground(id: id, foreground)) { place() }
    }

    func externalDisconnected(id: String) {
        routing.apply(.disconnected(id: id))
        log.info("external display disconnected")
        if let slot = externalSlots.removeValue(forKey: id)?.slot {
            slot.onGeometryChange = nil
            slot.removeVisuals()
        }
        place()
    }

    // MARK: - Placement

    /// Puts the visual in the target's slot (or in none when that slot is missing) and empties
    /// every other slot, inside this call (OUT-001-R6).
    func place() {
        let targetSlot: VisualSlotView?
        switch routing.target {
        case .device: targetSlot = deviceSlot
        case let .external(id): targetSlot = externalSlots[id]?.slot
        }
        let external: Bool
        if case .external = routing.target { external = true } else { external = false }
        if external != showsVisualExternally {
            showsVisualExternally = external
            log.info("visualization target: \(external ? "external display" : "device", privacy: .public)")
        }
        for slot in externalSlots.values.compactMap({ (w: WeakSlot) -> VisualSlotView? in w.slot }) where slot !== targetSlot {
            slot.removeVisuals()
        }
        if let deviceSlot, deviceSlot !== targetSlot { deviceSlot.removeVisuals() }
        guard let targetSlot, let visual else { return }
        if targetSlot.hold(visual) {
            placements &+= 1
            log.info("visual placed in the \(targetSlot.role == .device ? "device" : "external", privacy: .public) slot (\(targetSlot.bounds.width, privacy: .public) × \(targetSlot.bounds.height, privacy: .public))")
        }
    }

    private struct WeakSlot {
        weak var slot: VisualSlotView?
    }
}

/// OUT-001-D4: scene events that concern the device's visuals. The Camera and Photo hosts observe
/// every scene's connect and disconnect; an external display scene's must not stop or start them.
enum ExternalDisplayScenes {
    nonisolated static func affectsDeviceVisuals(role: UISceneSession.Role) -> Bool {
        role != .windowExternalDisplayNonInteractive
    }

    @MainActor static func affectsDeviceVisuals(_ notification: Notification) -> Bool {
        guard let scene = notification.object as? UIScene else { return true }
        return affectsDeviceVisuals(role: scene.session.role)
    }
}
