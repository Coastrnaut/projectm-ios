// AppCoordinator+ChromaticSplit.swift — FX-006: the chromatic split reaches the compositor-backed visuals (FX-006-R1,
// R9; specs/293-fx-006-chromatic-split; ADR-0104).
//
// The user's value goes to the Camera, Photo, Video and Text compositors when the setting changes and when a visual is
// created (`trailsCompositors`, the same four). The native spectra and projectM have no output effect chain.
import Compositor

extension AppCoordinator {
    /// Wires the setting to the visuals (called once from init).
    func connectChromaticSplit() {
        chromaticSplit.onChange = { [weak self] (_: ChromaticSplit) -> Void in self?.applyChromaticSplit() }
    }

    func applyChromaticSplit() {
        Self.apply(chromatic: chromaticSplit.split, to: trailsCompositors)
    }

    static func apply(chromatic split: ChromaticSplit, to compositors: [Compositor]) {
        for compositor in compositors { compositor.chromaticSplit = split }
    }
}
