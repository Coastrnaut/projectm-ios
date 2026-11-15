# Tasks: SHD-008 Vector Path Editor

**Input**: Design documents from `specs/279-shd-008-vector-path-editor/`
**Tests**: requested by the spec (acceptance is test-proven: pure, scene, GPU, simulation, app and UI tests).

## Phase 1: Setup

- [X] SHD-008-T01 Create simulator "SHD8 iPhone 17" (iOS 27.2), run `xcodegen generate`, confirm the `Build` symlink and preset submodules in the worktree; count PosterBoard reports — Verified 2026-11-14: simulator SHD8 iPhone 17 (iOS 27.2) created, `xcodegen generate`, `Build` symlink present, preset submodules initialised (depth 1); PosterBoard reports before: 32

## Phase 2: Foundational (blocks all stories)

- [X] SHD-008-T02 `VectorPath.swift` in `Packages/VisualGenerators/Sources/VisualGenerators/`: `VectorPoint`, `VectorPath` ("3…32 points", "0…1", duplicate ≤ 1e-6, area ≤ 1e-4 too small, crossing rules of contract P1), `VectorPathIssue` with messages, signed area, even-odd `contains`, ear-clipping triangulation, `sample(r1, r2, r3)`, `default` diamond, Codable `{"points"}` (SHD-008-R1, R2) — Verified 2026-11-14: `swift build` of VisualGenerators; `VectorPathTests` pass (crossing is checked before the area so a symmetric bow-tie, area 0, reports "crosses itself"; contract P1 updated)
- [X] SHD-008-T03 [P] `VectorPathTests.swift` in `Packages/VisualGenerators/Tests/VisualGeneratorsTests/`: bow-tie, 5-point figure-8, touching vertex, collinear overlap (non-adjacent and adjacent spike) rejected; convex and concave (L, arrow) accepted; too small; duplicate consecutive and wrapping duplicate; out of range and non-finite; count limits; Codable round trip exact; samples inside (SHD-008-S2) — Verified 2026-11-14: `swift test --filter VectorPath` in VisualGenerators: `VectorPathTests` 5 tests pass in 0.004 s (bow-tie, 5-point figure-8, touching vertex, collinear overlap, adjacent spike rejected; square, arrow, L accepted; area, duplicate, range, count rules; exact JSON round trip; 2000 samples inside the L, none in its notch)

## Phase 3: User Story 1 - Draw a valid closed path (P1) 🎯 MVP

**Goal**: an editing model that refuses invalid edits, and its editor screen. **Independent test**: `VectorPathDraftTests`, `VectorPathEditorUITests`.

- [X] SHD-008-T04 [US1] `VectorPathDraft.swift` in VisualGenerators: add, move, nudge, delete, undo last point, close, start over; refuse-and-keep-last-valid after closing; `closeIssue` message while drawing (SHD-008-R3) — Verified 2026-11-14: `VectorPathDraft.swift` builds; `VectorPathDraftTests` pass
- [X] SHD-008-T05 [P] [US1] `VectorPathDraftTests.swift`: bow-tie draft cannot close with "crosses itself"; triangle closes; a move across an edge after closing is refused and the path unchanged; deleting from a triangle refused; cap refused — Verified 2026-11-14: `VectorPathDraftTests` 3 tests pass in 0.001 s (kept in `VectorPathTests.swift`): bow-tie draft cannot close ("The path crosses itself."), triangle closes, a closed move across the opposite edge is refused with the square kept, nudge applies, deleting from a triangle refused, start over keeps the committed path, duplicate tap and the 32-point cap refused
- [ ] SHD-008-T06 [US1] `Apps/projectM-iOS/Views/VectorPathEditorView.swift`: canvas with tap-to-add, draggable 44 pt handles, VoiceOver element per point with Move left/right/up/down and Delete point actions, nudge row, Close path, Delete point, Start over, inline message (identifiers of contract P5), announcements through `AccessibilityAnnouncer` (SHD-008-R4)

## Phase 4: User Story 2 - Use a path as a layer mask (P1)

**Goal**: path mask drawn and saved. **Independent test**: `ScenePathMaskTests`, `LayerPathMaskTests`.

- [X] SHD-008-T07 [US2] `LayerMask.swift`: `LayerMaskShape.path(VectorPath)`, kind name "path", geometry kind 3 with local = (p − 0.5)·scale (SHD-008-R5) — Verified 2026-11-14: Compositor builds; `LayerPathMaskTests` and the 17 CMP-007 `LayerMask*` tests pass on the host GPU
- [X] SHD-008-T08 [US2] `SceneDecoding.swift`/`SceneEncoding.swift`: `"shape": "path"` with `points`; invalid path dropped with `droppedField` naming the reason (contract P2) (SHD-008-R6) — Verified 2026-11-14: SceneFormat builds (target now also depends on the VisualGenerators product); `ScenePathMaskTests` and `SceneMaskTests` pass
- [X] SHD-008-T09 [P] [US2] `Packages/SceneFormat/Tests/SceneFormatTests/ScenePathMaskTests.swift`: decode → encode byte-identical and decode → load → capture → encode with exact points; bow-tie, duplicate and 2-point saved paths dropped with a warning; scene still opens (SHD-008-S1) — Verified 2026-11-14: `swift test --filter "ScenePathMask|SceneMask"` in SceneFormat: 7 tests pass in 0.05 s (path points restored exactly, decode → encode and capture bytes identical; bow-tie, figure-8, duplicate, out-of-range and 2-point paths dropped with a `droppedField` naming the reason; layer unmasked)
- [X] SHD-008-T10 [P] [US2] `Packages/Compositor/Tests/CompositorTests/LayerPathMaskTests.swift`: concave path mask on a solid layer through the real compositor: outside band alpha 0, inside opaque, covered count within 2 % of the polygon area (SHD-008-S3) — Verified 2026-11-14: `LayerPathMaskTests.testPathMaskCoverageMatchesThePolygon` passes on the host GPU in 0.03 s: 1631 far-inside pixels equal the unmasked layer, 3855 far-outside pixels (notch included) exactly 0, covered 1974.1 px vs polygon 1966.1 px (0.4 %), one masked draw, no blend pass
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

## Analysis (speckit-analyze, 2026-11-14)

| ID | Category | Severity | Finding | Fix applied |
|---|---|---|---|---|
| U1 | Underspecification | MEDIUM | R3 did not say whether a tap adds points to a closed path, nor what "Start over" keeps (research D8 did). | R3 now says taps add only while drawing and the last closed path stays in use until the new one closes. |
| C1 | Coverage | LOW | Every requirement R1-R9 and S1-S5 maps to at least one task (R1-R2 T02-T03; R3 T04-T06; R4 T06; R5 T07, T10; R6 T08-T09; R7-R8 T12-T13; R9 T11, T14; S5 T16). | None needed. |
| K1 | Constitution | — | No conflict: VII (no allocation in spawn) is covered by T02's precomputed triangulation and T12; X by the test tasks and the open `{device}` task T18. | None needed. |

Metrics: 9 requirements, 5 success criteria, 18 tasks, 100 % coverage, 0 critical issues.
