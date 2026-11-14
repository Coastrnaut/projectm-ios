// AppCoordinator+MotionFeedback.swift — FX-009: Trails reach the compositor-backed visuals, and scene changes clear them
// (FX-009-R1, R5, R7; specs/130-fx-009-motion-feedback, research FX-009-D4, D6).
//
// * The effective value (the user's Trails after ACC-012's caps) goes to the Camera, Photo, Video and Text compositors
//   when the setting, the safety profile or Reduce flashing changes, and when a visual is created. The native spectra
//   and projectM have no trails.
// * `resetTrailsHistory()` makes the next frame of every compositor-backed visual show its new scene only. Show cue
//   apply (and UIX-002's switcher, which steps through it), scene reopen and undo/redo call it; a visual switch and a
//   resumed frame loop reset through the host's `resetFlashHistory()` at loop start, and size and output-format changes
//   inside the compositor.
import Compositor

extension AppCoordinator {
    /// The Trails the compositors apply now.
    var effectiveMotionFeedback: MotionFeedback { motionFeedback.effective(clamp: settings.safetyClamp) }

    /// The compositor-backed visuals that exist.
    var trailsCompositors: [Compositor] {
        [cameraVisual?.compositor, photoVisual?.compositor, videoVisual?.compositor, textVisual?.compositor]
            .compactMap { (c: Compositor?) -> Compositor? in c }
    }

    /// Wires the setting to the visuals (called once from init; kept out of init's body for its type-check budget).
    func connectMotionFeedback() {
        motionFeedback.onChange = { [weak self] (_: MotionFeedback) -> Void in self?.applyMotionFeedback() }
    }

    func applyMotionFeedback() {
        Self.apply(effectiveMotionFeedback, to: trailsCompositors)
    }

    /// FX-009-R5, R6: the next frame of each compositor-backed visual has no prior-scene content.
    func resetTrailsHistory() {
        Self.resetTrails(trailsCompositors)
    }

    /// The two steps on given compositors (app tests drive them with a real host's compositor).
    static func apply(_ feedback: MotionFeedback, to compositors: [Compositor]) {
        for compositor in compositors { compositor.motionFeedback = feedback }
    }

    static func resetTrails(_ compositors: [Compositor]) {
        for compositor in compositors { compositor.resetFeedback() }
    }
}
