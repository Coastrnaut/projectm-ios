# Tasks: SHOW-001 Manual Cue List

**Input**: `specs/069-show-001-manual-cue-list/` (spec, plan, research, data-model, contracts, quickstart)

Tests are requested by the spec (SHOW-001-S1 to S6). Budgets (owner rule 7): unit ≤ 10 s each,
package suite < 1 min, UI test < 30 s. A task is ticked only when verified, with
" — Verified <date>: <how>".

## Phase 1: Setup

- [ ] SHOW-001-T01 Create `Packages/ShowControl/Package.swift` (targets `ShowControl` with no dependency, `ShowStorage` on SceneFormat, test target `ShowControlTests`), add the package to `project.yml` and to the five package loops in `.github/workflows/ios-ci.yml`

## Phase 2: Foundational (model and document)

- [X] SHOW-001-T02 Implement `ShowCue`, `ShowPosition`, `ShowCueList` with `next()`, `previous()`, `go(to:)`, `append(sceneID:label:)`, `remove(_:)`, `move(fromOffsets:toOffset:)`, `rename(_:to:)` and `ShowStep` in `Packages/ShowControl/Sources/ShowControl/` per data-model.md: at most 256 cues; labels "Trimmed, 1…80 characters"; scene IDs canonical uppercase UUID text; deleting the active cue → the cue before it or standby — Verified 2026-11-13: `swift test --package-path Packages/ShowControl` 19 tests pass on the Mac host (0.23 s) and in the Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`, 0.21 s): ShowAcceptanceTests, ShowDocumentTests editing cases
- [X] SHOW-001-T03 Implement `ShowDocument` v1 encode/decode with validation (size ≤ 1 MiB first, `format` "projectm-ios.show", `version` > 1 refused as newer, limits, duplicate cue IDs refused, dangling position → standby warning) in `Packages/ShowControl/Sources/ShowControl/ShowDocument.swift` per contracts/show-document.md S1 — Verified 2026-11-13: `swift test --package-path Packages/ShowControl` 19 tests pass on the Mac host (0.23 s) and in the Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`, 0.21 s): ShowDocumentTests validation table and round trip

## Phase 3: User Story 1 — Step through a prepared show (P1) 🎯 MVP

**Goal**: deterministic Next/Previous/Go to over five cues; scene IDs preserved.
**Independent test**: `ShowAcceptanceTests` and `ShowCueUITests`.

- [X] SHOW-001-T04 [P] [US1] Acceptance test: five cues, five distinct scenes, an 18-step table of next/previous/go with expected position and scene ID at every step, run twice from fresh state with identical results; ends (atEnd, atStart, empty, standby) in `Packages/ShowControl/Tests/ShowControlTests/ShowAcceptanceTests.swift` — Verified 2026-11-13: `swift test --package-path Packages/ShowControl` 19 tests pass on the Mac host (0.23 s) and in the Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`, 0.21 s): ShowAcceptanceTests (6)
- [X] SHOW-001-T05 [P] [US1] Validation table and codec round trip (IDs, labels, order, position, byte-identical re-encode) in `Packages/ShowControl/Tests/ShowControlTests/ShowDocumentTests.swift` — Verified 2026-11-13: `swift test --package-path Packages/ShowControl` 19 tests pass on the Mac host (0.23 s) and in the Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`, 0.21 s): ShowDocumentTests (7)
- [X] SHOW-001-T06 [P] [US1] Seeded property test (SplitMix64, fixed seed, 1,000 operations, invariants, replay equality, ≤ 1 s) in `Packages/ShowControl/Tests/ShowControlTests/ShowPropertyTests.swift` — Verified 2026-11-13: `swift test --package-path Packages/ShowControl` 19 tests pass on the Mac host (0.23 s) and in the Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`, 0.21 s): ShowPropertyTests (1, 0.2 s)
- [X] SHOW-001-T07 [US1] `ShowStore` (folder `show.json` + `Scenes/<id>.scene.json`, atomic writes, scenes before show, unreferenced scenes removed, refused file set aside as `show.damaged-<n>.json`, missing/mismatched scene flagged) in `Packages/ShowControl/Sources/ShowStorage/ShowStore.swift`, tests in `Packages/ShowControl/Tests/ShowControlTests/ShowStoreTests.swift` (scene IDs preserved through save/load) — Verified 2026-11-13: `swift test --package-path Packages/ShowControl` 19 tests pass on the Mac host (0.23 s) and in the Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`, 0.21 s): ShowStoreTests (5)
- [ ] SHOW-001-T08 [US1] `ShowSceneSnapshot` (look ↔ SCN-001 document per research SHOW-001-D5) in `Apps/projectM-iOS/Coordinators/ShowSceneSnapshot.swift`
- [ ] SHOW-001-T09 [US1] `ShowCoordinator` (load at launch, step → read scene → `liveState` → apply settings, text, `visualSettingsChanged()`/`glowSettingsChanged()`; never audio or camera; notice + VoiceOver on failure; save after every change) in `Apps/projectM-iOS/Coordinators/ShowCoordinator.swift`, owned by `AppCoordinator`
- [ ] SHOW-001-T10 [US1] Show row in the controls (Previous cue, "Cue 2 of 5 · Intro", Next cue; VoiceOver value "Cue 2 of 5, Intro"; unavailable at the ends; notice) in `Apps/projectM-iOS/Views/ShowControls.swift`, used by `ControlsOverlay.swift` and `VisualizerView.swift`
- [ ] SHOW-001-T11 [US1] DEBUG seed `-uitestShowSeed` (five scenes with distinct visuals, five cues, standing on cue 1 applied) in `Apps/projectM-iOS/Debug/UITestShowFixture.swift` and DEBUG probe `showActiveScene` in `VisualizerView.swift`
- [ ] SHOW-001-T12 [US1] App tests: apply switches visual and options and keeps `sourceStarts`; missing scene → notice, output unchanged; unknown/camera layers left out with a notice; save failure keeps the session state; restart keeps the position in `Apps/projectM-iOS/Tests/ShowCoordinatorTests.swift`
- [ ] SHOW-001-T13 [US1] UI test: seed → Next ×4 shows cues 2…5 (label and `showActiveScene`), Previous → cue 4, `sourceStarts` = 1, then the Right Arrow key moves to cue 5 (hardware key event), < 30 s in `Apps/projectM-iOS/UITests/ShowCueUITests.swift`

