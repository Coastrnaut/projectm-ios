// VisualSlotView.swift — OUT-001-D3: a place the visualization can be shown in (the device's
// visualizer, an external display's window). Exactly one slot holds the visual view at a time;
// ExternalDisplayCoordinator decides which. SwiftUI hosts the device slot, never the visual view.
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

    init(role: Role) {
        self.role = role
        super.init(frame: .zero)
        backgroundColor = .black
        isOpaque = true
        clipsToBounds = true
        isUserInteractionEnabled = false   // taps go to the visualizer's tap target (device); none arrive on an external display
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
        visual.setNeedsLayout()
        return moved
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
