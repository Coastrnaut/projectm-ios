# Implementation Plan: FX-020 Effect Chain Presets

**Branch**: `feature/fx-020` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/142-fx-020-effect-chains/spec.md`

## Summary

FX-020 makes the order of the two output effects (FX-009 Trails, FX-003/FX-004 Color) a value, stores it
with the effects' on/off flags and parameters in scene documents as an optional `effects` list, and adds
named chain presets and an Effect order screen. The flash guard (FX-019, ACC-012) and the tone map (FX-002)
stay fixed after every reorderable effect (ADR-0052).

Compositor (`Packages/Compositor`, module `Compositor`):

- `OutputEffectOrder.swift` (new, plain Swift, Linux): `OutputEffectKind` (`fx.trails`, `fx.grade`),
  `FixedOutputStage` (`fx.flashGuard`, `fx.toneMap`), `OutputEffectOrder` (normalised list; `.standard`
  = Trails, Color; `gradeBeforeTrails`; `moving(from:to:)`).
- `OutputGradePass.swift` (new, Metal): one full-screen `cmp_grade_pass` (the existing `cmp_grade`, no tone
  map) into one pooled `rgba16Float` picture.
- `Compositor.swift` (focused edit): `public var outputEffectOrder`; in `encodeFrame`, when the order puts
  Color first **and** Trails are active **and** the grade is not neutral, the composite is graded by the
  pass before Trails and the guard and every output use the neutral grade block for that frame. Otherwise
  the existing single-pass path runs unchanged (FX-020-R3). An order change resets the Trails history.

Scene document (`Packages/SceneFormat`):

- `SceneEffectChain.swift` (new): `SceneEffectEntry` (kind, enabled, raw parameters, extra),
  `SceneDocument.effects: [SceneEffectEntry]?`, encode (only when non-nil), decode (types checked, count
  ≤ 16 in `checkCounts`), validation warnings, `SceneEffectSettings` (live order + optional Color and
  Trails values) and `SceneEffectSettings.entries(over:)` (writes the live values into known entries and
  keeps every other entry at its position).
- `SceneIssue.Code`: `unknownEffectKind`, `fixedEffectStage`, `duplicateEffect` (warnings);
  `SceneRepair` classifies them (unknown content / values adjusted).
- `SceneEffectChainPresets.swift` (new): the preset list codec (canonical JSON, version 1, ≤ 32 presets,
  names ≤ 60 characters, replace by name).

App (`Apps/projectM-iOS`):

- `ColorGradeSetting`: `isEnabled` (key `settings.colorGrade.enabled`, absent → on); `effectiveGrade`
  returns neutral when off.
- `EffectChainSetting` (new): order (key `settings.effectChain.order`), presets (key
  `settings.effectChain.presets`), `onChange`.
- `AppCoordinator+EffectChain.swift` (new): apply the order to the compositor-backed visuals, the live
  `SceneEffectSettings`, apply restored settings and presets. One line per visual creation site in
  `AppCoordinator.swift`, plus the restore sites.
- `SceneAutosaveCapture`: `SceneInputs.effects`, carry of the opened scene's list, restore.
- `EffectChainView` (new): List with `onMove` + `EditButton`, VoiceOver Move up/down actions, toggles,
  footer, presets; `EffectChainSection` row in `SettingsView.mediaSections`.
- New keys in `run_device_tests.py` `ALLOWED_KEYS`, `LibrarySettingsPolicy.includedKeys`, the UI-test reset.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/effect-chain.md](contracts/effect-chain.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: Compositor (FX-002/003/009/019), SceneFormat (SCN-001), FlashSafety. No new
package or framework; no networking.

**Storage**: scene documents gain the optional `effects` list (no version bump); UserDefaults keys
`settings.effectChain.order` (String), `settings.effectChain.presets` (Data, canonical JSON),
`settings.colorGrade.enabled` (Bool).

**Testing**: Compositor `OutputEffectOrderTests` (pure) and `EffectOrderCompositeTests` (GPU: default
bit-identical, order matters, single-effect orders equal); SceneFormat `SceneEffectChainTests` (codec,
validation, unknown kinds, fixed stages, presets) and `SceneEffectChainRenderTests` (acceptance: build the
document, write a file, read it, render with a real compositor, QA-003-style exact comparison); app
`EffectChainSettingTests`; UI `EffectChainUITests`.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (pure models).

**Project Type**: iOS app plus SwiftPM packages.

**Performance Goals**: no added pass in the default path; with Color first and Trails active, one extra
full-screen pass and one pooled picture (allocated once per size).

**Constraints**: public APIs only; explicit closure types; typed string steps; SwiftUI bodies split;
unit tests about 1-2 s, UI test under 30 s; focused edits to `Compositor.swift`, `AppCoordinator.swift`,
`SettingsView.swift` (parallel agents).

**Scale/Scope**: 4 new package sources, 4 edited; 3 new app sources, 5 edited; 4 test files; 1 ADR.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Metal, SwiftUI `List`/`onMove`/`EditButton`, UserDefaults | Pass |
| VI Modular boundaries | Order model and pass in Compositor; document codec in SceneFormat; app only wires settings | Pass |
| VII Real-time safety | Render thread: one optional pass, pooled picture, no per-frame allocation | Pass |
| VIII Upstream fidelity | Default and single-effect paths bit-identical; projectM untouched | Pass |
| X Evidence | Exact image comparison on the host GPU; device GPU is a `{device}` task | Pass |
| Photosensitivity (FX-019, ACC-012) | Guard and tone map fixed last; guard measures the shown frame; caps still applied to user values | Pass |
| Privacy / no networking | Local settings only | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/142-fx-020-effect-chains/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/effect-chain.md
└── checklists/requirements.md
docs/adr/0052-effect-chain-order.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/
├── OutputEffectOrder.swift        # new (plain Swift)
├── OutputGradePass.swift          # new (Metal)
└── Compositor.swift               # outputEffectOrder, pass selection
Packages/Compositor/Tests/CompositorTests/
├── OutputEffectOrderTests.swift   # new (pure)
└── EffectOrderCompositeTests.swift # new (GPU: default bit-identical, order matters)
Packages/SceneFormat/Sources/SceneFormat/
├── SceneEffectChain.swift         # new
├── SceneEffectChainPresets.swift  # new
├── SceneDocument.swift, SceneDecoding.swift, SceneEncoding.swift, SceneValidation.swift, SceneIssue.swift, SceneRepair.swift
Packages/SceneFormat/Tests/SceneFormatTests/
├── SceneEffectChainTests.swift    # new
└── SceneEffectChainRenderTests.swift # new (acceptance, Metal-guarded)
Apps/projectM-iOS/
├── Coordinators/EffectChainSetting.swift, AppCoordinator+EffectChain.swift   # new
├── Coordinators/ColorGradeSetting.swift, SceneAutosaveCapture.swift, AppCoordinator.swift, AppCoordinator+SceneHistory.swift
├── Views/EffectChainView.swift    # new
├── Views/SettingsView.swift       # one row
├── Tests/EffectChainSettingTests.swift   # new
└── UITests/EffectChainUITests.swift      # new
scripts/run_device_tests.py, Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift
```

**Structure Decision**: extend Compositor and SceneFormat; no new package.

## Complexity Tracking

None.