## Phase 4: User Story 2 — Build the show (P1)

**Goal**: add the current look, reorder, rename, delete; kept after relaunch.
**Independent test**: `ShowCoordinatorTests` editing cases.

- [ ] SHOW-001-T14 [US2] Add Current Scene / delete / move / rename / Go to in `ShowCoordinator`, tests in `ShowCoordinatorTests.swift` (output unchanged by edits; snapshot unchanged after later settings changes; Camera records the visual before Camera)
- [ ] SHOW-001-T15 [US2] Settings → Show editor (list with number, label, "Scene missing" flag; Add Current Scene; reorder; delete; rename alert; Go to cue; the set-aside notice) in `Apps/projectM-iOS/Views/ShowEditorView.swift`, one row in `SettingsView.swift`

## Phase 5: User Story 3 — Blackout and keyboard (P2)

- [ ] SHOW-001-T16 [US3] Test: a step while blacked out keeps `isOutputBlack` in `ShowCoordinatorTests.swift`
- [ ] SHOW-001-T17 [US3] Keyboard shortcut buttons (Right Arrow, Page Down → Next; Left Arrow, Page Up → Previous; no modifiers; only with cues; not B) in `Apps/projectM-iOS/Views/ShowControls.swift` placed in `VisualizerView.swift`; verified by the key step in `ShowCueUITests` (T13)

## Phase 6: Polish

- [ ] SHOW-001-T18 ADR (next free number) for the show document and scene reference rule, `docs/adr/README.md`, privacy policy "Shows" paragraph (`docs/privacy-policy.md`), FR-065 note in spec
- [ ] SHOW-001-T19 Checks: `check_compliance.py`, `validate_docs.py`, `check_privacy_manifest.py` on the Debug app, package tests on host and Linux shape, app tests and UI tests on the iOS 27.2 simulator (with EmergencyBlackoutUITests and NativeVisualUITests), PosterBoard report count before and after

## Dependencies

T01 → T02 → T03 → (T04, T05, T06 in parallel) → T07 → T08 → T09 → T10, T11 → T12, T13 → US2 (T14 → T15) → US3 (T16, T17) → T18 → T19.
US2 and US3 need US1's coordinator; the package (T01-T07) is independent of the app.

## Parallel example (US1)

T04, T05 and T06 are separate test files over the same model and can be written together.

## Implementation strategy

MVP = Phases 1-3 (deterministic package + apply + controls + UI test). Then the editor (US2) and the
blackout/keyboard additions (US3), then the ADR and checks.
