// VisualSlotView.swift — OUT-001-D3: a place the visualization can be shown in (the device's
// visualizer, an external display's window). Exactly one slot holds the visual view at a time;
// ExternalDisplayCoordinator decides which. SwiftUI hosts the device slot, never the visual view.
// OUT-010: every slot has an opaque black cover layer above the visual; the coordinator sets its
// opacity for the output blackout, with implicit animations off, so a change is part of the current
// Core Animation transaction and shows at the next composited frame (research OUT-010-D1).
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
        for view in subviews where view.frame != bounds { view.frame = bounds }
        syncCoverFrame()
        if role == .external { reportGeometry() }
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
            visual.frame = bounds
            visual.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(visual)
        }
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
