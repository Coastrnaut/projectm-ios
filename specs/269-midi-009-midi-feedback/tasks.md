# Tasks: MIDI-009 MIDI Feedback

**Input**: `specs/269-midi-009-midi-feedback/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MIDI-009-S1 to S7). Budgets (owner rule 7): unit tests about 1-2 s (≤ 10 s), package
suite under 1 minute, UI test under 30 s, each xcodebuild run under 10 minutes. `{device}` tasks stay open until a
person runs them.

## Phase 1: Setup

- [ ] MIDI-009-T01 Run `xcodegen generate`, initialize the preset submodules if missing (the `Build` symlink is in place), create the simulator "MIDI9 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run

## Phase 2: Foundational (blocks every story)

- [ ] MIDI-009-T02 `MIDIMappingOptions.feedback` (`fb=1` after `hires=1`, before unknown segments; first occurrence wins; summary ", feedback") in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIMappingOptions.swift` (contract F1; D1; R1, R12)
- [ ] MIDI-009-T03 `MIDIFeedbackMessage`, `MIDIFeedbackQuantizer` (nearest code by binary search over the forward mapping; 0…127 or 0…16383; prefers the known code on a flat run) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIFeedback.swift` (F2; D2; R3)
- [ ] MIDI-009-T04 `MIDIFeedbackOutput` protocol, `RecordingMIDIFeedbackOutput`, `MIDIFeedbackUMP` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIFeedbackOutput.swift`; `CoreMIDIFeedbackOutput` (`MIDIOutputPortCreate`, `MIDISendEventList`, MIDI 1.0 event list) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDISystem/CoreMIDIFeedbackOutput.swift` (F5; D6; R9)

## Phase 3: User Story 1 - A controller's LEDs or motor faders follow the app (P1) — MVP

**Independent test**: a mock output receives exactly one correct CC (or coarse then fine) per parameter change of a feedback mapping, and nothing for a mapping without feedback.

- [ ] MIDI-009-T05 [US1] `MIDIFeedbackEngine` (`configure`, `tick`, `resync`, `sentCount`; 14-bit coarse then fine) and `MIDIFeedbackRouting.destinations(in:)` in `MIDIFeedback.swift` (F3, F4; D5; R2-R4, R9, R11)
- [ ] MIDI-009-T06 [US1] Package tests `Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIFeedbackTests.swift`: one change → one CC; inverted curve ends (min → 127, max → 0); every 7-bit code round-trips through value and back for each preset curve, inverted or not; flat piecewise keeps the known code; 14-bit sends MSB then LSB; no `fb=1` → nothing; routing pairs by device and virtual name; UMP words (S1, S5)
- [ ] MIDI-009-T07 [US1] App: `MIDIInputCoordinator` tick observers (`Apps/projectM-iOS/Coordinators/MIDIInputCoordinator.swift`); engine, output and `feedbackValues` properties and `receive` hooks in `MIDIMappingCoordinator.swift`; `feedbackTick()` in new `MIDIMappingCoordinator+Feedback.swift`; `feedbackValues` and the CoreMIDI output (recording under `-uitestFakeMIDI`) wired in `AppCoordinator.swift` (F6; D7; R2, R9, R10)
- [ ] MIDI-009-T08 [US1] App test `Apps/projectM-iOS/Tests/MIDIFeedbackCoordinatorTests.swift`: a feedback mapping with a scripted paired destination; a base value change reaches the mock destination once; no paired destination → nothing (S7)

## Phase 4: User Story 2 - Feedback never floods or loops (P1)

- [ ] MIDI-009-T09 [US2] Engine bounds and loop prevention: per-control 1/30 s interval with coalescing, at most 16 messages per tick round-robin, `incomingApplied` (known code, 100 ms window), `filterEchoes` (once per sent byte), `absorb` (panic) in `MIDIFeedback.swift` (D3, D4; R4-R8, R10)
- [ ] MIDI-009-T10 [US2] Package tests: 1000 changes in 1 s → at most 31 messages for the control and the last carries the final value; a value applied from the controller is not echoed; loopback (output fed back through `filterEchoes` and `MIDIBindingValues` into the engine) sends at most one message per change and nothing over 3000 further ticks; per-tick cap with 64 controls; echoed bytes dropped once (S2, S3, S4)
- [ ] MIDI-009-T11 [US2] App test: controller input on a feedback mapping is not echoed; an echo of a sent value does not change the live value; panic drops pending feedback (S3; R7, R8, R10)

## Phase 5: User Story 3 - Turn feedback on for one mapping (P2)

- [ ] MIDI-009-T12 [US3] `setFeedback(_:for:)` (saves at once, announces "<name> feedback on." / "… off." on `.midi`, no Undo); "Send feedback" switch (`midiFeedback`) in `Apps/projectM-iOS/Views/MIDIMappingOptionsView.swift`; `MIDIMappingCoordinator+Feedback.swift` added to `scripts/check_status_events.py` (F6; R12)
- [ ] MIDI-009-T13 [US3] Tests: package option segment order, summary and profile document round trip (S6); app switch saves, announces, adds no Undo step; UI test `Apps/projectM-iOS/UITests/MIDIFeedbackUITests.swift` (seeded mapping, switch on, row reads "Linear, feedback"; under 30 s) (S7; R1, R12)

## Phase 6: Polish

- [ ] MIDI-009-T14 ADR-0080 (`docs/adr/0080-midi-feedback-output.md`); repository checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`), `check_privacy_manifest.py` and `check_network_symbols` on the Debug app, type-check budget flags, `LibraryBackupAppTests` and `SettingsTests` (no new key), existing MIDI suites; PosterBoard count after; delete the simulator and derived data
- [ ] MIDI-009-T15 `{device}` On D1 with a physical controller with motorised faders or LED rings (quickstart step 5): the ring or fader follows on-screen changes; moving the control causes no jitter or runaway messages

## Dependencies

T01 → T02-T04 → US1 (T05-T08) → US2 (T09-T11) → US3 (T12-T13) → T14; T15 last, by a person. T02, T03 and T04 touch
different files ([P]); T06 and T10 share the test file.

## Implementation strategy

MVP is US1 (one correct CC per change on a mock output); US2 makes it safe (the row's acceptance); US3 is the switch.
