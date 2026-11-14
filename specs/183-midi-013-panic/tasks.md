# Tasks: MIDI-013 MIDI Panic

**Input**: `specs/183-midi-013-panic/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MIDI-013-S1 to S6). Budgets (owner rule 7): unit tests about 1-2 s (≤ 10 s), package
suite under 1 minute, UI test under 30 s, each xcodebuild run under 10 minutes. `{device}` tasks stay open until a
person runs them.

## Phase 1: Setup

- [ ] MIDI-013-T01 Run `xcodegen generate`, initialize the preset submodules if missing (the `Build` symlink is in place), create the simulator "MIDI13 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run

## Phase 2: Foundational (blocks every story)

- [ ] MIDI-013-T02 `MIDIPressFilter.reset()` and `isEmpty` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIPressFilter.swift`; `MIDINoteRouter.panic(bindings:)` and `isIdle` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDINoteRouter.swift` (research MIDI-013-D1; R1, R2, R10)
- [ ] MIDI-013-T03 `MIDIInputCoordinator.discardPending()` in `Apps/projectM-iOS/Coordinators/MIDIInputCoordinator.swift` (D2; R3)
- [ ] MIDI-013-T04 `MIDIMappingCoordinator.panic()` and `panicText` in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+Panic.swift` (learn cancelled, queue dropped, releases through `performNotes`, status and `.midi` announcement, nothing stored); the file added to `scripts/check_status_events.py` (D3; R1, R3-R6, R9)

## Phase 3: User Story 1 - Clear a stuck controller in one action (P1) — MVP

**Independent test**: three held notes (one hold blackout), a held CC button and a learn session → panic → zero gates, empty press rule, blackout restored, learn cancelled, stored lines byte-identical, later presses fire.

- [ ] MIDI-013-T05 [US1] Package tests `Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIPanicTests.swift`: held notes and a CC button released, hold commands ordered, filter empty, a press inside the old 30 ms window fires after panic, a late note-off is ignored (S1, S3, R10)
- [ ] MIDI-013-T06 [US1] App acceptance test `Apps/projectM-iOS/Tests/MIDIPanicCoordinatorTests.swift` through the stand-in source system (`ScriptedMIDISourceSystem`): the independent test above, plus queued input dropped, live CC values and listening unchanged, the current scene untouched (no scene command) and the `.midi` announcement (S1, S2, S3; R1-R6)

## Phase 4: User Story 2 - Panic from the keyboard, VoiceOver or a controller (P1)

- [ ] MIDI-013-T07 [US2] `MIDINoteAction.panic` / `MIDINoteTarget.panic` (`midi.panic`, trigger only, last Transport row) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDINoteBinding.swift`; the router step runs panic on its `.fire` in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+Notes.swift`; `MIDINoteActionPerformer` ignores it (D4; R8)
- [ ] MIDI-013-T08 [US2] `Apps/projectM-iOS/Views/MIDIPanicControls.swift` (`MIDIPanicShortcut` ⌘⇧M, `MIDIPanicButton`, `MIDIPanicKeyCommand`); button in `Apps/projectM-iOS/Views/MIDISettingsSection.swift`; key command and VoiceOver action in `Apps/projectM-iOS/Views/VisualizerView.swift` (D5; R7)
- [ ] MIDI-013-T09 [US2] Tests: package line round trip for `midi.panic` (and `;mode=hold` unreadable, kept verbatim); app tests for a `midi.panic` binding (commands before it performed, later ones dropped) and the shortcut constants (R7, R8)
- [ ] MIDI-013-T10 [US2] DEBUG probe `UITestFakeMIDIPanicProbe` (`midiFakeHoldNote`, `midiHeldProbe`) in `Apps/projectM-iOS/Debug/UITestFakeMIDI.swift`, shown in the MIDI section; UI test `Apps/projectM-iOS/UITests/MIDIPanicUITests.swift`: Hold Note → 1 held, MIDI Panic → 0 held, Hold Note → 1 held, ⌘⇧M → 0 held, under 30 s (S5)

## Phase 5: User Story 3 - Panic while idle changes nothing (P2)

- [ ] MIDI-013-T11 [US3] Package and app tests: panic while idle returns no commands, performs no action, stores nothing and announces "MIDI reset" (S4, R9)

## Phase 6: Polish

- [ ] MIDI-013-T12 Run the touched package suite, the MIDI app suites and the UI test; the repository checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`), `check_privacy_manifest.py` on the Debug app and `scripts/check_network_symbols`; the Xcode 26 type-check budget flags; PosterBoard count after; delete the simulator and derived data (S6)
- [ ] MIDI-013-T13 `{device}` On D1 with a physical controller: hold a pad mapped to "Black out while held", press MIDI Panic, the output returns and the pad works again (quickstart step 4)

## Dependencies

T01 → T02 → T03, T04 → T05-T11 → T12. T07 changes `MIDINoteTarget.all` (MIDI-006's row-order test). T13 last.
