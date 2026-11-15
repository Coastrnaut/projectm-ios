// ExternalOutputSetting+Profile.swift — OUT-014 (spec specs/288-out-014-output-profile-export, contract C2): the
// setting as an `OutputProfile` and back. Applying sets every property inside the call; their existing `didSet`s write
// the usual `settings.externalDisplay.*` keys and push each value to the external coordinator, so a connected display
// updates at once (placement changes still wait for a recording hold, as from the controls). No new storage.
// OUT-008: the grid warp travels too (optional in the file).
import Compositor
import PresentationLifecycle

extension ExternalOutputSetting {
    /// The current transforms, with the class of the display they are for (nil: none connected).
    func outputProfile(display: OutputDisplayClass?) -> OutputProfile {
        let c: DisplayCalibration = calibration
        return OutputProfile(fit: fit, shape: shape, pixelAspect: pixelAspect, resolution: resolution, outputMode: outputMode,
                             cornerPin: cornerPin,
                             calibration: OutputProfile.Calibration(gamma: c.gamma, red: c.red, green: c.green, blue: c.blue),
                             display: display, gridWarp: gridWarp)
    }

    /// Sets every transform of a validated profile (OUT-014-R7).
    func apply(_ profile: OutputProfile) {
        fit = profile.fit
        shape = profile.shape
        pixelAspect = profile.pixelAspect
        resolutionMode = profile.resolution.mode
        resolutionPercent = profile.resolution.percent
        outputMode = profile.outputMode
        cornerPin = profile.cornerPin
        let c: OutputProfile.Calibration = profile.calibration
        calibration = DisplayCalibration(gamma: c.gamma, red: c.red, green: c.green, blue: c.blue)
        gridWarp = profile.gridWarp   // OUT-008 (validated by the decoder)
    }
}
