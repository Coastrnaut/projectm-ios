# Implementation Plan: UIX-010 Batch Parameter Reset

**Branch**: `feature/uix-010` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

A main-actor `ParameterBatchReset` writes each selected parameter's MOD-001 declared default through its UIX-003
Settings write target (skipping values already at default), between an SCN-010 `endCoalescing()` and a single
`recordStep(label:)`, the same "several writes, one step" path SCN-008 snapshot recall uses. Undo therefore
restores every previous value in one action. The scene lock is checked first (`SceneLock.refusesEdit()`), so a
locked scene changes nothing and records nothing. A `ParameterResetSelection` value holds the selected IDs,
per-group "Select All" and the count-bearing labels. The UIX-009 parameter list gains a selection mode (Select /
Done, toggle rows, group Select All, a bottom "Reset N to Defaults" bar, a status line) and the SCN-010 Undo and
Redo buttons in its toolbar. Results are announced on the parameter lane.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the Mac; CI Xcode 26 type-check budget)
**Primary Dependencies**: ParameterGraph and VisualParameters (MOD-001), SceneFormat (SCN-010 history), SwiftUI
**Storage**: none (selection in memory; no new UserDefaults key)
**Testing**: XCTest app unit tests (real catalog, real AppSettings targets, real SceneHistoryCoordinator); one XCUITest
**Target Platform**: iOS 26+ / iPadOS 26+
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: a reset writes at most 7 values and encodes one history state (as a snapshot recall does)
**Constraints**: no wall-clock assertions; UI test < 30 s; SwiftUI bodies split into properties
**Scale/Scope**: 7 resettable parameters of 15 today

## Constitution Check

- I Public APIs only: SwiftUI and the app's own types. Pass.
- VI Modular boundaries: no package change; the reset composes existing app seams (targets, history, lock). Pass.
- VII Real-time audio safety: no audio or render path touched. Pass.
- Privacy/local-first: nothing stored or sent. Pass.
- X Evidence-based quality: unit tests per rule, one short UI test; the `{device}` VoiceOver check stays open. Pass.

Post-design re-check: unchanged, pass. No ADR: no project default is overridden (bindings kept, quantization
bypassed for a reset as SCN-008 recall already does through the plain targets).

## Project Structure

### Documentation (this feature)

```text
specs/298-uix-010-batch-parameter-reset/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/batch-reset.md
└── checklists/requirements.md
```

### Source Code

```text
Apps/projectM-iOS/Coordinators/ParameterBatchReset.swift      # new: selection, reset, labels, announcement
Apps/projectM-iOS/Views/ParameterResetSelectionViews.swift    # new: toggle row, group header, reset bar
Apps/projectM-iOS/Views/ParameterSearchView.swift             # selection mode, Undo/Redo, history + announcer
Apps/projectM-iOS/Views/SettingsView.swift                    # one line: pass history and announcer
Apps/projectM-iOS/Tests/ParameterBatchResetTests.swift        # new: acceptance
Apps/projectM-iOS/UITests/ParameterBatchResetUITests.swift    # new: select two, reset, Undo
```

**Structure Decision**: app-only; the reset sits next to `ParameterInspectorReset` and reuses its targets.

## Complexity Tracking

None.
