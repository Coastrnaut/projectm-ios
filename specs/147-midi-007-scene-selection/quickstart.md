# Quickstart: MIDI-007 MIDI Scene Selection

Run from the worktree root.

1. Package tests (host, under 1 minute):
   `swift test --package-path Packages/PerformanceControl --filter "MIDISceneSelectionTests|MIDINoteTriggerTests|MIDILearnTests|MIDICCScalingTests"`
   — expect all pass (S1-S3).
2. App unit tests on the private iOS 27.2 simulator "MIDI7":
   `xcodebuild test-without-building … -only-testing:projectM-iOSTests/MIDISceneSelectionCoordinatorTests -only-testing:projectM-iOSTests/MIDINoteTriggerCoordinatorTests -only-testing:projectM-iOSTests/MIDIMappingCoordinatorTests`
   — expect PC 5 / channel 1 to select scene X with byte-identical stored mappings, and the same for a note (S4).
3. UI test (under 30 s): `-only-testing:projectM-iOSUITests/MIDISceneSelectionUITests` — assigns program 5 to cue 3's
   scene and triggers it.
4. Repository checks: compliance, docs, motion policy, permission catalog, status events, script tests.
5. `{device}`: with a physical controller on D1, assign a program to a scene and confirm the patch change selects it
   and a repeat does nothing.
