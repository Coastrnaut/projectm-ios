// AppCoordinator+PixelSort.swift — FX-011: the pixel sort reaches the compositor-backed visuals (FX-011-R1, R10;
// specs/310-fx-011-pixel-sorting; ADR-0121).
//
// The user's value goes to the Camera, Photo, Video and Text compositors when the setting changes and when a visual is
// created (`trailsCompositors`, the same four). The native spectra and projectM have no output effect chain.
import Compositor

extension AppCoordinator {
    /// Wires the setting to the visuals (called once from init).
    func connectPixelSort() {
        pixelSort.onChange = { [weak self] (_: PixelSort) -> Void in self?.applyPixelSort() }
    }

    func applyPixelSort() {
        Self.apply(pixelSort: pixelSort.sort, to: trailsCompositors)
    }

    static func apply(pixelSort value: PixelSort, to compositors: [Compositor]) {
        for compositor in compositors { compositor.pixelSort = value }
    }
}
