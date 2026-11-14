# Tasks: SCN-014 Scene Dependency Pack

**Input**: [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md), [contracts/scene-pack.md](contracts/scene-pack.md)
**Tests**: requested by the roadmap acceptance and the brief (acceptance, missing file, traversal, dedup, UI under 30 s).

## Phase 1: Foundational (pack format)

- [X] SCN-014-T01 Slide records, paths and scene helpers (`slideStoreIDs`, `remappingSlideIDs`), optional manifest `slides`, file limit 24, new errors, in Packages/SceneArchive/Sources/SceneArchive/ (SceneArchiveSlides.swift, SceneArchiveManifest.swift, SceneArchiveFormat.swift, SceneArchiveError.swift) — Verified 2026-11-14: `swift test --package-path Packages/SceneArchive` 36 pass (0.23 s)
- [X] SCN-014-T02 Path audit (contract P3) in Packages/SceneArchive/Sources/SceneArchive/SceneArchivePathAudit.swift; writer runs it and packs slides (P1); reader reads and checks slides (P2) — Verified 2026-11-14: `SceneArchiveSlideTests` round trip, audit and crafted-pack tests pass; Linux-shape build (`-D*_NO_*`) OK
- [X] SCN-014-T03 [P] Package tests: slides round trip; a pack without slides is byte-identical to before (no `slides` key); audit flags container paths and `file:` but not "1/2"; writer refuses a leaked path; crafted slide records (wrong path, repeated index, count mismatch, missing file) and `../`, `/` entry names refused, in Packages/SceneArchive/Tests/SceneArchiveTests/SceneArchiveSlideTests.swift — Verified 2026-11-14: 7 new tests pass (0.04 s)

## Phase 2: User Story 1 — Export (P1)

- [ ] SCN-014-T04 [US1] `SceneArchiveService.export` packs slides from the Photos folder; FILE-001 import stages, adopts and remaps slides; `stage(id:)` on PhotoStore, LogoStore, VideoStore, in Apps/projectM-iOS/Coordinators/
- [ ] SCN-014-T05 [US1] `ScenePackCoordinator.export(sceneID:)` (scene from the show store, share sheet, cleanup, announcements) in Apps/projectM-iOS/Coordinators/ScenePackCoordinator.swift; Scene Folders "Export Scene…" (context menu, swipe, VoiceOver action) in Apps/projectM-iOS/Views/SceneFoldersView.swift and Apps/projectM-iOS/Views/ScenePackViews.swift

## Phase 3: User Story 2 — Import (P1)

- [ ] SCN-014-T06 [US2] `ScenePackImporter` preview and library import (contract P4; derived identifiers, no current change, rollback of new identifiers) in Apps/projectM-iOS/Coordinators/ScenePackImporter.swift; `ShowCoordinator.installImportedScene` in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift
- [ ] SCN-014-T07 [US2] "Import Scene…" row, file picker for the exported type, preview sheet (contract P5) in Apps/projectM-iOS/Views/ScenePackViews.swift; `UTExportedTypeDeclarations` in project.yml; AppCoordinator wiring
- [ ] SCN-014-T08 [US2] Acceptance tests (photo + 2 slides + logo + text → export → no absolute path → wipe → import offline → equal scene apart from identifiers, byte-identical media, cue; missing media file refused; traversal entries refused; re-import stores nothing twice and adds no cue; conflicting ID → copy; a file that is not a pack refused) in Apps/projectM-iOS/Tests/ScenePackAcceptanceTests.swift
- [ ] SCN-014-T09 [US2] DEBUG fixture (`-uitestScenePackFixture`) in Apps/projectM-iOS/Debug/UITestScenePackFixture.swift and UI test under 30 s (export, import the exported pack, the copy's cue appears) in Apps/projectM-iOS/UITests/ScenePackUITests.swift

## Phase 4: Polish

- [ ] SCN-014-T10 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbol checks on the Debug app, Xcode 26 type-check budget, regression of FILE-001 app tests, PosterBoard counts; record results in spec.md Status

## Dependencies

T01 → T02 → T03; T02 → T04 → T05; T04 → T06 → T07 → T08, T09; all → T10.

## Implementation strategy

MVP is US1 + US2 together (the acceptance needs both); package work first, then the app service, then UI.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1-R4 → T01-T03, T08; R5-R7, R10 → T06, T08; R8 → T10 (network symbols) and T06 (single read);
R9 → T05, T07, T09. S1-S4 → T08 (S4 also T03); S5 → T09. Findings applied: (1) the spec's audit list was
narrower than research D2; the spec now points to D2's list as the source; (2) the edge case "the file
picked is not a pack" had no test; T08 now includes it. No constitution conflicts, no unmapped tasks.
