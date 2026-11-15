// AppCoordinator+FilmGrain.swift — FX-017: the film grain reaches the compositor-backed visuals (FX-017-R1, R4, R10;
// specs/311-fx-017-film-grain; ADR-0122).
//
// The effective value (the user's, with "Vary over time" off while Reduce Motion is on) goes to the Camera, Photo, Video
// and Text compositors when the setting or Reduce Motion changes and when a visual is created (`trailsCompositors`, the
// same four). Reduce flashing is applied by the compositor itself from each frame's context. The native spectra and
// projectM have no output effect chain.
import Compositor

extension AppCoordinator {
    /// What the compositors draw: static grain under Reduce Motion (research FX-017-D4).
    var effectiveFilmGrain: FilmGrain { filmGrain.grain.effective(reduceMotion: settings.systemReduceMotion) }

    /// Wires the setting to the visuals (called once from init).
    func connectFilmGrain() {
        filmGrain.onChange = { [weak self] (_: FilmGrain) -> Void in self?.applyFilmGrain() }
    }

    func applyFilmGrain() {
        Self.apply(filmGrain: effectiveFilmGrain, to: trailsCompositors)
    }

    static func apply(filmGrain value: FilmGrain, to compositors: [Compositor]) {
        for compositor in compositors { compositor.filmGrain = value }
    }
}
