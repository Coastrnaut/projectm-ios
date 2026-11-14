# Quickstart: MIDI-006 MIDI Note Triggers

Run from the worktree root.

1. Package tests (host, under 1 minute):
   `swift test --package-path Packages/PerformanceControl --filter "MIDINoteTriggerTests|MIDILearnTests|MIDICCScalingTests|MIDIMessageDecodingTests"`
   — expect all pass (N1-N3).
2. App unit tests on the private iOS 27.2 simulator "MIDI6":
   `xcodebuild test-without-building … -only-testing:projectM-iOSTests/MIDINoteTriggerCoordinatorTests -only-testing:projectM-iOSTests/MIDIMappingCoordinatorTests`
   — expect a Next cue mapping to step once per press and a hold mapping to black out and restore (N4).
3. UI test (under 30 s): `-only-testing:projectM-iOSUITests/MIDINoteTriggersUITests` — learns note C4 to Next cue.
4. Repository checks: compliance, docs, motion policy, permission catalog, status events, script tests.
5. `{device}`: with a physical controller on D1, map a pad to Next cue and a key to Black out while held;
   confirm one step per press and black only while held.
