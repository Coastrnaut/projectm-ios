# Quickstart: MIDI-008 MIDI Transport Mapping

Run from the worktree root.

1. Package tests (host, under 1 minute):
   `swift test --package-path Packages/PerformanceControl --filter "MIDITransportTests|MIDINoteTriggerTests|MIDISceneSelectionTests|MIDILearnTests|MIDICCScalingTests"`
   — expect all pass (S1, S3, S4).
2. App unit tests on the private iOS 27.2 simulator "MIDI8":
   `xcodebuild test-without-building … -only-testing:projectM-iOSTests/MIDITransportCoordinatorTests -only-testing:projectM-iOSTests/MIDINoteTriggerCoordinatorTests -only-testing:projectM-iOSTests/MIDIMappingCoordinatorTests -only-testing:projectM-iOSTests/MIDISceneSelectionCoordinatorTests`
   — expect one action per press for each source and pattern, and Play/Pause toggling (S1, S2).
3. UI test (under 30 s): `-only-testing:projectM-iOSUITests/MIDITransportUITests` — learns a CC button for Next cue and
   presses it twice (S5).
4. Repository checks: compliance, docs, motion policy, permission catalog, status events, script tests.
5. `{device}`: with a physical controller on D1, map a CC button and a pad to Next cue and Play/Pause; each press acts
   once.
