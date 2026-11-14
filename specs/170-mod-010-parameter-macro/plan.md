# Implementation Plan: MOD-010 Parameter Macro

**Branch**: `feature/mod-010` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/170-mod-010-parameter-macro/spec.md`

## Summary

One normalized value drives several registry parameters, each through its own MOD-004 curve and MOD-003
range, written as base values through the Settings path:

- **ParameterGraph** (`ParameterMacro.swift`): `MacroTarget` (parameter ID, curve, optional output
  minimum/maximum, invert), `ParameterMacro` (name, value, targets; limits 8 macros × 8 targets),
  `MacroTarget.problem(descriptor:)` (unknown, unsupported kind, invalid curve or range),
  `MacroTarget.value(at:descriptor:)` (continuous, integer, enum), and `ParameterMacro.evaluate(registry:)`
  → assignments plus skipped targets with reasons (duplicates included). Pure, Foundation-free logic,
  builds on Linux (research MOD-010-D1, D2).
- **SceneFormat** (`SceneMacros.swift`): optional top-level `macros` list, entries verbatim;
  `SceneMacroEntry(_ macro:)`, `SceneMacroEntry.read(_:registry:)` → live macros by position plus warnings
  `invalidMacro`, `unknownMacroTarget`; `settingValue(_:)` rewrites only `value`. Decoder, encoder, document,
  live state, validation, `SceneIssue`, `SceneRepair` (research MOD-010-D3).
- **App**: `MacroCoordinator` (`Coordinators/MacroCoordinator.swift`) holds the scene's macro entries, sets a
  macro (writes the targets through `ParameterInspectorTargets`; a target without an app control is skipped
  and reported); `SceneInputs.macros` / carry / restored values (autosave and history); `SceneHistoryEdit`
  labels a macro change "Macro <name> <percent>" with the key `macro.<index>`; `MacrosSection`
  (`Views/MacrosSection.swift`) in Settings; DEBUG seed `-uitestSeedMacro` (research MOD-010-D4, D5).
- Tests: package acceptance (three targets × 0, 0.25, 0.5, 1; invert; clamp; discrete; unknown; duplicate;
  limits) and scene round trip and issues (SceneFormat, real visual catalog); app unit tests (write through
  settings, scene round trip through capture/restore, one undo step); one UI test (slider → labels).

No ADR: nothing overrides a default (a new optional scene field, no format version change, no settings key).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new.

**Storage**: the scene document only (SCN-002 autosave); no UserDefaults key.

**Testing**: XCTest. ParameterGraph and SceneFormat on the host (and Linux in CI); app unit tests and one UI
test on the private simulator "MOD10 iPhone 17" (iOS 27.2).

**Target Platform**: iOS/iPadOS 26+; packages also macOS 15 and Linux.

**Performance Goals**: a macro change evaluates ≤ 8 targets (microseconds); nothing per frame.

**Constraints**: Settings write path only; type-check budget (explicit types, small view bodies).

**Scale/Scope**: ≤ 8 macros × 8 targets per scene.

## Constitution Check

- I Public APIs only: SwiftUI, Foundation. Pass.
- VI Modular boundaries: model in ParameterGraph, persistence in SceneFormat, app glue in the app. Pass.
- VII Real-time audio safety: nothing on the audio or frame path. Pass.
- X Evidence-based quality: acceptance tests with exact expected values; UI test on the simulator (not a
  compatibility claim). Pass.
- Privacy: no new storage outside the scene; no network. Pass.

Re-check after design: unchanged, pass.

## Project Structure

```text
Packages/ParameterGraph/Sources/ParameterGraph/ParameterMacro.swift          (new)
Packages/ParameterGraph/Tests/ParameterGraphTests/ParameterMacroTests.swift  (new)
Packages/SceneFormat/Sources/SceneFormat/SceneMacros.swift                   (new)
Packages/SceneFormat/Sources/SceneFormat/{SceneDocument,SceneDecoding,SceneEncoding,SceneIssue,
    SceneRepair,SceneValidation,SceneLiveState}.swift                          (small edits)
Packages/SceneFormat/Tests/SceneFormatTests/SceneMacroTests.swift            (new)
Apps/projectM-iOS/Coordinators/MacroCoordinator.swift                        (new)
Apps/projectM-iOS/Coordinators/{SceneAutosaveCapture,SceneHistoryCoordinator,AppCoordinator,
    AppCoordinator+SceneHistory}.swift                                         (small edits)
Apps/projectM-iOS/Views/MacrosSection.swift                                  (new)
Apps/projectM-iOS/Views/SettingsView.swift                                   (one line)
Apps/projectM-iOS/Debug/UITestMacroFixture.swift                             (new, DEBUG)
Apps/projectM-iOS/Tests/ParameterMacroAppTests.swift                         (new)
Apps/projectM-iOS/UITests/ParameterMacroUITests.swift                        (new)
specs/059-scn-001-versioned-scene-format/contracts/scene-document.md         (macros section)
```

## Complexity Tracking

None.
