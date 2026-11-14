# Implementation Plan: UIX-003 Context Parameter Inspector

**Branch**: `feature/uix-003` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/136-uix-003-parameter-inspector/spec.md`

## Summary

An app-only feature (no package changes; MOD-004 is editing ParameterGraph in parallel). The
inspector reads everything it shows from the MOD-001 registry descriptor and writes only through
the existing `AppSettings` properties that the Settings controls write.

- `ParameterInspectorModel.swift` (Coordinators): pure, unit-testable values.
  - `ParameterValueText`: display and spoken text of a `ParameterValue` for a descriptor
    (unit, decimals from the step hint). Research UIX-003-D2.
  - `ParameterInspectorSummary`: name, ID, group, unit, range, step, default (display + spoken).
  - `ParameterInspectorTarget`: get/set of a `ParameterValue` over one `AppSettings` property;
    `ParameterInspectorTargets.target(for:settings:)` for the seven inspectable IDs (nil = read-only).
  - `ParameterInspectorReset.reset(_:target:)`: writes `descriptor.defaultValue` and returns the
    announcement text. Research UIX-003-D1.
  - `ParameterModulationReading` and `ParameterModulationReader.reading(...)`: effective value,
    sources ("Kick → 0%…40% (replace)", "MIDI control") and the safety-limited flag, from plain
    inputs (bindings, external value, modulator value, rendered value). Research UIX-003-D3.
- `NativeSpectrumHost`: one read-only method `modulatorValue(for:manual:)` (the private modulator).
- `AppCoordinator+ParameterInspector.swift`: `parameterModulationReading(for:)` from the live host and
  the settings' manual value.
- `ParameterInspectorView.swift` (Views): the sheet (List: About, Details, Value, Modulation), the
  `.parameterInspectorEntry(_:open:)` modifier (context menu "Inspect" + VoiceOver action) and the
  `.parameterInspectorSheet(...)` modifier (sheet + DEBUG `-uitestInspectParameter <id>`).
  The modulation section is a `TimelineView(.periodic(by: 0.1))` subview only when a reading exists.
- `SettingsView`: the entry modifier on the seven rows and the sheet modifier; minimal edits.

## Technical Context

**Language/Version**: Swift 6.4 (Xcode 27.2), Swift 6 language mode in the app.
**Primary Dependencies**: SwiftUI, ParameterGraph (read-only), VisualParameters, VisualEffects.
**Storage**: none new (UIX-003-R11).
**Testing**: XCTest app unit tests (`projectM-iOSTests`), one XCUITest (< 30 s).
**Target Platform**: iOS 26.5+ (CI Xcode 26 type-check budget applies).
**Performance Goals**: inspector refresh ≤ 10 Hz, only while open; nothing per frame.
**Constraints**: public APIs only; no new UserDefaults keys; no networking.

## Constitution Check

- I Public APIs only: SwiftUI context menus, accessibility actions, TimelineView. Pass.
- VI Modular boundaries: no package change; the app reads the registry through its public API. Pass.
- VII Real-time audio safety: reads happen on the main actor at ≤ 10 Hz; no audio-thread access. Pass.
- X Evidence-based quality: acceptance by unit tests on the reset path and one UI test; simulator
  results are UI evidence only. Pass.
- Privacy: no new stored data. Pass.

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/136-uix-003-parameter-inspector/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/parameter-inspector.md
└── checklists/requirements.md
```

### Source Code

```text
Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift        (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+ParameterInspector.swift (new)
Apps/projectM-iOS/Views/ParameterInspectorView.swift                (new)
Apps/projectM-iOS/Views/SettingsView.swift                          (entry points, sheet)
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift                  (one read-only method)
Apps/projectM-iOS/Tests/ParameterInspectorTests.swift               (new)
Apps/projectM-iOS/UITests/ParameterInspectorUITests.swift           (new)
```

## Complexity Tracking

None.
