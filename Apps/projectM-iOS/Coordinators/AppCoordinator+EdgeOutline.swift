// AppCoordinator+EdgeOutline.swift — FX-014: the edge outline reaches the compositor-backed visuals (FX-014-R1, R10,
// R15; specs/303-fx-014-edge-outline; ADR-0114).
//
// The effective value (the user's outline with ACC-012's colour scale) goes to the Camera, Photo, Video and Text
// compositors (`trailsCompositors`, the same four) when the setting or the safety profile changes and when a visual is
// created. The native spectra and projectM have no output effect chain.
import Compositor

extension AppCoordinator {
    /// The outline the compositors apply now.
    var effectiveEdgeOutline: EdgeOutline { edgeOutline.effective(clamp: settings.safetyClamp) }

    /// Wires the setting to the visuals (called once from init).
    func connectEdgeOutline() {
        edgeOutline.onChange = { [weak self] (_: EdgeOutline) -> Void in self?.applyEdgeOutline() }
    }

    func applyEdgeOutline() {
        Self.apply(edgeOutline: effectiveEdgeOutline, to: trailsCompositors)
    }

    static func apply(edgeOutline value: EdgeOutline, to compositors: [Compositor]) {
        for compositor in compositors { compositor.edgeOutline = value }
    }
}
