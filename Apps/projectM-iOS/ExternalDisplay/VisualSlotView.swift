// VisualSlotView.swift — OUT-001-D3: a place the visualization can be shown in (the device's
// visualizer, an external display's window). Exactly one slot holds the visual view at a time;
// ExternalDisplayCoordinator decides which. SwiftUI hosts the device slot, never the visual view.
// OUT-010: every slot has an opaque black cover layer above the visual; the coordinator sets its
// opacity for the output blackout, with implicit animations off, so a change is part of the current
// Core Animation transaction and shows at the next composited frame (research OUT-010-D1).
// OUT-004 (spec specs/172-out-004-aspect-correction, contract C2): an external slot lays the visual
// out by `ExternalOutputPlacement` (bounds, centre, horizontal scale 1/PAR) from its correction, the
// device's shape and its screen mode's pixel aspect ratio; the slot's black background shows as the
// bars and the cover stays above both. The device slot always fills (identity) and reports its size.
// OUT-012 (spec specs/184-out-012-display-rehearsal, contract C2): a slot with no screen (the
// rehearsal preview, a test's fake display of a profile) takes a stand-in pixel aspect ratio.
// OUT-003 (spec specs/255-out-003-output-resolution, contract C2): an external slot sets the display
// scale its held visual reads (`traitOverrides.displayScale`) to the resolved output scale, so the
// visual's drawable has the chosen pixel count while its bounds, centre and transform (the scene's
// coordinate space) stay exactly as OUT-004 placed them. The slot's own scale is left alone, so its
// geometry still reports the screen. The device slot and `removeVisuals()` remove the override.
// OUT-007 (spec specs/264-out-007-corner-pin, contract C2; research OUT-007-D1, D4): an external slot shows
// everything it holds (the visual as OUT-004 placed it, the bars, the calibration card, the cover) through the
// corner pin's projective transform, set as its layer's `sublayerTransform` (Core Animation composites it: no
// extra render pass, any kind of layer content). The device slot never takes one. While the corner-pin editor
// is open the slot shows OUT-012's test card as a layer between the visual and the cover.
// OUT-009 (spec specs/268-out-009-output-color-calibration, contract C4; research OUT-009-D1, D6): Core Animation has
// no public colour transform on iOS, so an external slot hands its display calibration to the held visual's view
// when it is a `DisplayCalibrationReceiver` (projectM's ANGLE view, a compositor host's view), whose renderer applies
// it in its final pass. The device slot, and a visual leaving any slot, get the identity.
// OUT-011 (spec specs/275-out-011-output-diagnostics, contract C2): `standInReadings` for the DEBUG fake display.
// OUT-008 (spec specs/309-out-008-grid-warp, contract C4; research OUT-008-D1): like OUT-009's calibration, an external
// slot hands its grid warp mesh to the held visual's view when it is an `OutputWarpReceiver` (its final pass draws it,
// inside the picture as OUT-004 placed it; the corner pin then maps the whole slot). The device slot, and a visual
// leaving any slot, get `.none`.
import Compositor
import PresentationLifecycle
import SwiftUI
import UIKit

final class VisualSlotView: UIView {
    enum Role { case device, external }
    let role: Role
    /// External slots: the window's size in points and the screen's scale changed.
    var onGeometryChange: ((ExternalDisplayGeometry) -> Void)?
    /// The slot entered or left a window (the iOS 27 scene accessory joins the coordinator here).
    var onWindowChange: ((VisualSlotView) -> Void)?
    private var reported: ExternalDisplayGeometry?
    /// OUT-004: the external output correction and the device visualizer's shape (width ÷ height).
    var correction: ExternalOutputCorrection = .default {
        didSet { if correction != oldValue { setNeedsLayout() } }
    }
    var deviceAspect: Double? {
        didSet { if deviceAspect != oldValue { setNeedsLayout() } }
    }
    /// Device slots: the slot's size changed (the coordinator derives the device shape from it).
    var onSizeChange: ((CGSize) -> Void)?
    private var reportedSize: CGSize = .zero
    /// OUT-004: the placement last applied to the visual.
    private(set) var placement = ExternalOutputPlacement.filling(width: 0, height: 0)
    /// OUT-010: black, above every subview's layer; opacity 0 while the output is live.
    private let cover = CALayer()
    /// OUT-003: the external output resolution and this device's pixel budget (external slots only).
    var resolution: ExternalOutputResolution = .native {
        didSet { if resolution != oldValue { setNeedsLayout() } }
    }
    var pixelBudget: ExternalPixelBudget = .unlimited {
        didSet { if pixelBudget != oldValue { setNeedsLayout() } }
    }
    /// OUT-003: the output last applied to the held visual (nil on the device or without a size).
    private(set) var resolvedOutput: ResolvedExternalOutput?
    /// OUT-007: the corner pin (applied on external slots only) and the calibration card.
    var cornerPin: CornerPin = .identity {
        didSet { if cornerPin != oldValue { applyCornerPin() } }
    }
    var showsCalibrationCard = false {
        didSet {
            guard showsCalibrationCard != oldValue else { return }
            syncCoverFrame()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            card.isHidden = !showsCalibrationCard
            CATransaction.commit()
        }
    }
    private let card = CornerPinCardLayer()
    /// OUT-008: the grid warp mesh (handed to held receivers on external slots only).
    var outputWarp: OutputWarpMesh = .none {
        didSet { if outputWarp != oldValue { applyWarp() } }
    }
    /// OUT-009: the display calibration (applied to held receivers on external slots only).
    var calibration: DisplayCalibration = .identity {
        didSet { if calibration != oldValue { applyCalibration() } }
    }

