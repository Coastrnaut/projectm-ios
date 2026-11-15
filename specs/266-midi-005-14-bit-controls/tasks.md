# Tasks: MIDI-005 MIDI 14-bit Controls

**Input**: `specs/266-midi-005-14-bit-controls/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MIDI-005-S1 to S7). Budgets (owner rule 7): unit tests about 1-2 s (≤ 10 s), package
suite under 1 minute, UI test under 30 s, each xcodebuild run under 10 minutes. `{device}` tasks stay open until a
person runs them.

## Phase 1: Setup

- [ ] MIDI-005-T01 Run `xcodegen generate`, initialize the preset submodules if missing (the `Build` symlink is in place), create the simulator "MIDI5 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run

## Phase 2: Foundational (blocks every story)

- [ ] MIDI-005-T02 `MIDIHighResolution`, `MIDIHighResolutionTracker` and `MIDIHighResolutionLearnWatch` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIHighResolution.swift` (contract H1, H4; research MIDI-005-D2-D4; R1-R3, R9)
- [ ] MIDI-005-T03 `MIDIMappingOptions.highResolution` (`hires=1`, segment order, summary) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIMappingOptions.swift`; `MIDIControlBinding.isHighResolution` in `MIDIControlBinding.swift` (H2; D1; R7, R10)
- [ ] MIDI-005-T04 Stateful `MIDIBindingValues.values(…, tracker:)` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIBindingValues.swift` (H3; R1, R2, R4)

## Phase 3: User Story 1 - A 14-bit knob drives a parameter smoothly (P1) — MVP

**Independent test**: coarse/fine pairs on a 14-bit mapping give (MSB × 128 + LSB) / 16383, and the live parameter takes values between two 7-bit steps.

- [ ] MIDI-005-T05 [US1] Package tests `Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIHighResolutionTests.swift`: 0x40/0x00 → 8192/16383, 0x7F/0x7F → 1, 0/0 → 0, coarse then several fine, a new coarse resets the fine part, fine before coarse, other channel ignored, 7-bit fallback, curve and Invert on the 14-bit value, a flag on controller ≥ 32 ignored, `hires=1` segment order and the ", 14-bit" summary, the 7-bit overload unchanged; the suite builds without Apple-only APIs (Linux CI) (S1, S2, S3; R1-R4, R7, R9, R10)
- [ ] MIDI-005-T06 [US1] Coordinator wiring: tracker and watch properties, the stateful values call in `receive` in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator.swift` (R1-R4)
- [ ] MIDI-005-T07 [US1] App test `Apps/projectM-iOS/Tests/MIDIHighResolutionCoordinatorTests.swift`: a seeded 14-bit mapping driven by the stand-in MIDI source sets Glow intensity between two 7-bit steps; a coarse-only controller reaches both ends (S3, S6)

## Phase 4: User Story 2 - Learn recognizes a 14-bit control (P1)

- [ ] MIDI-005-T08 [US2] `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+HighResolution.swift` (new): arm the watch on bind, `detectHighResolution(in:)` sets the flag, status and `.midi` announcement; the file added to `scripts/check_status_events.py` (D4, D5; R5)
- [ ] MIDI-005-T09 [US2] Tests: package learn-watch cases (same batch, within 500 ms, after 500 ms, other channel, controller ≥ 32); app: CC 7 + CC 39 in the learning batch and in a later batch store `hires=1`, CC 7 alone stays 7-bit (S4; R5)

## Phase 5: User Story 3 - Set or clear 14-bit by hand (P2)

- [ ] MIDI-005-T10 [US3] `setHighResolution(_:for:)` and `canUseHighResolution(for:)`; `MIDIHighResolutionSection` in `Apps/projectM-iOS/Views/MIDIMappingOptionsView.swift` (H5; R6)
- [ ] MIDI-005-T11 [US3] App test: the switch saves `hires=1` at once, announces, adds no Undo step, and is unavailable on CC ≥ 32; UI test `Apps/projectM-iOS/UITests/MIDIHighResolutionUITests.swift` (seeded mapping, turn the switch on, row reads "Linear, 14-bit"; under 30 s) (S7; R6, R10)

## Phase 6: Polish

- [ ] MIDI-005-T12 Profiles: package test that lines with and without `hires=1` round-trip through `MIDIProfileDocument` byte for byte and classify as controls; existing `MIDIProfileTests`, `MIDICCScalingTests`, `MIDILearnTests` and the app MIDI coordinator suites still pass (S5; R7, R8)
- [ ] MIDI-005-T13 Repository checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`), `check_privacy_manifest.py` and `check_network_symbols` on the Debug app, type-check budget flags, `LibraryBackupAppTests` and `SettingsTests` (no new key), PosterBoard count after the runs; delete the simulator and derived data
- [ ] MIDI-005-T14 `{device}` On D1 with a physical 14-bit controller (quickstart step 4): learn detects the pair and a slow move has no visible steps

## Dependencies

T01 → T02-T04 → US1 (T05-T07) → US2 (T08-T09) → US3 (T10-T11) → T12-T13; T14 last, by a person.
