# Tasks: FX-020 Effect Chain Presets

**Input**: Design documents from `specs/142-fx-020-effect-chains/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/effect-chain.md, quickstart.md

Tests are requested by the spec (FX-020-S1…S6). `{device}` marks tasks the Mac cannot finish.

## Phase 1: Setup

- [X] FX-020-T01 Write ADR `docs/adr/0054-effect-chain-order.md` (reorderable Trails and Color; flash guard and tone map fixed last; glow stays per layer; Color-first only as a separate pass when Trails are active; research FX-020-D1…D3) — Verified 2026-11-14: `docs/adr/0054-effect-chain-order.md` written and indexed in `docs/adr/README.md`; `validate_docs` OK

## Phase 2: Foundational (blocking)

- [X] FX-020-T02 [P] `OutputEffectKind` (`fx.trails`, `fx.grade`), `FixedOutputStage` (`fx.flashGuard`, `fx.toneMap`) and `OutputEffectOrder` ("each kind exactly once", repeats dropped, missing kinds appended in standard order; `.standard` = Trails, Color; `gradeBeforeTrails`; `moving(from:to:)`; `storageText`/`init(storageText:)`) in `Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift`, plain Swift, with `Packages/Compositor/Tests/CompositorTests/OutputEffectOrderTests.swift` — Verified 2026-11-14: `OutputEffectOrderTests` (5) pass on the host and in the Linux shape
- [X] FX-020-T03 `OutputGradePass` (`cmp_grade_pass`, one pooled `rgba16Float` picture, released with the compositor) in `Packages/Compositor/Sources/Compositor/OutputGradePass.swift`; `Compositor.outputEffectOrder` and the pass selection of contract E1 in `Packages/Compositor/Sources/Compositor/Compositor.swift` (focused edit; order change resets Trails; the guard, output, recording and capture use the frame's grade block) — Verified 2026-11-14: `EffectOrderCompositeTests` and the full Compositor suite pass on the host GPU

## Phase 3: User Story 1 — the order is part of the scene (P1, MVP)

**Goal**: reorder → save → reload → render persists. **Independent test**: `SceneEffectChainRenderTests`.

- [X] FX-020-T04 [P] [US1] GPU tests in `Packages/Compositor/Tests/CompositorTests/EffectOrderCompositeTests.swift`: Color→Trails differs from Trails→Color over 3 frames with Trails active and gamma/saturation grade; with Trails off both orders give identical bytes; the standard order equals a compositor with the order never set — Verified 2026-11-14: `EffectOrderCompositeTests` (4) pass
- [X] FX-020-T05 [US1] `SceneEffectEntry`, `SceneDocument.effects` (optional, written only when non-nil), decode with `kind` string required / `enabled` bool / `parameters` object (else `malformed`), "at most 16 entries" (`tooMany`) in `checkCounts`, in `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift`, `SceneDocument.swift`, `SceneDecoding.swift`, `SceneEncoding.swift` — Verified 2026-11-14: `SceneEffectChainTests` (absent byte-identical, round trip, malformed, tooMany) pass
- [X] FX-020-T06 [US1] `SceneEffectSettings` (`init(entries:)`, `entries(over:)`, `isDefault`) per research FX-020-D5, D6 and the parameter table in data-model.md, in `SceneEffectChain.swift` — Verified 2026-11-14: `SceneEffectChainTests` (clamping, capture order, unknown kept) pass
- [X] FX-020-T07 [US1] Acceptance `Packages/SceneFormat/Tests/SceneFormatTests/SceneEffectChainRenderTests.swift`: chain Trails→Color with distinct values, reorder to Color→Trails, encode, write a file, read and decode, restore, render 3 frames; equals Color→Trails rendered directly (exact), differs from Trails→Color; restored values equal — Verified 2026-11-14: `EffectChainSceneTests.testReorderSaveReloadPersistsOrderValuesAndPicture` passes (`ImageDiff` `.exact`); placed in RenderGoldens, whose scene renderer is the SCN-001 → Compositor path
- [X] FX-020-T08 [US1] App: `ColorGradeSetting.isEnabled` (`settings.colorGrade.enabled`, absent → on; `effectiveGrade` neutral when off) in `Apps/projectM-iOS/Coordinators/ColorGradeSetting.swift`; `EffectChainSetting` (order key `settings.effectChain.order`) in `Apps/projectM-iOS/Coordinators/EffectChainSetting.swift`; `AppCoordinator+EffectChain.swift` (apply order to Camera/Photo/Video/Text compositors, live settings, apply restored settings); one line per visual creation site and the restore sites in `AppCoordinator.swift` and `AppCoordinator+SceneHistory.swift` — Verified 2026-11-14: app builds; `EffectChainSettingTests` pass (order, Color off, host compositor)
- [X] FX-020-T09 [US1] Scene capture and restore: `SceneInputs.effects`, carry of the opened scene's list, write rule FX-020-D7, restore → settings, in `Apps/projectM-iOS/Coordinators/SceneAutosaveCapture.swift` — Verified 2026-11-14: `EffectChainSettingTests.testSceneWritesTheListOnlyWhenNeededAndRestoreAppliesIt`, `SceneAutosave*` and `SceneHistoryCoordinatorTests` pass
- [X] FX-020-T10 [US1] Effect order screen `Apps/projectM-iOS/Views/EffectChainView.swift` (List, `onMove`, `EditButton`, VoiceOver Move up/down, toggles, footer "Always last: Flash safety, then Tone map."; moves and preset applies announced through `AccessibilityAnnouncer`) and the Settings row (`settings.effectOrder`) in `SettingsView.mediaSections` — Verified 2026-11-14: `EffectChainUITests` passes; `check_status_events` OK; no type-check warning
- [X] FX-020-T11 [US1] UI test `Apps/projectM-iOS/UITests/EffectChainUITests.swift` (under 30 s): open Effect order, move Color above Trails, Settings row reads "Color → Trails" — Verified 2026-11-14: `EffectChainUITests.testReorderEffects` passes in 24.1 s
- [X] FX-020-T12 [US1] App unit tests `Apps/projectM-iOS/Tests/EffectChainSettingTests.swift`: order persists; Color off gives neutral effective grade; scene capture writes nothing for the default chain and the list otherwise; restore applies order, flags and values — Verified 2026-11-14: `EffectChainSettingTests` (6) pass on the FX20 simulator

## Phase 4: User Story 2 — safety and the tone map stay last (P1)

- [X] FX-020-T13 [US2] Validation warnings `fixedEffectStage`, `duplicateEffect`, `unknownEffectKind`, `valueClamped` in `SceneIssue.swift`, `SceneValidation.swift`, classified in `SceneRepair.swift` — Verified 2026-11-14: `SceneEffectChainTests.testUnknownEntryIsKeptAtItsIndexAndReported`, `testRepeatedAndFixedKindsNeverChangeTheOrder` pass
- [X] FX-020-T14 [US2] Test: an `effects` list `[fx.flashGuard, fx.toneMap, fx.grade, fx.trails]` restores order Color→Trails, reports two `fixedEffectStage`, renders equal to the same list without them (in `SceneEffectChainRenderTests.swift`) — Verified 2026-11-14: `EffectChainSceneTests.testSafetyEntriesCannotMoveSafety` passes (`.exact`)

## Phase 5: User Story 3 — old, default and future scenes (P1)

- [X] FX-020-T15 [US3] Tests in `Packages/SceneFormat/Tests/SceneFormatTests/SceneEffectChainTests.swift`: no `effects` → byte-identical re-encode; unknown entry kept verbatim at its index across restore → capture; wrong types `malformed`; 17 entries `tooMany`; out-of-range clamped and reported; QA-004 meta-test still passes — Verified 2026-11-14: SceneFormat 133 tests pass, including the QA-004 meta-test

## Phase 6: User Story 4 — named chains (P2)

- [X] FX-020-T16 [US4] `EffectChainPreset`, `EffectChainPresetList` ("≤ 32 presets", "names 1…60 characters after trimming", repeated name replaces, canonical JSON version 1) in `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChainPresets.swift` with tests in `SceneEffectChainTests.swift` — Verified 2026-11-14: `SceneEffectChainTests` preset tests pass
- [X] FX-020-T17 [US4] Presets in the app: `settings.effectChain.presets` in `EffectChainSetting`, save/apply/delete in `AppCoordinator+EffectChain.swift` and `EffectChainView`; keys added to `scripts/run_device_tests.py` `ALLOWED_KEYS`, `LibrarySettingsPolicy.includedKeys`, the UI-test reset; preset round-trip in `EffectChainSettingTests.swift` — Verified 2026-11-14: `EffectChainSettingTests.testPresetsPersistAndApplyThroughTheSettings`, `testKeysAreBackedUpAndErased`, `LibraryBackupAppTests`, `LibraryEraseAppTests` pass

## Phase 7: Polish

- [X] FX-020-T18 Linux shape of Compositor and SceneFormat (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`, FX-020-R11); repository checks (compliance, docs, motion policy, permission catalog, status events, script tests, privacy manifest, network symbols), type-check budget, report `docs/test-reports/effect-chain.md` — Verified 2026-11-14: checks all OK, Linux shape passes, `docs/test-reports/effect-chain.md`
- [ ] FX-020-T19 {device} D1: compare both orders with Trails and a strong grade on a photo; flash guard still limits a strobing fixture in both orders

## Dependencies

T01 → T02 → T03 → (T04, T05) → T06 → T07; T08 → T09 → T10 → T11/T12; T05 → T13 → T14; T05 → T15; T05 → T16 → T17; all → T18. US2-US4 depend only on T05/T06.

## Parallel examples

- T02 and T05 (different packages).
- T04 and T15 (test files in different packages).

## Implementation strategy

MVP = Phases 1-3 (renderer, scene field, acceptance, app wiring). Then US2/US3 hardening, then presets.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1-R12 and S1-S6 each map to at least one task (R1-R3 → T02-T04; R4-R7 → T05-T07, T13-T15; R8 → T08-T09, T12; R9 → T10-T11; R10 → T16-T17; R11 → T18; R12 → T11). Fixes applied: T10 now names the announcements of FX-020-R9; T18 now names the Linux shape check of FX-020-R11. No constitution conflict; no critical or high finding.
