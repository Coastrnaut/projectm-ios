// AppCoordinator+Vignette.swift — FX-015: the vignette reaches the compositor-backed visuals (FX-015-R1, R9;
// specs/305-fx-015-vignette; ADR-0116).
//
// The user's value goes to the Camera, Photo, Video and Text compositors when the setting changes and when a visual is
// created (`trailsCompositors`, the same four). The native spectra and projectM have no output effect chain.
import Compositor

extension AppCoordinator {
    /// Wires the setting to the visuals (called once from init).
    func connectVignette() {
        vignette.onChange = { [weak self] (_: Vignette) -> Void in self?.applyVignette() }
    }

    func applyVignette() {
        Self.apply(vignette: vignette.vignette, to: trailsCompositors)
    }

    static func apply(vignette value: Vignette, to compositors: [Compositor]) {
        for compositor in compositors { compositor.vignette = value }
    }
}