    init(role: Role) {
        self.role = role
        super.init(frame: .zero)
        backgroundColor = .black
        isOpaque = true
        clipsToBounds = true
        isUserInteractionEnabled = false   // taps go to the visualizer's tap target (device); none arrive on an external display
        cover.backgroundColor = UIColor.black.cgColor
        cover.isOpaque = true
        cover.opacity = 0
        cover.zPosition = 10_000   // above the visual's layer whatever the subview order
        cover.actions = ["opacity": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull()]
        layer.addSublayer(cover)
        layer.addSublayer(card)   // OUT-007: hidden until the corner-pin editor opens
        if role == .external {
            registerForTraitChanges([UITraitDisplayScale.self]) { (slot: VisualSlotView, _: UITraitCollection) in
                slot.reportGeometry()
            }
            NotificationCenter.default.addObserver(self, selector: #selector(screenModeChanged(_:)),
                                                   name: UIScreen.modeDidChangeNotification, object: nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var geometry: ExternalDisplayGeometry {
        ExternalDisplayGeometry(width: Double(bounds.width), height: Double(bounds.height),
                                scale: Double(traitCollection.displayScale))
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyPlacement()
        syncCoverFrame()
        applyCornerPin()
        if role == .external { reportGeometry() } else { reportSize() }
    }

    /// OUT-004: lays the held visual out by the current correction now (also outside a layout pass:
    /// a change pushed from another view's layout is applied inside the call).
    func applyPlacement() {
        placement = currentPlacement()
        for view in subviews { lay(view) }
        applyResolution()
        applyCalibration()
        applyWarp()   // OUT-008
    }

    /// OUT-009: the calibration each held receiver applies here (the identity on the device).
    private var effectiveCalibration: DisplayCalibration { role == .external ? calibration : .identity }

    private func applyCalibration() {
        let value: DisplayCalibration = effectiveCalibration
        for view in subviews {
            guard let receiver = view as? DisplayCalibrationReceiver, receiver.displayCalibration != value else { continue }
            receiver.displayCalibration = value
        }
    }

    /// OUT-008: the mesh each held receiver draws here (`.none` on the device).
    private func applyWarp() {
        let value: OutputWarpMesh = role == .external ? outputWarp : .none
        for view in subviews {
            guard let receiver = view as? OutputWarpReceiver, receiver.outputWarp != value else { continue }
            receiver.outputWarp = value
        }
    }

    private static func removeWarp(_ view: UIView) {
        guard let receiver = view as? OutputWarpReceiver, receiver.outputWarp != .none else { return }
        receiver.outputWarp = .none
    }

    /// OUT-008 (tests, DEBUG probe): "yes" when the held visual draws this slot's active mesh, "unsupported" when it
    /// cannot, "no" otherwise; nil without a visual.
    var warpState: String? {
        guard let view = subviews.first else { return nil }
        guard let receiver = view as? OutputWarpReceiver, receiver.acceptsOutputWarp else { return "unsupported" }
        let value: OutputWarpMesh = role == .external ? outputWarp : .none
        return value.isActive && receiver.outputWarp == value ? "yes" : "no"
    }

    private static func removeCalibration(_ view: UIView) {
        guard let receiver = view as? DisplayCalibrationReceiver, !receiver.displayCalibration.isIdentity else { return }
        receiver.displayCalibration = .identity
    }

    /// OUT-009 (tests, DEBUG probe): "yes" when the held visual applies this slot's (non-identity) calibration,
    /// "unsupported" when it cannot, "no" otherwise; nil without a visual.
    var calibrationState: String? {
        guard let view = subviews.first else { return nil }
        guard let receiver = view as? DisplayCalibrationReceiver, receiver.acceptsDisplayCalibration else { return "unsupported" }
        let value: DisplayCalibration = effectiveCalibration
        return !value.isIdentity && receiver.displayCalibration == value ? "yes" : "no"
    }

    /// OUT-003-D3: the choice is resolved against the screen (this slot's size and its own display
    /// scale), then the device budget against the visual's own size (Fill renders the cropped
    /// overflow too). Only the visual's display scale changes; never its bounds.
    private func applyResolution() {
        guard role == .external else {
            resolvedOutput = nil
            for view in subviews { Self.removeScale(view) }
            return
        }
        let nativeScale: Double = Double(traitCollection.displayScale)
        let chosen: ResolvedExternalOutput = resolution.resolve(width: Double(bounds.width), height: Double(bounds.height),
                                                                nativeScale: nativeScale, budget: .unlimited)
        let drawable: ResolvedExternalOutput = ExternalOutputResolution.native.resolve(
            width: placement.boundsWidth, height: placement.boundsHeight, nativeScale: chosen.scale, budget: pixelBudget)
        guard drawable.pixelWidth > 0, drawable.pixelHeight > 0 else {
            resolvedOutput = nil
            for view in subviews { Self.removeScale(view) }
            return
        }
        let native: Bool = chosen.isNative && drawable.isNative
        resolvedOutput = ResolvedExternalOutput(scale: drawable.scale, pixelWidth: drawable.pixelWidth,
                                                pixelHeight: drawable.pixelHeight, clamped: drawable.clamped, isNative: native)
        for view in subviews {
            if native { Self.removeScale(view) } else { Self.setScale(drawable.scale, on: view) }
        }
    }

    private static func setScale(_ scale: Double, on view: UIView) {
        let value = CGFloat(scale)
        guard !view.traitOverrides.contains(UITraitDisplayScale.self) || view.traitOverrides.displayScale != value else { return }
        view.traitOverrides.displayScale = value
        view.updateTraitsIfNeeded()   // the new scale is read by the layout that follows, inside the call
        view.setNeedsLayout()
    }

    private static func removeScale(_ view: UIView) {
        guard view.traitOverrides.contains(UITraitDisplayScale.self) else { return }
        view.traitOverrides.remove(UITraitDisplayScale.self)
        view.updateTraitsIfNeeded()
        view.setNeedsLayout()
    }

    /// OUT-012-D3: used instead of the screen mode's ratio when set (a slot standing in for a display).
    var standInPixelAspect: Double? {
        didSet { if standInPixelAspect != oldValue { setNeedsLayout() } }
    }

    /// OUT-011-D4: a stand-in display's screen readings (DEBUG fake, tests), used instead of the screen's own, whose window
    /// sits on the device's screen. Real external scenes never set it.
    var standInReadings: OutputReadings?

    /// OUT-004-D3: the screen's current mode's pixel aspect ratio (nil off screen), or the stand-in.
    var screenPixelAspect: Double? {
        if let standInPixelAspect { return standInPixelAspect }
        return (window?.windowScene?.screen.currentMode?.pixelAspectRatio).map { (r: CGFloat) -> Double in Double(r) }
    }

    @objc private func screenModeChanged(_ notification: Notification) {
        setNeedsLayout()
    }

    private func currentPlacement() -> ExternalOutputPlacement {
        let width = Double(bounds.width), height = Double(bounds.height)
        guard role == .external else { return .filling(width: width, height: height) }
        return ExternalOutputPlacement(slotWidth: width, slotHeight: height, correction: correction,
                                       screenPixelAspect: screenPixelAspect, deviceAspect: deviceAspect)
    }

    /// Bounds, centre and transform from the placement (never `frame`, which a transform makes undefined).
    private func lay(_ view: UIView) {
        let p = placement
        let transform: CGAffineTransform = p.scaleX == 1 ? .identity : CGAffineTransform(scaleX: CGFloat(p.scaleX), y: 1)
        let size = CGRect(x: 0, y: 0, width: CGFloat(p.boundsWidth), height: CGFloat(p.boundsHeight))
        let center = CGPoint(x: CGFloat(p.centerX), y: CGFloat(p.centerY))
        if view.transform != transform { view.transform = transform }
        if view.bounds != size { view.bounds = size }
        if view.center != center { view.center = center }
    }

    private func reportSize() {
        guard bounds.size != reportedSize else { return }
        reportedSize = bounds.size
        onSizeChange?(bounds.size)
    }

    private func reportGeometry() {
        let current = geometry
        guard current != reported else { return }
        reported = current
        onGeometryChange?(current)
    }

    /// Puts `visual` in this slot, filling it, and removes anything else. Returns true when the
    /// view changed slot. The visual is laid out again so its drawable follows this slot's size and
    /// screen scale.
    @discardableResult
    func hold(_ visual: UIView) -> Bool {
        for view in subviews where view !== visual {
            Self.removeScale(view)
            Self.removeCalibration(view)   // OUT-009
            Self.removeWarp(view)   // OUT-008
            view.removeFromSuperview()
        }
        let moved = visual.superview !== self
        if moved {
            visual.removeFromSuperview()
            visual.autoresizingMask = []   // OUT-004: laid out by the placement, not by autoresizing
            addSubview(visual)
        }
        placement = currentPlacement()
        lay(visual)
        applyResolution()   // OUT-003: the external scale, or none on the device
        applyCalibration()   // OUT-009: the display's calibration, or the identity on the device
        applyWarp()   // OUT-008: the display's mesh, or none on the device
        syncCoverFrame()
        visual.setNeedsLayout()
        return moved
    }

    /// OUT-010: the black cover's opacity (0 live, 1 black), set without animation.
    var coverOpacity: Double {
        get { Double(cover.opacity) }
        set {
            let value = Float(min(max(newValue, 0), 1))
            syncCoverFrame()
            guard cover.opacity != value else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cover.opacity = value
            CATransaction.commit()
        }
    }

    private func syncCoverFrame() {
        guard cover.frame != layer.bounds || card.frame != layer.bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cover.frame = layer.bounds
        card.frame = layer.bounds
        CATransaction.commit()
    }

    /// OUT-007: the pin's projective transform for the current bounds about the layer's anchor (the device
    /// slot: identity), set without animation, so a change shows at the next composited frame.
    private func applyCornerPin() {
        let target: CATransform3D = Self.transform(role == .external ? cornerPin : .identity, bounds: layer.bounds,
                                                   anchor: layer.anchorPoint)
        guard !CATransform3DEqualToTransform(layer.sublayerTransform, target) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = target
        CATransaction.commit()
    }

    /// OUT-007-D1, D2: `pin`'s homography as a Core Animation matrix for a layer of `bounds` and `anchor`.
    static func transform(_ pin: CornerPin, bounds: CGRect, anchor: CGPoint) -> CATransform3D {
        guard !pin.isIdentity, bounds.width > 0, bounds.height > 0 else { return CATransform3DIdentity }
        let ax = Double(bounds.minX + anchor.x * bounds.width), ay = Double(bounds.minY + anchor.y * bounds.height)
        let m: [Double] = pin.homography.layerMatrix(width: Double(bounds.width), height: Double(bounds.height),
                                                     anchorX: ax - Double(bounds.minX), anchorY: ay - Double(bounds.minY))
        var t = CATransform3DIdentity
        t.m11 = CGFloat(m[0]); t.m12 = CGFloat(m[1]); t.m13 = CGFloat(m[2]); t.m14 = CGFloat(m[3])
        t.m21 = CGFloat(m[4]); t.m22 = CGFloat(m[5]); t.m23 = CGFloat(m[6]); t.m24 = CGFloat(m[7])
        t.m31 = CGFloat(m[8]); t.m32 = CGFloat(m[9]); t.m33 = CGFloat(m[10]); t.m34 = CGFloat(m[11])
        t.m41 = CGFloat(m[12]); t.m42 = CGFloat(m[13]); t.m43 = CGFloat(m[14]); t.m44 = CGFloat(m[15])
        return t
    }

    /// OUT-007 (tests, DEBUG probe): the calibration card is shown, opaque and filling the slot.
    var isCalibrationCardShown: Bool {
        !card.isHidden && card.superlayer === layer && card.frame == layer.bounds
    }

    /// OUT-010 (tests, DEBUG probe): the slot shows only black: the cover is fully opaque, fills
    /// the slot and is not animating.
    var isOutputBlack: Bool {
        cover.opacity >= 1 && !cover.isHidden && cover.superlayer === layer && cover.frame == layer.bounds
            && (cover.animationKeys() ?? []).isEmpty
    }

    func removeVisuals() {
        for view in subviews {
            Self.removeScale(view)   // OUT-003: a visual leaving the external slot renders at its next host's scale
            Self.removeCalibration(view)   // OUT-009: and uncalibrated
            Self.removeWarp(view)   // OUT-008: and unwarped
            view.removeFromSuperview()
        }
        resolvedOutput = nil
    }
}

/// Hosts the device's slot in SwiftUI and hands the current visual to the coordinator.
struct VisualSlotHost: UIViewRepresentable {
    let visual: UIView
    let external: ExternalDisplayCoordinator

    final class Registration {
        let external: ExternalDisplayCoordinator
        init(external: ExternalDisplayCoordinator) { self.external = external }
    }

    func makeCoordinator() -> Registration { Registration(external: external) }

    func makeUIView(context: Context) -> VisualSlotView {
        let slot = VisualSlotView(role: .device)
        external.registerDeviceSlot(slot)
        external.show(visual)
        return slot
    }

    func updateUIView(_ slot: VisualSlotView, context: Context) {
        external.registerDeviceSlot(slot)
        external.show(visual)
    }

    static func dismantleUIView(_ slot: VisualSlotView, coordinator: Registration) {
        coordinator.external.unregisterDeviceSlot(slot)
    }
}
