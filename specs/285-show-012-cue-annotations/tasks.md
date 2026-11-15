# Tasks: SHOW-012 Cue Annotations

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/show-cue-note.md](contracts/show-cue-note.md), [quickstart.md](quickstart.md)

## Phase 1: Foundation (model and file)

- [X] SHOW-012-T01 `ShowCueNote` rules (500 characters, line feeds kept, other Cc removed, trimmed; `normalized`, `stored`) in Packages/ShowControl/Sources/ShowControl/ShowCueNote.swift (R1; research D3) — Verified 2026-11-15: `ShowCueNoteTests` rule tests (cleaning, limit, preview) pass
- [X] SHOW-012-T02 `ShowCue.operatorNote`, `ShowCueList.setOperatorNote`, `insert(…, operatorNote:)`, `ShowEditError.invalidNote`, normalized-note check in `init(id:name:cues:position:)` in Packages/ShowControl/Sources/ShowControl/ShowCueList.swift (R1, R10; data-model) — Verified 2026-11-15: `testSetClearAndRefuseNotesWithoutTouchingTheRest`, `testInsertCarriesTheNoteAndMoveKeepsIt` pass
- [X] SHOW-012-T03 `show.json` cue key `note` (written only when set; lenient read; `droppedNotes`, `shortenedNotes` warnings) in Packages/ShowControl/Sources/ShowControl/ShowDocument.swift (R2, R3; contract N1-N3) — Verified 2026-11-15: `testNoteRoundTripsByteIdenticalAndMissingDecodesAsNil`, `testAShowWithoutNotesKeepsItsBytes`, `testLenientReadDropsNonTextAndShortensBadText` pass
- [X] SHOW-012-T04 Package tests: rules, set/clear/too long, encode/decode byte-identical, missing → nil, older file bytes unchanged, lenient read warnings, store save/load round trip in Packages/ShowControl/Tests/ShowControlTests/ShowCueNoteTests.swift (R1-R4; S1) — Verified 2026-11-15: `swift test --package-path Packages/ShowControl`: 173 tests, 0 failures (ShowCueNoteTests 10), 3.3 s
- [X] SHOW-012-T05 Backup round trip: notes byte-identical through a FILE-005 archive write/read in Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupCueNoteTests.swift (R4, contract N5; S1) — Verified 2026-11-15: `swift test --package-path Packages/LibraryBackup --filter LibraryBackupCueNoteTests|LibraryBackupNoteTests`: 4 pass, 0.12 s

## Phase 2: User Story 1 — write a note (P1)

- [X] SHOW-012-T06 [US1] `ShowCoordinator.setOperatorNote` (refused while locked, saves, applies nothing, no countdown restart) and Duplicate Scene passes the note in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift (R6, R7, R10) — Verified 2026-11-15: `CueNoteAcceptanceTests` (3 pass, 0.05 s) on "SHOW12 iPhone 17" (iOS 27.2): saved and reloaded, nothing applied, too-long refused, Duplicate Scene copies
- [X] SHOW-012-T07 [US1] `CueNoteView` sheet (TextEditor, "n / 500" counter, Save disabled over the limit, Remove Note) in Apps/projectM-iOS/Views/CueNoteView.swift (R5; Clarifications) — Verified 2026-11-15: `CueNoteUITests` (counter "17 of 500 characters", Save closes the sheet); build-for-testing with -warn-long-function-bodies=300 / -warn-long-expression-type-checking=150: no warnings in the new or edited files
- [X] SHOW-012-T08 [US1] Show editor: note line (icon + first line ≤ 60 characters), Add/Edit Note… in More… dialog, context menu and VoiceOver actions (hidden while locked), ", note <text>" in the row value in Apps/projectM-iOS/Views/ShowEditorView.swift (R5, R7, R8) — Verified 2026-11-15: `CueNoteUITests.testAddingANoteShowsTheIndicator` (20.9 s): More… → Add Note… → Save; the row reads ", note Wait for count-in"; regression UI tests CueTransitionOverride, CueTransition (2), ShowAutoAdvance pass
- [X] SHOW-012-T09 [US1] App tests: set, clear, refused while locked (lock message, unchanged), saved and reloaded, Duplicate Scene copies, no scene applied in Apps/projectM-iOS/Tests/CueNoteAcceptanceTests.swift (R6, R7, R10; S4) — Verified 2026-11-15: `testANoteIsSavedReloadedAndAppliesNothing`, `testTheLockRefusesNoteEditsAndDuplicateKeepsTheNote` pass; PerformanceLockAcceptanceTests (4), ShowCoordinatorTests, ShowSceneEditCoordinatorTests pass
- [X] SHOW-012-T10 [US1] UI test: More… → Add Note…, type, Save, row shows the note in Apps/projectM-iOS/UITests/CueNoteUITests.swift (R5; S3) — Verified 2026-11-15: `CueNoteUITests` 1 pass (20.9 s, under 30 s)

## Phase 3: User Story 3 — never in live output (P1)

- [X] SHOW-012-T11 [US3] Acceptance "do not appear in live output": a distinctive note on the applied cue appears in none of the external display's view tree, HUD texts, transport readout, status text, announcements, notice, applied scene bytes and text overlay, OSC send datagrams in Apps/projectM-iOS/Tests/CueNoteAcceptanceTests.swift (R9; S2; research D7) — Verified 2026-11-15: `testANoteNeverReachesLiveOutput` passes: the note string is in none of the HUD texts, status and transport readouts, notice, announcements, applied scene bytes, Text visual message, the 2 OSC datagrams (scene names on) or the external display window (slot holds only the visual)
- [X] SHOW-012-T12 [US3] Compliance rule SHOW-012-R11 (`operatorNote`/`ShowCueNote` allowed only in the show model, editor, `ShowCoordinator` and tests) and its script test in scripts/check_compliance.py, scripts/test_scripts.py (R11; research D6) — Verified 2026-11-15: `python3 scripts/check_compliance.py` OK; `python3 scripts/test_scripts.py` 181 tests OK (ComplianceCueNotesPrivacyTests 2)

## Phase 4: Polish

- [X] SHOW-012-T13 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget, LibraryBackupAppTests and SettingsTests (no new keys) — Verified 2026-11-15: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 181 OK; check_privacy_manifest and check_network_symbols OK on the Debug simulator app; LibraryBackupAppTests (5) and SettingsTests (9) pass; no new UserDefaults keys
- [ ] SHOW-012-T14 {device} On D1 with an external display: add a note, step to its cue; nothing of the note on the external display or in a short recording; VoiceOver reads it on the row (quickstart 6)

## Dependencies

T01 → T02 → T03 → T04, T05; T02 → T06 → T07, T08 → T09, T10, T11; T12 independent; T13 last; T14 needs a device.
User Story 2 (export) is covered by T03-T05 (no app code).
