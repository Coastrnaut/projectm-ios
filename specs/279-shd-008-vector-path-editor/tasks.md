# Tasks: SHD-008 Vector Path Editor

**Input**: Design documents from `specs/279-shd-008-vector-path-editor/`
**Tests**: requested by the spec (acceptance is test-proven: pure, scene, GPU, simulation, app and UI tests).

## Phase 1: Setup

- [ ] SHD-008-T01 Create simulator "SHD8 iPhone 17" (iOS 27.2), run `xcodegen generate`, confirm the `Build` symlink and preset submodules in the worktree; count PosterBoard reports

## Phase 2: Foundational (blocks all stories)

- [ ] SHD-008-T02 `VectorPath.swift` in `Packages/VisualGenerators/Sources/VisualGenerators/`: `VectorPoint`, `VectorPath` ("3…32 points", "0…1", duplicate ≤ 1e-6, area ≤ 1e-4 too small, crossing rules of contract P1), `VectorPathIssue` with messages, signed area, even-odd `contains`, ear-clipping triangulation, `sample(r1, r2, r3)`, `default` diamond, Codable `{"points"}` (SHD-008-R1, R2)
- [ ] SHD-008-T03 [P] `VectorPathTests.swift` in `Packages/VisualGenerators/Tests/VisualGeneratorsTests/`: bow-tie, 5-point figure-8, touching vertex, collinear overlap (non-adjacent and adjacent spike) rejected; convex and concave (L, arrow) accepted; too small; duplicate consecutive and wrapping duplicate; out of range and non-finite; count limits; Codable round trip exact; samples inside (SHD-008-S2)

## Phase 3: User Story 1 - Draw a valid closed path (P1) 🎯 MVP

**Goal**: an editing model that refuses invalid edits, and its editor screen. **Independent test**: `VectorPathDraftTests`, `VectorPathEditorUITests`.

- [ ] SHD-008-T04 [US1] `VectorPathDraft.swift` in VisualGenerators: add, move, nudge, delete, undo last point, close, start over; refuse-and-keep-last-valid after closing; `closeIssue` message while drawing (SHD-008-R3)
- [ ] SHD-008-T05 [P] [US1] `VectorPathDraftTests.swift`: bow-tie draft cannot close with "crosses itself"; triangle closes; a move across an edge after closing is refused and the path unchanged; deleting from a triangle refused; cap refused
- [ ] SHD-008-T06 [US1] `Apps/projectM-iOS/Views/VectorPathEditorView.swift`: canvas with tap-to-add, draggable 44 pt handles, VoiceOver element per point with Move left/right/up/down and Delete point actions, nudge row, Close path, Delete point, Start over, inline message (identifiers of contract P5), announcements through `AccessibilityAnnouncer` (SHD-008-R4)

## Phase 4: User Story 2 - Use a path as a layer mask (P1)

**Goal**: path mask drawn and saved. **Independent test**: `ScenePathMaskTests`, `LayerPathMaskTests`.

- [ ] SHD-008-T07 [US2] `LayerMask.swift`: `LayerMaskShape.path(VectorPath)`, kind name "path", geometry kind 3 with local = (p − 0.5)·scale (SHD-008-R5)
- [ ] SHD-008-T08 [US2] `SceneDecoding.swift`/`SceneEncoding.swift`: `"shape": "path"` with `points`; invalid path dropped with `droppedField` naming the reason (contract P2) (SHD-008-R6)
- [ ] SHD-008-T09 [P] [US2] `Packages/SceneFormat/Tests/SceneFormatTests/ScenePathMaskTests.swift`: decode → encode byte-identical and decode → load → capture → encode with exact points; bow-tie, duplicate and 2-point saved paths dropped with a warning; scene still opens (SHD-008-S1)
- [ ] SHD-008-T10 [P] [US2] `Packages/Compositor/Tests/CompositorTests/LayerPathMaskTests.swift`: concave path mask on a solid layer through the real compositor: outside band alpha 0, inside opaque, covered count within 2 % of the polygon area (SHD-008-S3)
- [ ] SHD-008-T11 [US2] App: "Path" in the mask picker (`LayerCompositeEdit.maskTitles`, `settingMask` default path), `LayerInspectorCoordinator.setMaskPath`, "Edit path" link `layerControl.maskPathEdit` in `LayerDetailView.maskDetails` opening the editor (SHD-008-R9)

## Phase 5: User Story 3 - Use a path as a particle spawn area (P2)

**Goal**: path spawn shape. **Independent test**: `VectorPathEmitterTests`.

- [ ] SHD-008-T12 [US3] `ParticleEmitterSettings`: `Shape.path`, `path: VectorPath` (default diamond; invalid or missing → default, contract P3); `ParticleFountainSimulation.spawnFromEmitter` `.path` case: three draws, x = (px − 0.5)·shapeWidth, y = (0.5 − py)·shapeHeight (SHD-008-R7, R8)
- [ ] SHD-008-T13 [P] [US3] `VectorPathEmitterTests.swift`: seeded 10 s run with a concave path at 60 Hz and jittery frames: every spawn inside, none in the notch, attempts = SHD-007 formula, identical runs; settings round trip exact; invalid stored path → default (SHD-008-S4)
- [ ] SHD-008-T14 [US3] App: `ParticleEmitterEditorView` spawn section shows width/height for `.path` and an "Edit path" link `particleEmitterPathEdit` (SHD-008-R9)

## Phase 6: App and UI tests

- [ ] SHD-008-T15 [P] `Apps/projectM-iOS/Tests/VectorPathEditorTests.swift`: mask path set through the inspector round-trips through the scene and the compositor mapping; emitter path persists through `AppSettings.particleEmitter`
- [ ] SHD-008-T16 `Apps/projectM-iOS/UITests/VectorPathEditorUITests.swift` (under 30 s): open the editor from the emitter editor, tap a bow-tie, see the "crosses itself" message and Close disabled, Start over, tap a triangle, Close → closed (SHD-008-S5)

## Phase 7: Polish

- [ ] SHD-008-T17 Linux shape (`-DVISUAL_NO_METAL` / `COMPOSITOR_NO_METAL` subsets), type-check budget on the app, SHD-007 and CMP-007 suites still pass, `SettingsTests` and `LibraryBackupAppTests` (no new keys), repo checks, privacy manifest and network symbols; report; spec status; delete simulator and derived data
- [ ] SHD-008-T18 {device} On D1, draw a path mask and a path emitter; look at the mask edge and the spawn area

## Dependencies

T02 → all. US1 (T04-T06) → T11, T14, T16. US2 (T07-T11) and US3 (T12-T14) are independent of each other.
Parallel: T03, T05, T09, T10, T13, T15 (separate test files).

## Implementation strategy

MVP = T02-T05 (validated model + editing model): proves the "rejects self-intersecting" half. Then US2 (the
saved-path half and the mask), then US3, then app/UI tests and polish.
