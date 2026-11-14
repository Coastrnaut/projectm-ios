# Tasks: FX-020 Effect Chain Presets

**Input**: Design documents from `specs/142-fx-020-effect-chains/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/effect-chain.md, quickstart.md

Tests are requested by the spec (FX-020-S1…S6). `{device}` marks tasks the Mac cannot finish.

## Phase 1: Setup

- [ ] FX-020-T01 Write ADR `docs/adr/0052-effect-chain-order.md` (reorderable Trails and Color; flash guard and tone map fixed last; glow stays per layer; Color-first only as a separate pass when Trails are active; research FX-020-D1…D3)

## Phase 2: Foundational (blocking)

- [ ] FX-020-T02 [P] `OutputEffectKind` (`fx.trails`, `fx.grade`), `FixedOutputStage` (`fx.flashGuard`, `fx.toneMap`) and `OutputEffectOrder` ("each kind exactly once", repeats dropped, missing kinds appended in standard order; `.standard` = Trails, Color; `gradeBeforeTrails`; `moving(from:to:)`; `storageText`/`init(storageText:)`) in `Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift`, plain Swift, with `Packages/Compositor/Tests/CompositorTests/OutputEffectOrderTests.swift`
- [ ] FX-020-T03 `OutputGradePass` (`cmp_grade_pass`, one pooled `rgba16Float` picture, released with the compositor) in `Packages/Compositor/Sources/Compositor/OutputGradePass.swift`; `Compositor.outputEffectOrder` and the pass selection of contract E1 in `Packages/Compositor/Sources/Compositor/Compositor.swift` (focused edit; order change resets Trails; the guard, output, recording and capture use the frame's grade block)

## Phase 3: User Story 1 — the order is part of the scene (P1, MVP)

**Goal**: reorder → save → reload → render persists. **Independent test**: `SceneEffectChainRenderTests`.

- [ ] FX-020-T04 [P] [US1] GPU tests in `Packages/Compositor/Tests/CompositorTests/EffectOrderCompositeTests.swift`: Color→Trails differs from Trails→Color over 3 frames with Trails active and gamma/saturation grade; with Trails off both orders give identical bytes; the standard order equals a compositor with the order never set
- [ ] FX-020-T05 [US1] `SceneEffectEntry`, `SceneDocument.effects` (optional, written only when non-nil), decode with `kind` string required / `enabled` bool / `parameters` object (else `malformed`), "at most 16 entries" (`tooMany`) in `checkCounts`, in `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift`, `SceneDocument.swift`, `SceneDecoding.swift`, `SceneEncoding.swift`
- [ ] FX-020-T06 [US1] `SceneEffectSettings` (`init(entries:)`, `entries(over:)`, `isDefault`) per research FX-020-D5, D6 and the parameter table in data-model.md, in `SceneEffectChain.swift`
- [ ] FX-020-T07 [US1] Acceptance `Packages/SceneFormat/Tests/SceneFormatTests/SceneEffectChainRenderTests.swift`: chain Trails→Color with distinct values, reorder to Color→Trails, encode, write a file, read and decode, restore, render 3 frames; equals Color→Trails rendered directly (exact), differs from Trails→Color; restored values equal
- [ ] FX-020-T08 [US1] App: `ColorGradeSetting.isEnabled` (`settings.colorGrade.enabled`, absent → on; `effectiveGrade` neutral when off) in `Apps/projectM-iOS/Coordinators/ColorGradeSetting.swift`; `EffectChainSetting` (order key `settings.effectChain.order`) in `Apps/projectM-iOS/Coordinators/EffectChainSetting.swift`; `AppCoordinator+EffectChain.swift` (apply order to Camera/Photo/Video/Text compositors, live settings, apply restored settings); one line per visual creation site and the restore sites in `AppCoordinator.swift` and `AppCoordinator+SceneHistory.swift`
- [ ] FX-020-T09 [US1] Scene capture and restore: `SceneInputs.effects`, carry of the opened scene's list, write rule FX-020-D7, restore → settings, in `Apps/projectM-iOS/Coordinators/SceneAutosaveCapture.swift`
- [ ] FX-020-T10 [US1] Effect order screen `Apps/projectM-iOS/Views/EffectChainView.swift` (List, `onMove`, `EditButton`, VoiceOver Move up/down, toggles, footer "Always last: Flash safety, then Tone map.") and the Settings row (`settings.effectOrder`) in `SettingsView.mediaSections`
- [ ] FX-020-T11 [US1] UI test `Apps/projectM-iOS/UITests/EffectChainUITests.swift` (under 30 s): open Effect order, move Color above Trails, Settings row reads "Color → Trails"
- [ ] FX-020-T12 [US1] App unit tests `Apps/projectM-iOS/Tests/EffectChainSettingTests.swift`: order persists; Color off gives neutral effective grade; scene capture writes nothing for the default chain and the list otherwise; restore applies order, flags and values

## Phase 4: User Story 2 — safety and the tone map stay last (P1)

- [ ] FX-020-T13 [US2] Validation warnings `fixedEffectStage`, `duplicateEffect`, `unknownEffectKind`, `valueClamped` in `SceneIssue.swift`, `SceneValidation.swift`, classified in `SceneRepair.swift`
- [ ] FX-020-T14 [US2] Test: an `effects` list `[fx.flashGuard, fx.toneMap, fx.grade, fx.trails]` restores order Color→Trails, reports two `fixedEffectStage`, renders equal to the same list without them (in `SceneEffectChainRenderTests.swift`)

## Phase 5: User Story 3 — old, default and future scenes (P1)

- [ ] FX-020-T15 [US3] Tests in `Packages/SceneFormat/Tests/SceneFormatTests/SceneEffectChainTests.swift`: no `effects` → byte-identical re-encode; unknown entry kept verbatim at its index across restore → capture; wrong types `malformed`; 17 entries `tooMany`; out-of-range clamped and reported; QA-004 meta-test still passes

## Phase 6: User Story 4 — named chains (P2)

- [ ] FX-020-T16 [US4] `EffectChainPreset`, `EffectChainPresetList` ("≤ 32 presets", "names 1…60 characters after trimming", repeated name replaces, canonical JSON version 1) in `Packages/SceneFormat/Sources/SceneFormat/SceneEffectChainPresets.swift` with tests in `SceneEffectChainTests.swift`
- [ ] FX-020-T17 [US4] Presets in the app: `settings.effectChain.presets` in `EffectChainSetting`, save/apply/delete in `AppCoordinator+EffectChain.swift` and `EffectChainView`; keys added to `scripts/run_device_tests.py` `ALLOWED_KEYS`, `LibrarySettingsPolicy.includedKeys`, the UI-test reset; preset round-trip in `EffectChainSettingTests.swift`

## Phase 7: Polish

- [ ] FX-020-T18 Repository checks (compliance, docs, motion policy, permission catalog, status events, script tests, privacy manifest, network symbols), type-check budget, report `docs/test-reports/effect-chain.md`
- [ ] FX-020-T19 {device} D1: compare both orders with Trails and a strong grade on a photo; flash guard still limits a strobing fixture in both orders

## Dependencies

T01 → T02 → T03 → (T04, T05) → T06 → T07; T08 → T09 → T10 → T11/T12; T05 → T13 → T14; T05 → T15; T05 → T16 → T17; all → T18. US2-US4 depend only on T05/T06.

## Parallel examples

- T02 and T05 (different packages).
- T04 and T15 (test files in different packages).

## Implementation strategy

MVP = Phases 1-3 (renderer, scene field, acceptance, app wiring). Then US2/US3 hardening, then presets.
