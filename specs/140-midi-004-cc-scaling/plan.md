# Implementation Plan: MIDI-004 MIDI CC Scaling

**Branch**: `feature/midi-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/140-midi-004-cc-scaling/spec.md`

## Summary

MIDI-004 gives every MIDI-003 binding a curve (MOD-004) and an Invert flag, stored as `;`-options on the
existing mapping line, and adds an options screen per mapping. Same split as MIDI-001 to MIDI-003: a pure,
Linux-testable model in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/` and a thin app layer.

Pure model (`MIDI/`):

- `MIDIMappingOptions` (new file `MIDIMappingOptions.swift`): curve, inverted, kept unreadable curve text,
  kept unknown segments; `init(segments:)` / `segments` (the `;` codec); `position(normalized:)` =
  clamp → invert → curve (research MIDI-004-D1, D2, D3).
- `MIDICurvePreset` (same file): Linear, Ease in (`easeIn:2`), Ease out (`easeOut:2`), Logarithmic
  (`log:9`); `preset(for:)` (nil = Custom); `MIDIMappingOptions.summary` ("Ease in, inverted").
- `MIDIControlBinding` gains `options` (default `.default`); its storage line appends the option segments.
- `MIDIBindingList.bind` carries the target's previous options onto the new binding (MIDI-004-R6);
  new `setOptions(_:for:)`, `binding(forKey:)`.
- `MIDIBindingValues.value(normalized:for:options:)` uses `options.position` then MOD-003
  `LinearMapping.interpolate(from: minimum, to: maximum, at:)`; `values(for:bindings:registry:)` uses each
  binding's options.

App:

- `MIDIMappingCoordinator`: `options(for:)`, `selectPreset(_:for:)`, `setInverted(_:for:)` (save, announce
  on `.midi`, no Undo entry); `MIDIMappingRow` gains `curveSummary` and `curveUnreadable`.
- `MIDIMappingsView`: a "Curve" row under each mapped row, linking to the new `MIDIMappingOptionsView`
  (`Views/MIDIMappingOptionsView.swift`: picker, Invert toggle, static preview, unreadable notice).
- `check_status_events.py` lists the new view. No new stored key, no backup or erase change (the key is
  MIDI-003's).

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/cc-scaling.md](contracts/cc-scaling.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PerformanceControl (MIDI-003 bindings), ParameterGraph (MOD-004 `MappingCurve`,
MOD-003 `LinearMapping`, MOD-001 registry). No new package or framework; no networking.

**Storage**: unchanged key `settings.midi.mappings` (`[String]`); lines gain optional `;curve=` and
`;invert=1` segments.

**Testing**: package `MIDICCScalingTests` (endpoints for 3 ranges × 7 curve kinds × invert, midpoints,
codec, presets) on the host and the Linux shape; app `MIDIMappingCoordinatorTests` additions (fake MIDI
source end to end, options persist, rebinding keeps options, announcements); UI `MIDICCScalingUITests`
(seeded mapping, toggle Invert); script tests.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (pure model).

**Project Type**: iOS app plus SwiftPM packages.

**Performance Goals**: per value one clamp, one subtraction, one curve evaluation (allocation-free,
MOD-004) and one interpolation; unchanged O(events + bindings) per batch at ≤ 30 Hz on the main actor.

**Constraints**: public APIs only; explicit closure types; typed string steps; no C stdio globals; no
wall-clock assertions; SwiftUI bodies under the type-check budget; unit tests about 1-2 s, UI test under
30 s. Parallel work: UIX-003 edits parameter UI; this row stays inside the MIDI views and does not touch
`SettingsView.swift`, `AppCoordinator.swift`, `Compositor.swift` or `VisualizerView.swift`.

**Scale/Scope**: 1 new and 2 edited package sources, 1 package test file; 1 coordinator edit, 1 new view,
1 view edit, app test additions, 1 UI test file, 1 script list line.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | SwiftUI `Path`, `Picker`, `Toggle` only | Pass |
| VI Modular boundaries | Scaling and codec pure in PerformanceControl; coordinator owns state; views only show | Pass |
| VII Real-time safety | MIDI thread unchanged; scaling runs on the main actor at drain rate, allocation-free | Pass |
| VIII Upstream fidelity | Only the native glow is driven; nothing feeds projectM | Pass |
| X Evidence | Fake MIDI on the Mac; a physical controller is the `{device}` task | Pass |
| Privacy | Options add a curve and a flag; no device or endpoint data | Pass |
| No networking (FR-068) | No network code | Pass |
| Accessibility (ACC-004, ACC-011, ACC-012) | Changes announced through the `.midi` lane; preview has a spoken description; no animation; values still pass the safety clamp | Pass |
| Permissions (FILE-013) | No new usage key | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/140-midi-004-cc-scaling/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/cc-scaling.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/
├── MIDIMappingOptions.swift      # new: options, codec, presets, position
├── MIDIControlBinding.swift      # options on the binding and the list
└── MIDIBindingValues.swift       # curve- and inversion-aware values
Packages/PerformanceControl/Tests/PerformanceControlTests/MIDICCScalingTests.swift   # new
Apps/projectM-iOS/
├── Coordinators/MIDIMappingCoordinator.swift   # options API, row summary
├── Views/MIDIMappingsView.swift                 # Curve row
├── Views/MIDIMappingOptionsView.swift           # new
├── Tests/MIDIMappingCoordinatorTests.swift      # additions
└── UITests/MIDICCScalingUITests.swift           # new
scripts/check_status_events.py
```

**Structure Decision**: extend MIDI-003's files; no new package.

## Complexity Tracking

None.
