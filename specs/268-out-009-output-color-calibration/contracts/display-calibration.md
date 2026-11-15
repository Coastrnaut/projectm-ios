# Contract: OUT-009 display calibration

- **C1 (Compositor, pure)**: `DisplayCalibration` as in data-model.md; `DisplayCalibrationReceiver`
  (`@MainActor`, `AnyObject`): `var displayCalibration: DisplayCalibration { get set }`,
  `var acceptsDisplayCalibration: Bool { get }`.
- **C2 (Compositor GPU)**: `Compositor.displayCalibration` (default identity). `composite(into:)` draws its
  screen pass with `cmp_output_calibrated` (fragment buffer 3: `CMPCalibration { float4 gain; float4 params }`,
  params.x = exponent) only when not the identity; otherwise `cmp_output` exactly as before.
  `encodeOutput`, captures and `SceneTransitionBus` never calibrate. `calibratedFrames` counts calibrated
  screen passes (tests).
- **C3 (renderers)**: `PMFlashLimiterSetCalibration(limiter, enabled, exponent, r, g, b)` stores uniforms the
  output step applies after the gain (encoded values, clamped); `PMFlashLimiterDrawOutput(limiter, target,
  calibrated)` redraws the output step from the current state. ANGLERenderer's view is a receiver; the
  renderer applies the view's calibration each frame and keeps captures uncalibrated. Compositor hosts
  install `NativeSpectrumLayerView.onDisplayCalibrationChange` → `compositor.displayCalibration`.
- **C4 (app routing)**: `VisualSlotView.calibration` (external slots apply it to held receivers; the device
  slot and `removeVisuals` give the identity). `ExternalDisplayCoordinator.displayCalibration` is pushed to
  every external slot inside the call, also during a recording hold. `ExternalOutputSetting.calibration`
  persists `settings.externalDisplay.calibration` and pushes live.
- **C5 (UI)**: Settings › External Display › "Color calibration…" (`externalCalibrationButton`) opens
  `DisplayCalibrationEditorView`: sliders `calibrationGamma`, `calibrationRed`, `calibrationGreen`,
  `calibrationBlue` (ACC-005), readouts, Reset (`calibrationReset`, disabled at identity), Done
  (`calibrationDone`), a footer naming the uncovered visuals.
- **C6 (DEBUG probe)**: `externalCalibration` = "cal=<identity|custom> applied=<yes|no|unsupported|none>
  values=<stored>"; `none` without an external slot holding a visual.
