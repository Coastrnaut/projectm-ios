# Implementation Plan: UIX-004 Favorite Parameter Shelf

**Branch**: `feature/uix-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/151-uix-004-parameter-shelf/spec.md`

## Summary

An app-only feature built on UIX-003. The shelf stores an ordered list of parameter ID strings and
renders a compact control per available pin inside the controls overlay; every control writes through
`ParameterInspectorTargets.target(for:settings:)`, the same `AppSettings` path as Settings and the
inspector.

- `ParameterShelfModel.swift` (Coordinators, new):
  - `ParameterShelfStorage`: decode the stored value (list of strings; non-strings and a non-list value
    become their text form; duplicates dropped) — pure, research UIX-004-D2.
  - `ParameterShelf` (`@MainActor @Observable`): `entries` (stored order, unknown entries kept),
    `pinned` (available, in order), `missing` (unavailable entries), `pin`, `unpin`, `move`, `moveUp`,
    `moveDown`, `removeMissing`, `canPin`, `missingNote`; saves on every change; logs the missing count
    once at load (`os.Logger`, values private). Availability = registered and inspectable
    (`ParameterInspectorTargets.inspectableIDs`), research UIX-004-D1.
  - `ParameterShelfControlSpec`: the slider spec for a numeric descriptor (shared with the inspector's
    editor so both build the same `.accessibleParameter` spec).
- `ParameterShelfView.swift` (Views, new):
  - `ParameterShelfStrip`: the overlay strip (horizontal `ScrollView` at standard sizes, `VStack` at
    accessibility sizes), the missing note with Remove, one `ParameterShelfControl` per pin.
  - `ParameterShelfControl`: slider (`.accessibleParameter`), toggle or menu picker from the descriptor;
    ends history coalescing per drag, swipe or choice; restarts the controls' auto-hide.
  - `ParameterShelfSection`: the Settings section (list with Edit, delete, VoiceOver Move up/down,
    the note, the limit footer).
  - `ParameterShelfEnvironment`: an environment value carrying the shelf, so the UIX-003 entry
    modifier and sheet can offer Pin/Remove without new parameters through `SettingsView`.
- `ParameterInspectorView.swift`: the entry modifier's context menu and VoiceOver actions add
  "Pin to Shelf" / "Remove from Shelf"; the sheet's Value section adds the same button.
- `AppCoordinator`: owns `parameterShelf` (one property, one init line, reset-flag line).
- `ControlsOverlay`: one line placing the strip above the button rows.
- `SettingsView`: one environment line and one section line (other agents edit this file).
- Key lists: `run_device_tests.py` `ALLOWED_KEYS`, `LibrarySettingsPolicy.includedKeys`, the
  `-uitestResetNotice` reset.

## Technical Context

**Language/Version**: Swift 6.4 (Xcode 27.2), Swift 6 language mode in the app.
**Primary Dependencies**: SwiftUI, Observation, os (Logger), ParameterGraph and VisualParameters (read-only).
**Storage**: one UserDefaults key `settings.parameterShelf.pins` ([String]).
**Testing**: XCTest app unit tests (`projectM-iOSTests`, own UserDefaults suites), one XCUITest (< 30 s).
**Target Platform**: iOS 26.5+ (CI Xcode 26 type-check budget applies).
**Performance Goals**: no per-frame work; the strip reads settings like any control.
**Constraints**: public APIs only; no networking; at most 8 available pins.

## Constitution Check

- I Public APIs only: SwiftUI lists, context menus, accessibility actions, UserDefaults, os.Logger. Pass.
- VI Modular boundaries: no package source change except the FILE-005 key list (a string). Pass.
- VII Real-time audio safety: main-actor UI only. Pass.
- X Evidence-based quality: acceptance by unit tests on the storage path and one UI test; simulator
  results are UI evidence only. Pass.
- Privacy (FR-065): the new key is a user setting, listed in the allowed keys; IDs only, no personal data;
  logs carry the count publicly and the values privately. Pass.

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/151-uix-004-parameter-shelf/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/parameter-shelf.md
└── checklists/requirements.md
```

### Source Code

```text
Apps/projectM-iOS/Coordinators/ParameterShelfModel.swift      (new)
Apps/projectM-iOS/Views/ParameterShelfView.swift              (new)
Apps/projectM-iOS/Views/ParameterInspectorView.swift          (Pin/Remove in menu, actions, sheet)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift           (owns the shelf; reset flag)
Apps/projectM-iOS/Views/ControlsOverlay.swift                 (the strip)
Apps/projectM-iOS/Views/SettingsView.swift                    (environment + section)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift (included key)
scripts/run_device_tests.py                                   (allowed key)
Apps/projectM-iOS/Tests/ParameterShelfTests.swift             (new)
Apps/projectM-iOS/UITests/ParameterShelfUITests.swift         (new)
```

## Complexity Tracking

None.
