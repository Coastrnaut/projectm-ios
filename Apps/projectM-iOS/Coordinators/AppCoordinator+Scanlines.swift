// AppCoordinator+Scanlines.swift — FX-018: the scanlines reach the compositor-backed visuals (FX-018-R1, R9;
// specs/312-fx-018-scanline-texture; ADR-0123).
//
// The user's value goes to the Camera, Photo, Video and Text compositors when the setting changes and when a visual is
// created (`trailsCompositors`, the same four). The native spectra and projectM have no output effect chain.
import Compositor

extension AppCoordinator {
    /// Wires the setting to the visuals (called once from init).
    func connectScanlines() {
        scanlines.onChange = { [weak self] (_: Scanlines) -> Void in self?.applyScanlines() }
    }

    func applyScanlines() {
        Self.apply(scanlines: scanlines.scanlines, to: trailsCompositors)
    }

    static func apply(scanlines value: Scanlines, to compositors: [Compositor]) {
        for compositor in compositors { compositor.scanlines = value }
    }
}
