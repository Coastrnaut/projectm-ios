# Tasks: PRE-011 Preset Notes

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/notes-file.md](contracts/notes-file.md), [quickstart.md](quickstart.md)

Tests are requested by the roadmap acceptance ("Notes survive relaunch and never appear in exported diagnostics").
Budgets (owner rule 7): unit tests 1-2 s, suites under 1 minute, the UI test under 30 s.

## Phase 1: Setup

- [X] PRE-011-T01 Create the simulator "PRE11 iPhone 17" (iOS 27.2), run `xcodegen generate`, init the preset submodules if missing, and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` (worktree root) — Verified 2026-11-14: simulator "PRE11 iPhone 17" (iOS 27.2) created, `xcodegen generate` exit 0, presets initialised, PosterBoard reports 26 before

## Phase 2: Foundational (notes model, file and store)

- [X] PRE-011-T02 Add `PresetNoteMap` with "preset ID (1-512 UTF-8 bytes) → trimmed text, 1-2,000 characters; at most 20,000 entries", `set`/`remove`/`note(for:)`/`presetIDs(containing:)`/`repaired(_:)` and `PresetNoteError` in Packages/PresetLibrary/Sources/PresetLibrary/Notes/PresetNoteMap.swift — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary --filter PresetNoteTests` (8 tests pass)
- [X] PRE-011-T03 Add `PresetNotesFile` (schema `org.projectmios.preset-notes`, versions 0-1, 8 MiB, depth 3, strings up to 64 KiB, 20,000 elements; migration table; newer → `newerVersion`; lenient body; stable encoding) in Packages/PresetLibrary/Sources/PresetLibrary/Notes/PresetNotesFile.swift — Verified 2026-11-14: PresetNoteTests (lenient repair, newer version, unreadable, migration, 50 KB emoji note within the schema)
- [X] PRE-011-T04 Add `PresetNoteStore` (atomic transactions, newer format unavailable, unreadable set aside as `notes.unreadable.json`, migration with the original kept until saved, load notice) in Packages/PresetLibrary/Sources/PresetLibrary/Notes/PresetNoteStore.swift — Verified 2026-11-14: PresetNoteTests testANoteSurvivesRelaunch, testAFailedSaveChangesNothing, testUnreadableFileIsSetAside
- [X] PRE-011-T05 Package tests: relaunch (a new store on the same folder reads the note), trimming, empty removes, 2,000-character limit, lenient repair, newer version untouched, unreadable set aside, injected migration from version 0, failed save changes nothing, folded search in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetNoteTests.swift — Verified 2026-11-14: PresetLibrary suite 346 tests pass, 0 failures (34 s)

## Phase 3: User Story 1 — Write a note about a preset (P1, MVP)

**Independent test**: a note saved in the app survives a new coordinator on the same folder; the UI test adds a note and sees the row indicator.

- [X] PRE-011-T06 [US1] Add the notes store to `PresetCoordinator` (init parameter `notes:`, `notesVersion`, `notesMessage`) and create it in `AppCoordinator` at `PresetNoteStore.defaultDirectory()` in Apps/projectM-iOS/Coordinators/PresetCoordinator.swift and Apps/projectM-iOS/Coordinators/AppCoordinator.swift — Verified 2026-11-14: PresetNoteAppTests testANoteSurvivesRelaunch on "PRE11 iPhone 17"
- [X] PRE-011-T07 [US1] Add `note(of:)`, `hasNote(_:)`, `saveNote(_:for:)` (announces "Note saved for <name>." / "Note removed from <name>." on the library lane), `pruneNote(_:)`, the load notice ("Some notes could not be read and were removed." / "Your notes could not be read and were set aside.") shown once as the browser's notes message, the ", has note" row-label suffix and note matches in `searchResults` in Apps/projectM-iOS/Coordinators/PresetCoordinator+Notes.swift (hooks in PresetCoordinator.swift `rowLabel` and PresetCoordinator+Tags.swift `searchResults`) — Verified 2026-11-14: PresetNoteAppTests (announcements, row label, notice, search: testSearchFindsAPresetByItsNote)
- [X] PRE-011-T08 [US1] Add `PresetNoteView` (TextEditor limited to 2,000 characters, label "Note", count "n of 2,000", Save, Cancel, Delete Note, message, swipe-dismiss disabled while unsaved) in Apps/projectM-iOS/Views/PresetNoteView.swift and the row's "Note…" menu item, "Note" VoiceOver action and `note.text` indicator in Apps/projectM-iOS/Views/PresetBrowserView.swift — Verified 2026-11-14: PresetNoteUITests testAddingANoteShowsItOnTheRow (18.0 s)
- [X] PRE-011-T09 [US1] Remove a user preset's note when the preset is removed in Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift — Verified 2026-11-14: code review of UserPresetsCoordinator.remove (pruneNote beside pruneTags and overrides prune); the prune path is tested by testADanglingNoteIsListedAndItsSafeFixRemovesIt
- [X] PRE-011-T10 [US1] UI test: add a note through the row menu, see the indicator, reopen and see the text in Apps/projectM-iOS/UITests/PresetNoteUITests.swift — Verified 2026-11-14: PresetNoteUITests passes in 18.0 s on iOS 27.2

