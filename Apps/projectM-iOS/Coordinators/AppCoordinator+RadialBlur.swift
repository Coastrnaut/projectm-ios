// AppCoordinator+RadialBlur.swift — FX-008: the radial blur reaches the compositor-backed visuals (FX-008-R1, R9;
// specs/296-fx-008-radial-blur; ADR-0107).
//
// The user's value goes to the Camera, Photo, Video and Text compositors when the setting changes and when a visual is
// created (`trailsCompositors`, the same four). The native spectra and projectM have no output effect chain.
import Compositor

extension AppCoordinator {
    /// Wires the setting to the visuals (called once from init).
    func connectRadialBlur() {
        radialBlur.onChange = { [weak self] (_: RadialBlur) -> Void in self?.applyRadialBlur() }
    }

    func applyRadialBlur() {
        Self.apply(radialBlur: radialBlur.blur, to: trailsCompositors)
    }

    static func apply(radialBlur blur: RadialBlur, to compositors: [Compositor]) {
        for compositor in compositors { compositor.radialBlur = blur }
    }
}
