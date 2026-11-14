# Tasks: MIDI-012 MIDI Mapping Profiles

**Input**: `specs/171-midi-012-profiles/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MIDI-012-S1 to S6). Budgets (owner rule 7): unit tests about 1-2 s (≤ 10 s), package
suite under 1 minute, UI test under 30 s, each xcodebuild run under 10 minutes. `{device}` tasks stay open until a
person runs them.

## Phase 1: Setup

- [ ] MIDI-012-T01 Run `xcodegen generate`, initialize the preset submodules if missing (the `Build` symlink is in place), create the simulator "MIDI12 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run

## Phase 2: Foundational (blocks every story)

- [ ] MIDI-012-T02 `MIDIProfile` (id, name "1-60 characters", lines "≤ 512 lines, each ≤ 256 UTF-8 bytes, no control characters", `link: Int32?`), `MIDIProfileLimits`, `MIDIMappingLineKind.classify`, `MIDIProfileDocument` (format `org.projectmios.midi-profile`, version 1; decode errors per contract P1) and `MIDIProfileReport` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIProfile.swift` (research MIDI-012-D1-D4)
- [ ] MIDI-012-T03 `MIDIProfileList` ("≤ 32 profiles", unique names, "Profile <n>", rename, delete, link, in use, suggestion), `MIDIProfileStoreFile` codec (format `org.projectmios.midi-profiles`, version 1, ≤ 4 MB) and `MIDIProfileFileStore` (atomic write; unreadable or newer file never overwritten) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIProfileStore.swift` (D5, D8)
- [ ] MIDI-012-T04 `MIDIMappingCoordinator`: `otherLines` kept after known lines on save, `storedLines`, `replaceLines(_:announcement:)` (verbatim write, reload, held keys released, learn cancelled, one Undo step), Undo as a stored-line snapshot, `linkableInputs` in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator.swift` (D6, D9; R6, R7)

## Phase 3: User Story 1 - Save, export, import and apply without losing anything (P1) — MVP

**Independent test**: the every-kind fixture survives save → reload → export → import → apply byte-identical and ordered.

- [ ] MIDI-012-T05 [US1] Package tests `Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIProfileTests.swift`: every-kind fixture (channels 1 and 16, controller 119 with options, `note:` with `mode=hold`, `ccbtn:`, `rt:start`/`rt:stop`, `pc:` scene lines, position mode, two unknown lines, a non-ASCII scene ID) through store file and document, UTF-8 identical and ordered; report counts (S1, R11)
- [ ] MIDI-012-T06 [US1] `MIDIProfilesCoordinator` (rows, save current, apply, rename, delete, link, export to a temporary `.pmmidi` and clean-up, bounded import, messages and `.midi` announcements) in `Apps/projectM-iOS/Coordinators/MIDIProfilesCoordinator.swift`; created in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (one line) with the UI-test reset removing the folder (R2, R4-R6)
- [ ] MIDI-012-T07 [US1] App tests `Apps/projectM-iOS/Tests/MIDIProfilesCoordinatorTests.swift`: save → export file → import → apply leaves `settings.midi.mappings` UTF-8 identical and ordered and the CC, trigger and scene lists loaded; import never applies; unknown lines survive a later learn (S1, R7)

## Phase 4: User Story 2 - Switch between controllers (P1)

- [ ] MIDI-012-T08 [US2] `MIDIProfilesSection` (Save Current, Import…, rows with Apply and a More menu: Rename…, Export…, Link, Delete…; suggestion row; message; rename alert; delete confirmation; file mover and importer) in `Apps/projectM-iOS/Views/MIDIProfilesSection.swift`, placed in `Apps/projectM-iOS/Views/MIDIMappingsView.swift` after the status section (R8, R10, R12)
- [ ] MIDI-012-T09 [US2] App tests in `Apps/projectM-iOS/Tests/MIDIProfilesCoordinatorTests.swift`: apply is one Undo step restoring the previous list exactly and is announced on the `.midi` lane; a linked listed input is suggested and nothing applies by itself; fallback IDs are not linkable (S3, R6, R8)
- [ ] MIDI-012-T10 [US2] UI test `Apps/projectM-iOS/UITests/MIDIProfilesUITests.swift`: Save, change the mappings, Save, Apply the first, Undo, under 30 s (S5)

## Phase 5: User Story 3 - Bad files are refused safely (P1)

- [ ] MIDI-012-T11 [US3] Package tests in `MIDIProfileTests.swift`: empty, not JSON, wrong format, newer version, missing name, missing lines, non-string line, too many lines, line too long, control character, over 128 KB; store file corrupt and newer; app test: a refused import changes nothing and an unreadable store is not overwritten (S2, R3, R5)

## Phase 6: User Story 4 - Manage profiles (P2)

- [ ] MIDI-012-T12 [US4] Package and app tests: rename (trim, control characters removed, 60 characters, empty keeps the old name, unique), delete, 32-profile limit message, duplicate import named "(2)" and reported "Same mappings as …", row accessibility labels (R2, R3, R12)

## Phase 7: Polish

- [ ] MIDI-012-T13 FILE-005/011: `LibraryErasePolicy.midiProfilesFolderName` in `folders(.settings)` and its inventory count in `Packages/LibraryBackup/Sources/LibraryBackup/LibraryErasePolicy.swift` and `LibraryEraseInventory.swift`; app test that the backup omits the file, the Settings erase removes it and the folder name agrees with the store (S4, R9)
- [ ] MIDI-012-T14 Re-run the package suite, the existing MIDI app tests and `MIDILearnUITests`; type-check budget on touched files; repository checks (compliance, docs, motion policy, permission catalog, status events, script tests, privacy manifest, network symbols); PosterBoard count; delete the simulator and derived data (S6)
- [ ] MIDI-012-T15 {device} On D1 with a controller: save a profile, export it to Files, import it on D2, apply it, move each mapped control once

## Dependencies

T01 → T02, T03 → T04 → US1 (T05-T07) → US2 (T08-T10) → US3 (T11) → US4 (T12) → T13 → T14 → T15.

## Parallel examples

- T02/T03 (package) and T04 (app coordinator) touch different files.
- T11 and T12 tests can be written while T08's UI builds.

## Implementation strategy

MVP is US1 (the row's acceptance in package and app). US2 adds the UI and Undo; US3 and US4 harden imports and
management.