## Phase 4: User Story 2 — Notes stay private (P1)

**Independent test**: diagnostics exported with marker notes present contain no marker; the compliance rule refuses a diagnostics source naming the notes store.

- [X] PRE-011-T11 [US2] Add the PRE-011 rule to scripts/check_compliance.py (no `PresetNote`, `noteStore` or `notes.json` in Packages/Diagnostics, Apps/CaptureLab, Apps/projectM-iOS/Automation and the PERF-012 report sources) with a test in scripts/test_scripts.py — Verified 2026-11-14: `python3 scripts/check_compliance.py` OK; ComplianceNotesPrivacyTests (2) pass; `scripts/test_scripts.py` 179 tests OK
- [X] PRE-011-T12 [US2] App tests: relaunch through a new `PresetCoordinator` on the same folder; with marker notes saved, the PERF-012 report (the Export button's gathering path) and a `DiagnosticsExporter`-encoded snapshot with the app's frame timings contain no marker or noted preset ID; search finds a preset by its note in Apps/projectM-iOS/Tests/PresetNoteAppTests.swift — Verified 2026-11-14: PresetNoteAppTests testDiagnosticsExportsNeverContainNotes and testANoteSurvivesRelaunch pass (5 app tests, 0.016 s)

## Phase 5: User Story 3 — Notes are kept safely (P2)

**Independent test**: backup round trip, restore merge by choice, erase count and removal; PRE-018 dangling note.

- [X] PRE-011-T13 [US3] Back up, read, record, restore-merge and erase-count notes (`collections/notes.json`, digest `preset-notes`) in Packages/LibraryBackup/Sources/LibraryBackup/{LibraryFolders,LibraryContents,LibraryBackupFormat,LibraryBackupArchive,LibraryRecords,LibraryRestorePlan,LibraryRestoreInstaller,LibraryEraseInventory}.swift — Verified 2026-11-14: `swift test --package-path Packages/LibraryBackup` 86 tests pass (32 s)
- [X] PRE-011-T14 [US3] LibraryBackup tests: round trip, merge by choice, erase removes and counts in Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupNoteTests.swift — Verified 2026-11-14: LibraryBackupNoteTests (3) pass
- [X] PRE-011-T15 [US3] PRE-018: `PresetReferenceStore.notes` ("Notes", "Remove Note"), `PresetReferenceSnapshot.notes`, scanned after overrides; app snapshot and safe fix in Packages/PresetLibrary/Sources/PresetLibrary/Integrity/ and Apps/projectM-iOS/Coordinators/PresetCoordinator+Integrity.swift; update Packages/PresetLibrary/Tests/PresetLibraryTests/PresetIntegrityTests.swift and Apps/projectM-iOS/Tests/LibraryIntegrityAcceptanceTests.swift — Verified 2026-11-14: PresetIntegrityTests (package) and LibraryIntegrityAcceptanceTests (app, 9 problems, "Removed 6 broken references") pass

## Phase 6: Polish

- [X] PRE-011-T16 Run the repo checks (compliance, docs, motion policy, permission catalog, status events, script tests, privacy manifest, network symbols), `LibraryBackupAppTests`, the type-check budget, and record the spec status; delete the simulator and derived data — Verified 2026-11-14: compliance, validate_docs, motion policy, permission catalog, status events, 179 script tests, check_privacy_manifest and check_network_symbols on the Debug app all OK; LibraryBackupAppTests 5 pass; type-check flags show no warning in the new files

## Dependencies

T01 → T02-T05 → (US1 T06-T10, US2 T11-T12, US3 T13-T15 in any order; T12 needs T06) → T16.
Parallel: T11 and T13-T14 are independent of the app work; T02-T04 are separate files.

## Implementation strategy

MVP = Phase 2 + US1. US2 closes the acceptance; US3 keeps notes in backups and the library check.
