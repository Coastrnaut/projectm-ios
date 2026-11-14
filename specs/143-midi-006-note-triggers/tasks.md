# Tasks: MIDI-006 MIDI Note Triggers

**Input**: `specs/143-midi-006-note-triggers/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MIDI-006-S1 to S6). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, UI test under 30 s, each xcodebuild run under 10 minutes.
`{device}` tasks are the final device stage and stay open until a person runs them.

## Phase 1: Setup

- [ ] MIDI-006-T01 Run `xcodegen generate`, initialize the preset submodules and the `Build` symlink if missing, create the simulator "MIDI6 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run

## Phase 2: Foundational (blocks every story)

- [ ] MIDI-006-T02 [P] `MIDINoteEdge` and `MIDIEvent.noteEdge` ("`.on` iff kind `.noteOn` and value > 0; `.off` iff kind `.noteOff`, or `.noteOn` with value 0") in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIEvent.swift` (research MIDI-006-D1, contract N1)
- [ ] MIDI-006-T03 [P] `MIDINoteAction`, `MIDINoteMode`, `MIDINoteTarget`, `MIDINoteBinding` (line `note:<ch 0-15>:<note 0-127>=<action>[;mode=hold][;extra…]`) and `MIDINoteBindingList` (≤ 64, one key per target and one target per key, unreadable `note:` lines kept) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDINoteBinding.swift` (research MIDI-006-D4, contract N2)
- [ ] MIDI-006-T04 `MIDINoteRouter` and `MIDINoteCommand` (fire / engage / release; edge-only; one fire per binding per batch; CC 120/123 and System Reset; `releaseAll`, `release(keys:)`) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDINoteRouter.swift` (research MIDI-006-D2, D3, contract N3)

## Phase 3: User Story 1 - A pad steps to the next cue, however my controller sends note-off (P1) — MVP

**Independent test**: the three equivalent sequences give identical event streams and identical commands.

- [ ] MIDI-006-T05 [US1] Package tests `Packages/PerformanceControl/Tests/PerformanceControlTests/MIDINoteTriggerTests.swift`: noteEdge cases; byte parser and UMP decoder equivalence of (on v>0, on v=0), (on v>0, off), (on v>0, running-status v=0) with a clock byte inside; router commands identical for trigger and hold bindings across the three; channel filtering; codec round-trip, mixed `cc:` + `note:` lists (CC lines unchanged), unknown lines kept; host and the Linux shape (S1, S3)
- [ ] MIDI-006-T06 [US1] Coordinator note state in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator.swift` and `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+Notes.swift`: load and save `note:` lines after `cc:` lines, route batches through the router to `noteActions`, input client while note bindings exist (contract N4)
- [ ] MIDI-006-T07 [US1] `MIDINoteActionPerformer` in `Apps/projectM-iOS/Coordinators/MIDINoteActionPerformer.swift` and one wiring line in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (research MIDI-006-D5)
- [ ] MIDI-006-T08 [US1] App test `Apps/projectM-iOS/Tests/MIDINoteTriggerCoordinatorTests.swift`: fake MIDI source (scripted input + `drain()`), Next cue fires once per press for each of the three sequences; storage beside a CC line (S4)

## Phase 4: User Story 2 - Black out while I hold a key (P1)

- [ ] MIDI-006-T09 [US2] Package tests in `MIDINoteTriggerTests.swift`: repeated note on does not re-engage or re-fire; one fire per batch; panic per channel; System Reset; `releaseAll` (S2)
- [ ] MIDI-006-T10 [US2] Coordinator release of held notes when the input stops, when listed sources shrink, and when a held binding is deleted or replaced, in `MIDIMappingCoordinator+Notes.swift`
- [ ] MIDI-006-T11 [US2] App tests in `MIDINoteTriggerCoordinatorTests.swift`: hold mapping engages and releases (velocity 0 and note off), repeated note on changes nothing, stuck key released on listening off and on unplug; performer black-out bookkeeping (restore only what the hold did) (S2, S4)

## Phase 5: User Story 3 - Learn a note (P2)

- [ ] MIDI-006-T12 [US3] `MIDILearnSession.handle(_:now:isEligible:)` and `MIDILearnEligibility.isNoteEligible(_:)` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDILearnSession.swift`; package test that CC learn ignores notes and note learn ignores CCs and velocity-0
- [ ] MIDI-006-T13 [US3] Note learn in the coordinator (one session at a time, Cancel, timeout, Undo for both lists, `.midi` announcements, `noteRows`) and the "Note triggers" section in `Apps/projectM-iOS/Views/MIDIMappingsView.swift` (identifiers `midiNote.<id>`, `midiNoteLearn.<id>`, `midiNoteDelete.<id>`); app tests for learn (the learning press fires nothing; a note already used moves, research MIDI-006-D2), announcement and Undo
- [ ] MIDI-006-T14 [US3] UI test `Apps/projectM-iOS/UITests/MIDINoteTriggersUITests.swift`: learn note C4 to Next cue with the stand-in input in under 30 s (S5)

## Phase 6: Polish

- [ ] MIDI-006-T15 Repository checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the built Debug app, type-check budget flags on touched files; PosterBoard count after; delete the simulator, derived data and the `Build` symlink (S6)
- [ ] MIDI-006-T16 `{device}` With a physical controller on D1: map a pad to Next cue and a key to Black out while held; confirm one step per press (including a controller that sends velocity-0 note on) and black only while held

## Dependencies

T01 → T02, T03 (parallel) → T04 → US1 (T05-T08) → US2 (T09-T11) → US3 (T12-T14) → T15 → T16. US2 and US3
depend only on the foundation and US1's coordinator state (T06).

## Parallel examples

- T02 and T03 (different files).
- T05 (package tests) alongside T07 (app performer).

## Implementation strategy

MVP is US1 (the row's acceptance). US2 adds the note-off half; US3 the learn UI. Commit after each phase.
