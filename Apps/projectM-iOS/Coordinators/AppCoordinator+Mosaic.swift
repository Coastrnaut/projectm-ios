// AppCoordinator+Mosaic.swift — FX-012: the mosaic reaches the compositor-backed visuals (FX-012-R1, R9;
// specs/299-fx-012-mosaic-pixelation; ADR-0110).
//
// The user's value goes to the Camera, Photo, Video and Text compositors when the setting changes and when a visual is
// created (`trailsCompositors`, the same four). The native spectra and projectM have no output effect chain.
import Compositor

extension AppCoordinator {
    /// Wires the setting to the visuals (called once from init).
    func connectMosaic() {
        mosaic.onChange = { [weak self] (_: Mosaic) -> Void in self?.applyMosaic() }
    }

    func applyMosaic() {
        Self.apply(mosaic: mosaic.mosaic, to: trailsCompositors)
    }

    static func apply(mosaic value: Mosaic, to compositors: [Compositor]) {
        for compositor in compositors { compositor.mosaic = value }
    }
}
