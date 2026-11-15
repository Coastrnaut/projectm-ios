# Tasks: SHOW-012 Cue Annotations

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/show-cue-note.md](contracts/show-cue-note.md), [quickstart.md](quickstart.md)

## Phase 1: Foundation (model and file)

- [ ] SHOW-012-T01 `ShowCueNote` rules (500 characters, line feeds kept, other Cc removed, trimmed; `normalized`, `stored`) in Packages/ShowControl/Sources/ShowControl/ShowCueNote.swift (R1; research D3)
- [ ] SHOW-012-T02 `ShowCue.operatorNote`, `ShowCueList.setOperatorNote`, `insert(…, operatorNote:)`, `ShowEditError.invalidNote`, normalized-note check in `init(id:name:cues:position:)` in Packages/ShowControl/Sources/ShowControl/ShowCueList.swift (R1, R10; data-model)
- [ ] SHOW-012-T03 `show.json` cue key `note` (written only when set; lenient read; `droppedNotes`, `shortenedNotes` warnings) in Packages/ShowControl/Sources/ShowControl/ShowDocument.swift (R2, R3; contract N1-N3)
- [ ] SHOW-012-T04 Package tests: rules, set/clear/too long, encode/decode byte-identical, missing → nil, older file bytes unchanged, lenient read warnings, store save/load round trip in Packages/ShowControl/Tests/ShowControlTests/ShowCueNoteTests.swift (R1-R4; S1)
- [ ] SHOW-012-T05 Backup round trip: notes byte-identical through a FILE-005 archive write/read in Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupCueNoteTests.swift (R4, contract N5; S1)

## Phase 2: User Story 1 — write a note (P1)

- [ ] SHOW-012-T06 [US1] `ShowCoordinator.setOperatorNote` (refused while locked, saves, applies nothing, no countdown restart) and Duplicate Scene passes the note in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift (R6, R7, R10)
- [ ] SHOW-012-T07 [US1] `CueNoteView` sheet (TextEditor, "n / 500" counter, Save disabled over the limit, Remove Note) in Apps/projectM-iOS/Views/CueNoteView.swift (R5; Clarifications)
- [ ] SHOW-012-T08 [US1] Show editor: note line (icon + first line ≤ 60 characters), Add/Edit Note… in More… dialog, context menu and VoiceOver actions (hidden while locked), ", note <text>" in the row value in Apps/projectM-iOS/Views/ShowEditorView.swift (R5, R7, R8)
- [ ] SHOW-012-T09 [US1] App tests: set, clear, refused while locked (lock message, unchanged), saved and reloaded, Duplicate Scene copies, no scene applied in Apps/projectM-iOS/Tests/CueNoteAcceptanceTests.swift (R6, R7, R10; S4)
- [ ] SHOW-012-T10 [US1] UI test: More… → Add Note…, type, Save, row shows the note in Apps/projectM-iOS/UITests/CueNoteUITests.swift (R5; S3)

## Phase 3: User Story 3 — never in live output (P1)

- [ ] SHOW-012-T11 [US3] Acceptance "do not appear in live output": a distinctive note on the applied cue appears in none of the external display's view tree, HUD texts, transport readout, status text, announcements, notice, applied scene bytes and text overlay, OSC send datagrams in Apps/projectM-iOS/Tests/CueNoteAcceptanceTests.swift (R9; S2; research D7)
- [ ] SHOW-012-T12 [US3] Compliance rule SHOW-012-R11 (`operatorNote`/`ShowCueNote` allowed only in the show model, editor, `ShowCoordinator` and tests) and its script test in scripts/check_compliance.py, scripts/test_scripts.py (R11; research D6)

## Phase 4: Polish

- [ ] SHOW-012-T13 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget, LibraryBackupAppTests and SettingsTests (no new keys)
- [ ] SHOW-012-T14 {device} On D1 with an external display: add a note, step to its cue; nothing of the note on the external display or in a short recording; VoiceOver reads it on the row (quickstart 6)

## Dependencies

T01 → T02 → T03 → T04, T05; T02 → T06 → T07, T08 → T09, T10, T11; T12 independent; T13 last; T14 needs a device.
User Story 2 (export) is covered by T03-T05 (no app code).
