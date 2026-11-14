# Tasks: UIX-011 Color Palette Picker

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/palettes.md

## Phase 1: Foundation (model and rendering)

- [X] UIX-011-T01 [P] Palette model, library operations and limits, file codec, colour names, contrast, scene link accessors and resolver in `Packages/SceneFormat/Sources/SceneFormat/ScenePalettes.swift` and `ScenePaletteColorNames.swift` (UIX-011-R1, R2, R4, R5, R9; contract P1–P3) — Verified 2026-11-14: `swift test --package-path Packages/SceneFormat --filter ScenePalettesTests` (6 tests pass)
- [X] UIX-011-T02 [P] SceneFormat tests `ScenePalettesTests.swift`: codec round trip and canonical bytes, lenient read, newer version, limits, built-ins read-only, links in a decoded document, resolver fallback, names and contrast — Verified 2026-11-14: `swift test --package-path Packages/SceneFormat --filter ScenePalettesTests` (6 tests pass)
- [X] UIX-011-T03 [P] `VisualPalette.custom` (gradient and swatches) with `LinearColor` Hashable; `CustomPaletteTests.swift` (contract P4) — Verified 2026-11-14: `swift test --package-path Packages/VisualGenerators` (249 tests pass, 57 s, incl. 4 CustomPaletteTests); SceneFormat full suite 181 tests pass after the source-list update

## Phase 2: User Story 1 — palettes on the visual (P1)

- [X] UIX-011-T04 [US1] `PaletteStore` (file in Application Support/Palettes, atomic save, load issue, read-only on newer file) and `PaletteCoordinator` (edits, scene link, missing notice, effective `VisualPalette` with ACC-003 override) (R2, R3, R5, R6, R8, R10) — Verified 2026-11-14: `PaletteAppTests` (4 tests pass on the UIX11 iOS 27.2 simulator: read-only newer file, missing fallback, ACC-003 override)
- [X] UIX-011-T05 [US1] Scene wiring: `SceneInputs.palette`, capture writes the document and spectrum-layer links, `SceneRestoredValues.paletteID`, restore at launch, reopen and history; the native host draws the effective palette and redraws on library edits (R4, R6, R7) — Verified 2026-11-14: `PaletteAppTests.testTheSceneCaptureWritesAndRestoresTheLink` and `testAnEditUpdatesBothLinkedLayersAndSurvivesRelaunch`; scene regressions (SceneAutosaveCapture/Coordinator, SceneHistoryCoordinator, LayerInspector, NativeVisual, Settings: 45 tests) pass
- [X] UIX-011-T06 [US1] Acceptance `Apps/projectM-iOS/Tests/PaletteAppTests.swift`: edit a linked palette through the real store → two linked layers' resolved colours change at once and the coordinator's effective palette changes; a new store reading the file plus the re-decoded scene resolve the same colours; deleted palette falls back with the notice (S1, S2) — Verified 2026-11-14: `PaletteAppTests.testAnEditUpdatesBothLinkedLayersAndSurvivesRelaunch` — two linked layers change on one swatch edit, a new store plus the re-decoded scene resolve the same colours (4 tests, 0.01 s)

## Phase 3: User Stories 2 and 3 — manage and edit accessibly (P2)

- [X] UIX-011-T07 [US2][US3] Settings › Palettes: list (built-ins and user palettes, scene choice), New, Duplicate, Rename, Delete (confirmed), editor with style picker, gradient preview, swatch rows (ColorPicker, named-colour menu, VoiceOver label "Colour i of n, name, hex", low-contrast mark), add/remove colour; one row in SettingsView (R3, R9, R10) — Verified 2026-11-14: built into the app; exercised by `PalettePickerUITests` (list, New Palette, named-colour menu, Use for This Scene)
- [X] UIX-011-T08 [US3] UI test `PalettePickerUITests.swift`: new palette, change swatch 1 through the named-colour menu, its VoiceOver value changes; under 30 s (`-uitestResetPalettes`) — Verified 2026-11-14: `PalettePickerUITests.testEditASwatchOfANewPaletteAndUseIt` passes in 22.6 s on the UIX11 iOS 27.2 simulator

## Phase 4: Library integration

- [X] UIX-011-T09 FILE-005/011/009: `LibraryFolders.Folder.palettes`, contents read, archive record, records digest, restore plan section and install, erase folder with "Scenes and show", erase inventory count, `StorageLocations` Scenes root; `PaletteBackupTests.swift`; `LibraryBackupAppTests` folder-name check (R11, S4) — Verified 2026-11-14: `swift test --package-path Packages/LibraryBackup` (80 tests incl. 3 PaletteBackupTests, 27 s); app `LibraryBackupAppTests`, `LibraryEraseAppTests`, `StorageLocationsTests` pass

## Phase 5: Polish

- [X] UIX-011-T10 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget, touched package suites; spec status — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 174 tests OK; check_privacy_manifest and check_network_symbols OK on the Debug app; no new type-check warning in UIX-011 files (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`)

## Analyze (speckit-analyze, 2026-11-14)

- Coverage: R1–R11 each map to at least one task (R1/R2/R4/R5/R9 → T01; R3/R6/R7/R8/R10 → T04–T07; R11 → T09). S1, S2 → T06; S4 → T09; S3 (a minute, with or without VoiceOver) is covered by the UI flow of T08 only — it is not timed with a person (no `{device}` task: nothing device-specific).
- Fix applied: the colour-name file is `ScenePaletteColorNames.swift` (SCN-001's source-safety test lists SceneFormat's files by name).
- No constitution conflict; no ADR (optional scene fields, no default overridden).
