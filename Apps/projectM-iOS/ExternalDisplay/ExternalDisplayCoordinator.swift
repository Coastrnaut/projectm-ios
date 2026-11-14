// ExternalDisplayCoordinator.swift — OUT-001: puts the one visualization on the device or on a
// connected external display (spec specs/049-out-001-external-display-scene; research OUT-001-D2,
// D3; contracts/external-display.md).
//
// * Scene events from ExternalDisplaySceneDelegate (or the DEBUG fake, UITestExternalDisplay.swift)
//   and the visualizer state from AppCoordinator go into `ExternalDisplayRouting`
//   (PresentationLifecycle), which decides the target.
// * `place()` moves the current visual's own view (the ANGLE renderer's view, or the native spectrum,
//   Camera, Photo or Video host's view) into the target's `VisualSlotView`, inside the call. Every visual
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
// * OUT-002 (spec specs/161-out-002-display-hotplug; research OUT-002-D1 to D5): hot-plug. Events
//   arrive through `ExternalDisplayEventSink` (scene delegate, iOS 27 accessory, DEBUG fake, tests).
//   A connect settles for 0.3 s (`HotPlugSettle`) before the visual moves; a disconnect cancels a
//   pending connect (nothing moves, nothing is announced) or is applied inside the call. While a
//   recording runs (`holdsPlacement`), the visual stays where it is unless its slot is gone, so the
//   recording's size never changes. The internal render session is never touched: only its view
//   changes window. `externalResources` counts what the external side holds (0 after disconnect).
// * OUT-004 (spec specs/172-out-004-aspect-correction, contract C3): `correction` (Fit, Fill, Stretch;
//   Display or Device shape; pixel aspect) and the device slot's shape are pushed to every external
//   slot, which lays the visual out by them. While a recording holds the placement nothing is pushed
//   (the recording's picture size must not change); the latest values follow when the hold ends.
import OSLog
import PresentationLifecycle
import SwiftUI
import UIKit

/// OUT-002-R7 (contract C1): the one seam through which external display connections arrive.
@MainActor
protocol ExternalDisplayEventSink: AnyObject {
    func externalConnected(id: String, slot: VisualSlotView, geometry: ExternalDisplayGeometry, foreground: Bool)
    func externalResized(id: String, geometry: ExternalDisplayGeometry)
    func externalForeground(id: String, _ foreground: Bool)
    func externalDisconnected(id: String)
}

/// OUT-002-R6: a settled connection or the disconnect of a settled display (announced as X27, X28).
enum ExternalDisplayConnectionChange: Equatable, Sendable {
    /// `heldByRecording`: a running recording keeps the visualization where it is for now.
    case connected(heldByRecording: Bool)
    case disconnected
}

/// OUT-002-R8: what the external side holds (tests, DEBUG probe).
struct ExternalResourceCounts: Equatable, Sendable {
    var slots = 0
    var pending = 0
    var slotsHoldingVisual = 0
    static let zero = ExternalResourceCounts()
}

@MainActor
@Observable
final class ExternalDisplayCoordinator: ExternalDisplayEventSink {
    /// The app's coordinator; the external scene delegates report to it. Connects settle (OUT-002-R3).
    static let shared = ExternalDisplayCoordinator(connectSettle: HotPlugSettle.defaultInterval)

    /// Runs `body` on the main actor after `seconds` (the settle timer; tests inject a manual one).
    typealias SettleScheduler = (_ seconds: Double, _ body: @escaping @MainActor () -> Void) -> Void

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

    // OUT-002: hot-plug.
    @ObservationIgnored private(set) var settle: HotPlugSettle
    @ObservationIgnored private let scheduleSettle: SettleScheduler
    /// The target a running recording holds the visual on (OUT-002-R4); nil without a hold.
    @ObservationIgnored private var heldTarget: VisualOutputTarget?
    /// Settled connections and disconnections (OUT-002-R6); AppCoordinator posts them as status events.
    @ObservationIgnored var onConnectionChange: ((ExternalDisplayConnectionChange) -> Void)?

