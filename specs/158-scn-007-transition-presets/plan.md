# Implementation Plan: SCN-007 Scene Transition Presets

**Branch**: `feature/scn-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Each SHOW-001 cue gets an optional transition (type, duration, MOD-004 easing curve) stored in its
`show.json` entry. The CMP-014 spec and clock learn an optional `MappingCurve`. The show coordinator
resolves a cue's transition (Reduce Motion, Reduce flashing) into a `SceneTransitionSpec` and hands it
to a transition driver before applying the scene. Settings → Show gets a per-cue Transition sheet.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: ShowControl (model + `show.json`), ParameterGraph (`MappingCurve`), Compositor (`SceneTransitionSpec`, clock, bus), app (ShowCoordinator, ShowEditorView)
**Storage**: `Application Support/Show/show.json` (format version 1, optional key per cue)
**Testing**: XCTest: ShowControl (host and Linux), Compositor model (Linux) and bus (Metal, host), LibraryBackup, app unit tests and one UI test on simulator "SCN7"
**Target Platform**: iOS 26+
**Constraints**: byte-identical legacy encoding; no new settings keys; no networking; tests within owner rule 7 budgets; type-check budget for Xcode 26

## Constitution Check

- Public APIs only, no networking, local-first data: pass (pure Swift model, local file).
- Accessibility (FR-070): the sheet uses standard Form controls, ACC-005 slider, VoiceOver actions; pass.
- Photosensitive safety: Reduce flashing lengthens cuts; FX-019 guard unchanged; pass.
- No compatibility or device claims: none made.

## Project Structure

```text
Packages/ShowControl/Sources/ShowControl/ShowCueTransition.swift   # new: model, validation, warnings
Packages/ShowControl/Sources/ShowControl/ShowCueList.swift         # cue field, setTransition, insert copies
Packages/ShowControl/Sources/ShowControl/ShowDocument.swift        # optional `transition` per cue
Packages/ShowControl/Package.swift                                  # ShowControl → ParameterGraph
Packages/Compositor/Sources/Compositor/SceneTransition.swift       # optional curve on spec and clock
Packages/Compositor/Package.swift                                   # Compositor → ParameterGraph
Apps/projectM-iOS/Coordinators/CueTransition.swift                  # new: resolver + driver protocol
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift                # drive on apply, setTransition
Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift            # wire driver and safety state
Apps/projectM-iOS/Views/CueTransitionView.swift                     # new: the Transition sheet
Apps/projectM-iOS/Views/ShowEditorView.swift                        # row line + actions
```

Tests: `ShowTransitionDocumentTests` (ShowControl), `SceneTransitionCurveTests` (Compositor model),
a curve case in `SceneTransitionBusTests`, `LibraryBackupTransitionTests`, app
`CueTransitionAcceptanceTests`, UI `CueTransitionUITests`.

## Complexity Tracking

None. The only cross-package change is two new pure-Swift dependencies on ParameterGraph.
