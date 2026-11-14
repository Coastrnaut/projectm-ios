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
        if role == .external { reportGeometry() } else { reportSize() }
    }

    /// OUT-004: lays the held visual out by the current correction now (also outside a layout pass:
    /// a change pushed from another view's layout is applied inside the call).
    func applyPlacement() {
        placement = currentPlacement()
        for view in subviews { lay(view) }
    }

    /// OUT-004-D3: the screen's current mode's pixel aspect ratio (nil off screen).
    var screenPixelAspect: Double? {
        (window?.windowScene?.screen.currentMode?.pixelAspectRatio).map { (r: CGFloat) -> Double in Double(r) }
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
        for view in subviews where view !== visual { view.removeFromSuperview() }
        let moved = visual.superview !== self
        if moved {
            visual.removeFromSuperview()
            visual.autoresizingMask = []   // OUT-004: laid out by the placement, not by autoresizing
            addSubview(visual)
        }
        placement = currentPlacement()
        lay(visual)
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
        guard cover.frame != layer.bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cover.frame = layer.bounds
        CATransaction.commit()
    }

    /// OUT-010 (tests, DEBUG probe): the slot shows only black: the cover is fully opaque, fills
    /// the slot and is not animating.
    var isOutputBlack: Bool {
        cover.opacity >= 1 && !cover.isHidden && cover.superlayer === layer && cover.frame == layer.bounds
            && (cover.animationKeys() ?? []).isEmpty
    }

    func removeVisuals() {
        for view in subviews { view.removeFromSuperview() }
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
