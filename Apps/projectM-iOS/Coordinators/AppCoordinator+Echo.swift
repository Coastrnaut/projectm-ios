// AppCoordinator+Echo.swift — FX-010: Echo reaches the compositor-backed visuals (FX-010-R1, R10;
// specs/297-fx-010-echo-feedback; ADR-0108).
//
// The effective value (the user's Echo after ACC-012's weight cap) goes to the Camera, Photo, Video and Text
// compositors (`trailsCompositors`) when the setting, the safety profile or Reduce flashing changes, and when a visual
// is created. Scene changes empty its history through the compositors' `resetFeedback()` and `resetFlashHistory()`,
// the same calls that clear Trails. The native spectra and projectM have no output effect chain.
import Compositor

extension AppCoordinator {
    /// The Echo the compositors apply now.
    var effectiveEcho: EchoFeedback { echoFeedback.effective(clamp: settings.safetyClamp) }

    /// Wires the setting to the visuals (called once from init).
    func connectEcho() {
        echoFeedback.onChange = { [weak self] (_: EchoFeedback) -> Void in self?.applyEcho() }
    }

    func applyEcho() {
        Self.apply(echo: effectiveEcho, to: trailsCompositors)
    }

    static func apply(echo: EchoFeedback, to compositors: [Compositor]) {
        for compositor in compositors { compositor.echoFeedback = echo }
    }
}
