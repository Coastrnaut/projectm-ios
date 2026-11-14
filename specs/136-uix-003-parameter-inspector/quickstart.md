# Quickstart: UIX-003 Context Parameter Inspector

1. Unit tests: `xcodebuild test-without-building ... -only-testing:projectM-iOSTests/ParameterInspectorTests`
   (reset equals the registry default for a 0…1 value, a fraction of the output, a boolean and an
   enum; formatting; modulation reading with a stub binding; read-only parameters have no target).
2. UI test (< 30 s): `-only-testing:projectM-iOSUITests/ParameterInspectorUITests` — opens the
   inspector for `effect.bloom.intensity`, reads unit and range, moves the slider, presses Reset and
   sees the default "50%".
3. Manual (simulator): Settings › Circular Spectrum › Glow on › long press Intensity › Inspect.
