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
// * OUT-010 (spec specs/051-out-010-output-blackout-isolation; research OUT-010-D1 to D5): the output
//   blackout. `OutputBlackout` (PresentationLifecycle) holds the state; every slot's black cover
//   follows its `coverOpacity`. Black out sets the covers inside the call with animations off, so
//   the next composited frame is black; `place()` covers every slot before it moves the visual, so a
//   connect, disconnect or visual change never reveals it. The visual stays in its slot and keeps
//   running. A display link runs only while the restore fade or the restore spacing needs frames.
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

    // OUT-010: output blackout.
    /// The blackout's phase (controls, badge, note).
    private(set) var blackoutPhase: OutputBlackout.Phase = .live
    @ObservationIgnored private(set) var blackout = OutputBlackout()
    /// Reduce flashing (FR-072), set by AppCoordinator; read at each fade frame (OUT-010-R6).
    @ObservationIgnored var reduceFlashing = false
    /// Tests drive `advanceFrame` themselves and turn the display link off.
    @ObservationIgnored var usesDisplayLink = true
    @ObservationIgnored private var frameDriver: BlackoutFrameDriver?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitestStartBlackedOut") {   // quickstart C
            blackout.blackOut()
            blackoutPhase = blackout.phase
        }
        #endif
    }

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

    // MARK: - Output blackout (OUT-010)

    /// The user wants the output black (the control offers Restore).
    var isBlackoutRequested: Bool { blackoutPhase == .blackedOut || blackoutPhase == .restoreWaiting }

    /// `true`: every slot is black before this returns (OUT-010-R2). `false`: the fade starts, or
    /// waits for the restore spacing (OUT-010-R6, R7). Never touches the source or the visual.
    func setBlackout(_ on: Bool) {
        if on { blackout.blackOut() } else { blackout.restore() }
        blackoutChanged()
    }

    func toggleBlackout() {
        setBlackout(!blackout.isBlackoutRequested)
    }

    /// One presented frame (the display link's tick; tests call it with fake frame times).
    func advanceFrame(frameTime: Double) {
        blackout.advance(frameTime: frameTime, reduceFlashing: reduceFlashing)
        blackoutChanged()
    }

    /// The slot holding the visual shows only black (tests, DEBUG probe).
    var isOutputBlack: Bool {
        guard let slot = visual?.superview as? VisualSlotView else { return blackout.isBlack }
        return slot.isOutputBlack
    }

    /// A display link is delivering frames to the blackout (tests).
    var drivesBlackoutFrames: Bool { frameDriver != nil }

    private func blackoutChanged() {
        applyCovers()
        if blackoutPhase != blackout.phase {
            blackoutPhase = blackout.phase
            log.info("output blackout: \(self.blackoutPhase.rawValue, privacy: .public)")
        }
        updateFrameDriver()
    }

    private func applyCovers() {
        let opacity = blackout.coverOpacity
        deviceSlot?.coverOpacity = opacity
        for slot in externalSlots.values.compactMap({ (w: WeakSlot) -> VisualSlotView? in w.slot }) {
            slot.coverOpacity = opacity
        }
    }

    private func updateFrameDriver() {
        if blackout.needsFrames, usesDisplayLink {
            if frameDriver == nil {
                frameDriver = BlackoutFrameDriver { [weak self] (frameTime: Double) in self?.advanceFrame(frameTime: frameTime) }
            }
        } else if let driver = frameDriver {
            driver.stop()
            frameDriver = nil
        }
    }

    // MARK: - Placement

    /// Puts the visual in the target's slot (or in none when that slot is missing) and empties
    /// every other slot, inside this call (OUT-001-R6). OUT-010: every slot is covered first, so
    /// the visual never appears uncovered while the output is blacked out.
    func place() {
        applyCovers()
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

/// OUT-010-D4: a display link that runs only while the blackout needs frames. The link retains a
/// proxy that holds the driver weakly, so a dropped driver ends the link at its next tick.
@MainActor
final class BlackoutFrameDriver {
    private let link: CADisplayLink
    private let proxy: Proxy
    private var last: CFTimeInterval?
    private let onFrame: (Double) -> Void

    init(onFrame: @escaping (Double) -> Void) {
        self.onFrame = onFrame
        let proxy = Proxy()
        self.proxy = proxy
        link = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
        proxy.driver = self
        link.add(to: .main, forMode: .common)
    }

    func stop() {
        link.invalidate()
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let frameTime = last.map { (previous: CFTimeInterval) -> Double in link.timestamp - previous } ?? link.duration
        last = link.timestamp
        onFrame(frameTime)
    }

    @MainActor
    private final class Proxy: NSObject {
        weak var driver: BlackoutFrameDriver?

        @objc func tick(_ link: CADisplayLink) {
            guard let driver else {
                link.invalidate()
                return
            }
            driver.tick(link)
        }
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
