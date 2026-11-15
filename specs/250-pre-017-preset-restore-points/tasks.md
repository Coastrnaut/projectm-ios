# Tasks: PRE-017 Preset Restore Points

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/restore-points.md](contracts/restore-points.md), [quickstart.md](quickstart.md)

Tests are requested by the roadmap acceptance ("Revert restores prior content and removes no unrelated files").
Budgets (owner rule 7): unit tests 1-2 s, suites under 1 minute, the UI test under 30 s.

## Phase 1: Setup

- [ ] PRE-017-T01 Create the simulator "PRE17 iPhone 17" (iOS 27.2), run `xcodegen generate`, init the preset submodules if missing, and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` (worktree root)

## Phase 2: Foundational (version model and list file)

- [ ] PRE-017-T02 Add `UserPresetVersion` (sha256 "64 lowercase hex", blobHash, byteCount "1…524,288", replacedAt, name), `UserPresetVersionLimits` (perPreset 10, total 500, totalBytes 50,000,000), `UserPresetHistoryFile` (schema 1, newer → `newerVersion`, encode/decode) and pure `adding`/`pruned`/`namedHashes` helpers in Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/UserPresetHistory.swift
- [ ] PRE-017-T03 Add the list to `UserPresetStore` (load at init: newer → unavailable and untouched, unreadable → `history.unreadable.json`; drop entries for unknown IDs or missing files; collect unnamed `versions/<sha>.milk` only when the list was read), `versions(of:)`, `versionBytes(of:sha256:)`, all through the path guard in Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/UserPresetStore+History.swift

## Phase 3: User Story 1 — Revert an edit (P1, MVP)

**Independent test**: edit A→B→C, revert to A: SHA-256 equals A's; the library folders' file set differs only in the version bookkeeping.

- [ ] PRE-017-T04 [US1] Make `replaceContents` keep the replaced text as a version in one transaction (research D3; a list save failure refuses; an index failure restores list and files) and make `remove` drop the preset's versions in Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/UserPresetStore.swift
- [ ] PRE-017-T05 [US1] Split `edit` into the shared bytes routine and add `versions(of:)` (`UserPresetVersionList`), `versionText(of:sha256:)` and `revert(_:to:expectedSHA256:)` with `PresetEditRefusal.versionUnavailable` in Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/UserPresetLibrary.swift and UserPresetEditing.swift
- [ ] PRE-017-T06 [US1] Package tests: revert sha match and the before/after file-set diff with other presets, their versions and sibling `PresetCollections` files present (S1); revert is itself undoable; changed-meanwhile refusal; damaged version refused with nothing changed, in Packages/PresetLibrary/Tests/PresetLibraryTests/UserPresetHistoryTests.swift
- [ ] PRE-017-T07 [US1] App: `UserPresetsCoordinator+Versions` (versions, preview text, revert announcing "Reverted <name>." on the library lane) in Apps/projectM-iOS/Coordinators/UserPresetsCoordinator+Versions.swift
- [ ] PRE-017-T08 [US1] App: `UserPresetVersionsView` (rows "<date, time> · <size>", Preview read-only, Revert with confirmation, checking progress, refusal message, empty and newer-format texts) and the row's "Versions…" menu item and VoiceOver action in Apps/projectM-iOS/Views/UserPresetVersionsView.swift and Apps/projectM-iOS/Views/PresetBrowserView.swift
- [ ] PRE-017-T09 [US1] UI test: a DEBUG fixture `-uitestPresetVersions` seeds a playable preset "Versioned" with one version; the test opens Versions…, reverts and sees the success, in Apps/projectM-iOS/Debug/UITestPresetVersionsFixture.swift and Apps/projectM-iOS/UITests/UserPresetVersionsUITests.swift

## Phase 4: User Story 2 — Versions stay bounded (P1)

- [ ] PRE-017-T10 [US2] Package tests with injected limits: the per-preset bound drops the oldest; the total count and byte bounds drop the globally oldest; a text named by another preset's version survives pruning and that preset's removal; a repeated text appears once (S2) in Packages/PresetLibrary/Tests/PresetLibraryTests/UserPresetHistoryTests.swift

## Phase 5: User Story 3 — Versions are kept safely (P2)

- [ ] PRE-017-T11 [US3] Package tests: a preset saved before this feature has no versions and edits normally; a newer list is untouched and edits save without versions; an unreadable list is set aside; an index save fault restores every file; a leftover unnamed version text is collected at load (S3) in Packages/PresetLibrary/Tests/PresetLibraryTests/UserPresetHistoryTests.swift
- [ ] PRE-017-T12 [US3] LibraryBackup test: back up a library with versions, restore it (Replace): the device's `history.json` and version texts survive and the preset's text is the backup's (S4) in Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupPresetVersionTests.swift; document the folder contents in Packages/LibraryBackup/Sources/LibraryBackup/LibraryFolders.swift

## Phase 6: Polish

- [ ] PRE-017-T13 Repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`), privacy manifest and network symbol checks on the Debug app, type-check budget flags; no new UserDefaults keys
- [ ] PRE-017-T14 Delete the simulator and derived data; count PosterBoard reports; spec status

## Dependencies

T01 → T02 → T03 → T04 → T05 → (T06, T10, T11, T12 in parallel) ; T05 → T07 → T08 → T09 ; all → T13 → T14.

## Implementation Strategy

MVP is US1 (T02-T09). US2 and US3 are tests over the same store code.
