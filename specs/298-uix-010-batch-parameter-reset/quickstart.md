# Quickstart: UIX-010 Batch Parameter Reset

1. `xcodegen generate`; build for testing on the "UIX10 iPhone 17" simulator (iOS 27.2).
2. Unit: `-only-testing:projectM-iOSTests/ParameterBatchResetTests` — N changed parameters reset in one step, one Undo restores all, Redo resets again, unselected untouched, already-default and locked add no step.
3. UI: `-only-testing:projectM-iOSUITests/ParameterBatchResetUITests` — launched with bars 16 and horizontal orientation; Settings › Search Parameters › Select, tick Bars and Orientation, Reset; values show 64 and Vertical; Undo; values show 16 and Horizontal.
4. `{device}`: on D1 with VoiceOver, the toggles, the counted reset button and the "Reset 2 parameters" announcement.
