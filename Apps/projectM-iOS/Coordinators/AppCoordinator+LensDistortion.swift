// AppCoordinator+LensDistortion.swift — FX-016: the lens distortion reaches the compositor-backed visuals (FX-016-R1,
// R9; specs/306-fx-016-lens-distortion; ADR-0117).
//
// The user's value goes to the Camera, Photo, Video and Text compositors when the setting changes and when a visual is
// created (`trailsCompositors`, the same four). The native spectra and projectM have no output effect chain.
import Compositor

extension AppCoordinator {
    /// Wires the setting to the visuals (called once from init).
    func connectLensDistortion() {
        lensDistortion.onChange = { [weak self] (_: LensDistortion) -> Void in self?.applyLensDistortion() }
    }

    func applyLensDistortion() {
        Self.apply(lensDistortion: lensDistortion.lens, to: trailsCompositors)
    }

    static func apply(lensDistortion value: LensDistortion, to compositors: [Compositor]) {
        for compositor in compositors { compositor.lensDistortion = value }
    }
}
