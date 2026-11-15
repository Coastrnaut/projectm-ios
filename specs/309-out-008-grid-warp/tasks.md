# Tasks: OUT-008 Grid Warp

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/grid-warp.md, quickstart.md
**Tests**: included (owner rule 7 budgets: unit ≤ 10 s, package suite < 1 min, UI test < 30 s).

Format: `[ID] [P?] [Story] Description`. `{device}` = needs a physical device and a person.

## Phase 1: Foundational model (blocks every story)

- [ ] OUT-008-T01 [US2] `GridWarp` in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/GridWarp.swift`:
  size, identity, Catmull-Rom surface, validator (research OUT-008-D4), clamped/refused edits, resampling, codec (C1).
- [ ] OUT-008-T02 [US2] `GridWarpTests.swift`: each rule with an example, identity reproduction, affine exactness,
  fuzzed meshes (accepted ⇒ every drawn triangle positive and the outline simple; refused ⇒ a rule fails), codec round
  trip and malformed values, edits refused keep the mesh, resampling (OUT-008-S3).

## Phase 2: Output passes (US1, P1)

- [ ] OUT-008-T03 [US1] `OutputWarpMesh` and `OutputWarpReceiver` in `Packages/Compositor/Sources/Compositor/OutputWarp.swift`;
  `GridWarpPass.swift` (MSL vertex surface from `vertex_id`, bilinear fragment, guides) spliced into
  `CompositorShaders.source`; `Compositor.outputWarp` hook in `composite(into:)` (C2).
- [ ] OUT-008-T04 [US1] `GridWarpOutputTests.swift` on the real compositor: `.none` = no pass and identical bytes; a
  forced identity mesh byte-exact on `bgra8Unorm_srgb`; an affine and a curved warp match an independent CPU reference
  (OUT-008-S2); uncovered pixels black; guides on the identity draw white lines only on grid lines; `encodeOutput` unwarped
  (OUT-008-S1, S4).
- [ ] OUT-008-T05 [US1] FX-019 warp step in `Packages/Rendering/Sources/CFlashLimiter/` (`PMFlashLimiterSetWarp`, warp
  program, display flag) and `ANGLERenderer` (receiver, per-frame mesh, unwarped REC-001 capture) (C3).
- [ ] OUT-008-T06 [US1] `GridWarpGLTests.swift` (ANGLERendering, simulator): identity mesh exact, a warp moves a known
  frame as the reference says, capture unwarped.

## Phase 3: App wiring and editor (US1, US3, US4)

- [ ] OUT-008-T07 [US1] `VisualSlotView.outputWarp` / `warpState`, receiver conformance of `NativeSpectrumLayerView`
  and the compositor hosts' hooks (Camera, Photo, Video, Text), `ExternalDisplayCoordinator.gridWarp`, editing flag and
  `gridWarpSummary`, launch apply in `AppCoordinator+ExternalDisplay.swift` (C4).
- [ ] OUT-008-T08 [US4] `ExternalOutputSetting.gridWarp` and key; key lists (`run_device_tests.py` ALLOWED_KEYS,
  `LibrarySettings` excluded keys, `LibraryErasePolicy.externalDisplayKeys`); UI-test reset via `ExternalOutputSetting.keys`.
- [ ] OUT-008-T09 [US4] OUT-014 optional `gridWarp` field in `OutputProfile.swift` and `ExternalOutputSetting+Profile.swift`
  with package tests (round trip, absent = identity, invalid refused) (C5).
- [ ] OUT-008-T10 [US3] `GridWarpEditorView.swift` (canvas, handles, size picker, point picker, nudges, Reset, reason,
  announcer, DEBUG probe) and the "Grid warp…" row in `ExternalDisplaySection.swift`; help text.
- [ ] OUT-008-T11 [US1] DEBUG probe `externalGridWarp` in `Debug/UITestExternalDisplay.swift`.

## Phase 4: App verification

- [ ] OUT-008-T12 `GridWarpAppTests.swift`: external slot hands the mesh to a receiver, the device slot never;
  unsupported receivers reported; persistence (absent, stored, malformed, invalid → identity); key in
  `ExternalOutputSetting.keys`; profile apply; corner pin and grid warp applied together on one slot (OUT-008-R6);
  a mesh change applies inside the call while a recording holds the placement (OUT-008-R11); the rehearsal preview
  slot never takes a mesh (OUT-008-R8). Also run `LibraryBackupAppTests`, `LibraryEraseAppTests`,
  `OutputProfileAppTests`, `CornerPinAppTests`, `DisplayCalibrationAppTests`.
- [ ] OUT-008-T13 `GridWarpUITests.swift` (< 30 s) with the fake external display: open editor → guides on, nudge
  moves a point, Reset → identity, Done → guides off, mesh kept; plus `CornerPinUITests` and `DisplayCalibrationUITests`.
- [ ] OUT-008-T14 Repo checks (`test_scripts.py`, `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
  `check_permission_catalog.py`, `check_status_events.py`), type-check budget of new SwiftUI, privacy manifest and
  network-symbol checks on the Debug app; PosterBoard counts.
- [ ] OUT-008-T15 {device} D1 with a projector on a curved surface: guides aligned with a 5 × 5 grid, identity shows no
  change, a recording made meanwhile is unwarped, a native spectrum shown unwarped (last stage).

## Dependencies

T01 → T02; T01 → T09; T03 → T04; T03 → T05 → T06; T01 + T03 + T05 → T07 → T08 → T10 → T11 → T12 → T13 → T14 → T15.

## Analysis (speckit-analyze, 2026-11-15)

Coverage after fixes: R1-R3 → T01/T02; R4 → T01/T02 (edits), T08 (stored), T09 (import), T10 (editor reason); R5 →
T10/T13; R6 → T12 (added); R7 → T04, T06; R8 → T04, T06, T12 (rehearsal added); R9 → T08/T12; R10 → T09; R11 → T12
(added); R12 → T11/T13. S1 → T04/T06; S2 → T04; S3 → T02; S4 → T04/T06; S5 → T09/T12. No constitution conflict, no
duplicate or ambiguous requirement left. Fixes applied: T04 gains the guides check; T12 gains R6, R8 and R11 checks.