    // OUT-004: output correction.
    /// The user's choice (ExternalOutputSetting sets it); applied to external slots unless held.
    @ObservationIgnored var correction: ExternalOutputCorrection = .default {
        didSet { if correction != oldValue { pushCorrection() } }
    }
    /// The device visualizer's shape (width ÷ height), from the device slot's size; nil until known.
    @ObservationIgnored private(set) var deviceAspect: Double?

    /// `connectSettle` 0 (the default): a connect moves the visual inside the call (OUT-001-R6 tests).
    init(connectSettle: Double = 0, scheduleSettle: SettleScheduler? = nil) {
        settle = HotPlugSettle(interval: connectSettle)
        self.scheduleSettle = scheduleSettle ?? { (seconds: Double, body: @escaping @MainActor () -> Void) -> Void in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                body()
            }
        }
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
        slot.onSizeChange = { [weak self] (size: CGSize) -> Void in self?.deviceSizeChanged(size) }
        if slot.bounds.width > 0, slot.bounds.height > 0 { deviceSizeChanged(slot.bounds.size) }
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

    /// OUT-002-R3, R5: the slot is kept (weakly) and covered at once with the current blackout, and
    /// stays empty until the connection settles.
    func externalConnected(id: String, slot: VisualSlotView, geometry: ExternalDisplayGeometry, foreground: Bool) {
        externalSlots[id] = WeakSlot(slot: slot)
        slot.correction = correction   // OUT-004: a new slot holds no visual yet, so even a hold allows it
        slot.deviceAspect = deviceAspect
        slot.onGeometryChange = { [weak self] (geometry: ExternalDisplayGeometry) in self?.externalResized(id: id, geometry: geometry) }
        log.info("external display connected: \(geometry.width, privacy: .public) × \(geometry.height, privacy: .public) @\(geometry.scale, privacy: .public), foreground \(foreground, privacy: .public)")
        if routing.displays.contains(where: { (d: ExternalDisplay) -> Bool in d.id == id }) || settle.isImmediate {
            settleConnection(id: id, geometry: geometry, foreground: foreground)   // a known display, or no settle time
            return
        }
        let token = settle.connect(id: id, geometry: geometry, foreground: foreground)
        place()   // covers the new slot (OUT-010) and keeps it empty
        scheduleSettle(settle.interval) { [weak self] () -> Void in self?.settleFired(token: token) }
    }

    /// The settle timer: a connection still pending with this token joins the routing (OUT-002-R3).
    func settleFired(token: Int) {
        guard let connection = settle.settle(token: token) else { return }   // cancelled or replaced
        settleConnection(id: connection.id, geometry: connection.geometry, foreground: connection.foreground)
    }

    private func settleConnection(id: String, geometry: ExternalDisplayGeometry, foreground: Bool) {
        let known = routing.displays.contains(where: { (d: ExternalDisplay) -> Bool in d.id == id })
        routing.apply(.connected(id: id, geometry: geometry, foreground: foreground))
        place()
        guard !known else { return }
        let held = heldTarget != nil && effectiveTarget != routing.target
        log.info("external display settled\(held ? " (held by a recording)" : "", privacy: .public)")
        onConnectionChange?(.connected(heldByRecording: held))
    }

    func externalResized(id: String, geometry: ExternalDisplayGeometry) {
        if settle.update(id: id, geometry: geometry) { return }   // still settling
        guard routing.apply(.resized(id: id, geometry: geometry)) else { return }
        log.info("external display size: \(geometry.width, privacy: .public) × \(geometry.height, privacy: .public) @\(geometry.scale, privacy: .public)")
        place()
    }

    func externalForeground(id: String, _ foreground: Bool) {
        log.info("external display foreground: \(foreground, privacy: .public)")
        if settle.update(id: id, foreground: foreground) { return }   // still settling
        if routing.apply(.foreground(id: id, foreground)) { place() }
    }

