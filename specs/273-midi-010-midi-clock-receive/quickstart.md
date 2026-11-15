# Quickstart: MIDI-010 MIDI Clock Receive

Run from the worktree root.

1. Package tests (host, under 1 minute):
   `swift test --package-path Packages/PerformanceControl --filter "MIDIClockTests|TempoSourceTests|MIDIEventRingTests|MIDIMessageDecodingTests"`
   — expect all pass (S1–S4).
2. App unit tests on the private iOS 27.2 simulator "MIDI10 iPhone 17":
   `-only-testing:projectM-iOSTests/MIDIClockCoordinatorTests -only-testing:projectM-iOSTests/TempoCoordinatorTests -only-testing:projectM-iOSTests/LibraryBackupAppTests -only-testing:projectM-iOSTests/SettingsTests`
   — the snapshot follows the fake clock with the toggle on and ignores it off (S5).
3. UI test (under 30 s): `-only-testing:projectM-iOSUITests/MIDIClockUITests` (S6).
4. Repository checks: compliance, docs, motion policy, permission catalog, status events, script tests (S7).
5. `{device}`: on D1 with a hardware or app clock source at 120 and 174 BPM, turn on Follow MIDI clock; the readout
   shows the BPM and the beat grid follows Start.
