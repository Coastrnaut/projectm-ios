# Tasks: SCN-011 Scene Template Gallery

**Input**: [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md), [contracts/scene-templates.md](contracts/scene-templates.md)
**Tests**: requested by the roadmap acceptance and the brief (acceptance, decode, licence, UI under 30 s).

## Phase 1: Setup

- [X] SCN-011-T01 Add the five templates' scene files and `manifest.json` (format `projectm-ios.scene-templates`, version 1; asset licence SPDX `MIT`; layer kinds only `spectrum.circular`, `spectrum.linear`, `text`) in Apps/projectM-iOS/Resources/SceneTemplates/ — Verified 2026-11-14: `SceneTemplateTests` (6 pass, 0.02 s) decodes all six files with zero warnings
- [X] SCN-011-T02 Bundle `Resources/SceneTemplates` as a folder resource (excluded from sources) in project.yml — Verified 2026-11-14: the Debug simulator app holds `SceneTemplates/` with the manifest and six scene files; `SceneTemplateAcceptanceTests` reads them from `Bundle.main`

## Phase 2: Foundational

- [X] SCN-011-T03 Implement `SceneTemplateManifest`, `SceneTemplateCatalog.load(directory:)` (contract T1) and `ShowStore.storeTemplateCopy(_:newID:name:)` (contract T2) in Packages/ShowControl/Sources/ShowStorage/SceneTemplates.swift — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` 84 pass (2.2 s)
- [X] SCN-011-T04 [P] Package tests: every bundled template decodes with zero warnings; licence records cover every asset key with `MIT` and `LICENSE` is MIT; copy twice → two IDs and files; edit copy 1 → copy 2 and the template byte-identical; delete copy 1 → copy 2 loads; bad manifest and missing file are skipped; a copy onto a stored ID is refused (`sceneIDTaken`) and writes nothing, in Packages/ShowControl/Tests/ShowControlTests/SceneTemplateTests.swift — Verified 2026-11-14: 6 tests pass on the macOS host

## Phase 3: User Story 1 — Start from a template (P1)

**Independent test**: instantiate Pulse Rings into a show; a cue appears with a new scene ID; nothing applied.

- [X] SCN-011-T05 [US1] `ShowCoordinator.addTemplate(_:)` (contract T3: all or nothing, tags, one save, `sceneFilesChanged`, library-lane announcement) and the bundle catalog in Apps/projectM-iOS/Coordinators/ShowCoordinator+Templates.swift — Verified 2026-11-14: `SceneTemplateAcceptanceTests` 4 pass (0.03 s) on "SCN11 iPhone 17" (iOS 27.2)
- [X] SCN-011-T06 [US1] Gallery sheet (contract T5) in Apps/projectM-iOS/Views/SceneTemplateGalleryView.swift and the "Add from Template…" row (disabled when the show holds 256 cues) in Apps/projectM-iOS/Views/ShowEditorView.swift — Verified 2026-11-14: `SceneTemplateUITests` opens it and adds Pulse Rings; `ShowEditorView.body` split to stay under the 300 ms type-check budget (no warning)
- [X] SCN-011-T07 [US1] App acceptance tests (acceptance 1-3 through the coordinator; every template validates against the app registry with zero warnings; nothing applied, position unchanged; `sceneFilesChanged` reports the copies' IDs) in Apps/projectM-iOS/Tests/SceneTemplateAcceptanceTests.swift — Verified 2026-11-14: 4 pass; ShowCoordinatorTests, SceneTagAcceptanceTests, CueTransitionAcceptanceTests also pass (19 tests, 1.3 s)
- [X] SCN-011-T08 [US1] UI test under 30 s: Settings → Show → Add from Template… → Pulse Rings → its cue appears, in Apps/projectM-iOS/UITests/SceneTemplateUITests.swift — Verified 2026-11-14: passes in 22.4 s; regressions ShowCueUITests editor test 19.2 s, SceneDuplicateUITests 24.4 s, DynamicTypeInspectorUITests testShowEditorAX3 21.2 s and AX5 19.0 s pass

## Phase 4: User Story 2 — Show Starter (P2)

- [X] SCN-011-T09 [US2] Tests: Show Starter appends two cues in order, the second with a 1.5 s crossfade; with 255 cues it is refused and nothing is written, in Apps/projectM-iOS/Tests/SceneTemplateAcceptanceTests.swift — Verified 2026-11-14: `testShowStarterAddsTwoCuesWithACrossfadeIntoTheSecond`, `testAShowWithoutRoomRefusesAndWritesNothing` pass

## Phase 5: Polish

- [X] SCN-011-T10 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbol checks on the Debug app, Xcode 26 type-check budget, PosterBoard counts; record results in spec.md Status — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 OK (21 s); check_privacy_manifest and check_network_symbols OK on the Debug app; PosterBoard reports 25 before and 25 after

## Dependencies

T01 → T03 → T04; T02 + T03 → T05 → T06 → T07, T08; T05 → T09; all → T10. T04 runs beside T05-T06.

## Implementation strategy

MVP is US1 (T01-T08); US2 adds only tests on the same code path.
