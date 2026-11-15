// AppCoordinator+DirectionalBlur.swift — FX-007: the directional blur reaches the compositor-backed visuals (FX-007-R1,
// R10; specs/295-fx-007-directional-blur; ADR-0106).
//
// The user's value goes to the Camera, Photo, Video and Text compositors when the setting changes and when a visual is
// created (`trailsCompositors`, the same four). The native spectra and projectM have no output effect chain.
import Compositor

extension AppCoordinator {
    /// Wires the setting to the visuals (called once from init).
    func connectDirectionalBlur() {
        directionalBlur.onChange = { [weak self] (_: DirectionalBlur) -> Void in self?.applyDirectionalBlur() }
    }

    func applyDirectionalBlur() {
        Self.apply(directionalBlur: directionalBlur.blur, to: trailsCompositors)
    }

    static func apply(directionalBlur blur: DirectionalBlur, to compositors: [Compositor]) {
        for compositor in compositors { compositor.directionalBlur = blur }
    }
}
