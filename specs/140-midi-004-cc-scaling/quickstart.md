# Quickstart: MIDI-004 MIDI CC Scaling

Run from the worktree root.

1. Package tests (host, under 1 minute):
   `swift test --package-path Packages/PerformanceControl --filter "MIDICCScalingTests|MIDILearnTests"`
   — expect all pass (C1-C3).
2. App unit tests on a private iOS 27.2 simulator:
   `xcodebuild test-without-building … -only-testing:projectM-iOSTests/MIDIMappingCoordinatorTests`
   — expect the inverted fake-MIDI test to give the glow maximum at value 0 (C4).
3. UI test (under 30 s): `-only-testing:projectM-iOSUITests/MIDICCScalingUITests` — seeds
   `cc:0:7=effect.bloom.intensity`, opens the Curve row, toggles Invert, sees "Linear, inverted".
4. Repository checks: compliance, docs, motion policy, permission catalog, status events, script tests.
5. `{device}`: with a physical controller on D1, map a fader to Glow intensity, set Inverted, and confirm
   fully down gives the brightest glow and fully up none.
