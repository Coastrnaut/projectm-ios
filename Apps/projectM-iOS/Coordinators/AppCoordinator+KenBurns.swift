// AppCoordinator+KenBurns.swift — the Ken Burns setting's link to the photo layer (MED-007-R5, R7, R8, R10; contracts/
// ken-burns.md K4; research MED-007-D7).
//
// * `applyKenBurns()` hands the photo layer the movement, Reduce Motion and, while the slideshow is active, the slide's
//   dwell as the duration. It runs when the Photo visual is created, when its content is re-chosen, on every setting
//   change and when the system Reduce Motion changes; the slideshow's tick keeps the dwell current (Beats mode follows
//   the tempo grid). Equal values change nothing in the layer, so calling it often never restarts the movement.
// * `restorePhotoMotion(_:)` applies a document's photo-layer fields (MED-006's slideshow, MED-007's movement) at every
//   place a scene, cue or reopened scene is restored.
import Compositor
import Foundation
import ImageLayer

extension AppCoordinator {
    /// Wires the Ken Burns setting (called once in init, from `connectSlideshow`).
    func connectKenBurns() {
        kenBurns.announce = { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .layer) }
        kenBurns.onChange = { [weak self] () -> Void in self?.applyKenBurns() }
    }

    /// The photo layer's movement, Reduce Motion and duration (nil: the movement's own).
    func applyKenBurns() {
        guard let layer = photoVisual?.photo else { return }
        KenBurnsCoordinator.apply(kenBurns.motion, reduceMotion: settings.systemReduceMotion,
                                  duration: kenBurnsDurationOverride(grid: currentSlideshowGrid), to: layer)
    }

    /// The slide's dwell while the slideshow is active (nil otherwise).
    func kenBurnsDurationOverride(grid: SlideshowBeatGrid?) -> UInt64? {
        guard slideshow.isActive else { return nil }
        return KenBurnsCoordinator.slideDwellNanoseconds(slideshow.settings, grid: grid)
    }

    /// The tempo grid the slideshow follows now (nil outside Beats mode or without a reliable tempo).
    var currentSlideshowGrid: SlideshowBeatGrid? {
        slideshow.settings.mode == .beats ? SlideshowCoordinator.grid(snapshot: tempo.snapshot, readout: tempo.readout) : nil
    }

    /// A restored document's photo-layer fields: the slideshow (MED-006-R12) and the Ken Burns movement (MED-007-R10).
    func restorePhotoMotion(_ restore: SceneSlideshowRestore) {
        slideshow.restore(restore.value)
        kenBurns.restore(restore.kenBurns)
    }
}