    /// Inside the call: the visual leaves the slot, the slot is forgotten (OUT-002-R8). A connection
    /// that had not settled is cancelled: nothing moved and nothing is announced (OUT-002-R3).
    func externalDisconnected(id: String) {
        let cancelled = settle.cancel(id: id)
        let known = routing.displays.contains(where: { (d: ExternalDisplay) -> Bool in d.id == id })
        routing.apply(.disconnected(id: id))
        log.info("external display disconnected\(cancelled ? " before it settled" : "", privacy: .public)")
        if let slot = externalSlots.removeValue(forKey: id)?.slot {
            slot.onGeometryChange = nil
            slot.removeVisuals()
        }
        place()
        if !cancelled, known { onConnectionChange?(.disconnected) }
    }

    // MARK: - Recording hold (OUT-002-R4)

    /// True while a recording runs: the visual stays on its current target unless that display is gone.
    /// Turning it off places the visual by OUT-001's rules.
    var holdsPlacement: Bool {
        get { heldTarget != nil }
        set {
            guard newValue != holdsPlacement else { return }
            heldTarget = newValue ? effectiveTarget : nil
            log.info("placement hold: \(newValue, privacy: .public)")
            place()
            if !newValue { pushCorrection() }   // OUT-004-R7: deferred changes apply now
        }
    }

    /// Where the visual is drawn now: OUT-001's target, or the target a recording holds.
    var effectiveTarget: VisualOutputTarget { routing.effectiveTarget(held: heldTarget) }

    /// What the external side holds (OUT-002-R8).
    var externalResources: ExternalResourceCounts {
        let live = externalSlots.values.compactMap { (w: WeakSlot) -> VisualSlotView? in w.slot }
        let holding = live.filter { (slot: VisualSlotView) -> Bool in !slot.subviews.isEmpty }.count
        return ExternalResourceCounts(slots: live.count, pending: settle.pending.count, slotsHoldingVisual: holding)
    }

    /// The visual view the coordinator places (tests).
    var currentVisual: UIView? { visual }

    // MARK: - Output correction (OUT-004)

    func deviceSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let aspect = Double(size.width) / Double(size.height)
        guard aspect != deviceAspect else { return }
        deviceAspect = aspect
        pushCorrection()
    }

    /// Sends the correction and device shape to every external slot and lays the visual out inside
    /// the call; nothing while a recording holds the placement (OUT-004-R7).
    private func pushCorrection() {
        guard heldTarget == nil else { return }
        for slot in externalSlots.values.compactMap({ (w: WeakSlot) -> VisualSlotView? in w.slot }) {
            slot.correction = correction
            slot.deviceAspect = deviceAspect
            slot.applyPlacement()
        }
        if let summary = externalPlacementSummary { log.info("external placement: \(summary, privacy: .public)") }
    }

    /// "fit=<fit> shape=<shape> par=<x.xx> frame=<W>x<H> bars=<none|pillarbox|letterbox>" for the
    /// external slot holding the visual; nil when the visual is not on an external display (tests,
    /// DEBUG probe, log; sizes only).
    var externalPlacementSummary: String? {
        guard let slot = visual?.superview as? VisualSlotView, slot.role == .external else { return nil }
        let p: ExternalOutputPlacement = slot.placement
        let applied: ExternalOutputCorrection = slot.correction
        let par: Double = applied.pixelAspect.resolved(screen: slot.screenPixelAspect)
        let width: Int = Int(p.frameWidth.rounded())
        let height: Int = Int(p.frameHeight.rounded())
        let parText: String = String(format: "%.2f", par)
        let head: String = "fit=" + applied.fit.rawValue + " shape=" + applied.shape.rawValue + " par=" + parText
        return head + " frame=\(width)x\(height) bars=" + p.bars.rawValue
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
        let target = effectiveTarget
        if heldTarget != nil { heldTarget = target }   // a held display that is gone: the hold follows the fallback
        let targetSlot: VisualSlotView?
        switch target {
        case .device: targetSlot = deviceSlot
        case let .external(id): targetSlot = externalSlots[id]?.slot
        }
        let external: Bool
        if case .external = target { external = true } else { external = false }
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

/// OUT-001-D4: scene events that concern the device's visuals. The Camera, Photo and Video hosts observe
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
