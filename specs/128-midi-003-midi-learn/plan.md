# Implementation Plan: MIDI-003 MIDI Learn

**Branch**: `feature/midi-003` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/128-midi-003-midi-learn/spec.md`

## Summary

MIDI-003 turns MIDI-002's received control changes into bindings, in the same split as MIDI-001
and MIDI-002: a pure, Linux-testable model in
`Packages/PerformanceControl/Sources/PerformanceControl/MIDI/` and a thin app layer.

Pure model (`MIDI/`):

- `MIDIControlBinding` (control key → parameter ID) with a one-line text form
  (`cc:<channel>:<number>=<parameter ID>`), and `MIDIBindingList` (ordered, at most 64, one binding
  per control and per parameter; `bind` returns added / replaced / moved; `remove`; text codec for
  the stored list that skips unreadable lines). Research MIDI-003-D1, D2.
- `MIDILearnEligibility`: control change on controllers 0–119 only. Research MIDI-003-D3.
- `MIDILearnSession`: idle or learning (target, deadline on an injected monotonic clock);
  `handle(batch:now:)` finds the first eligible event, binds it and ends; `expire(now:)`;
  `cancel()`. It returns the index of the learning event so the caller applies values only from the
  other events. Research MIDI-003-D4.
- `MIDIBindingValues`: for a batch, the newest value per bound parameter, mapped linearly from the
  event's `normalizedValue` over the descriptor's continuous range (MOD-001 registry); events at a
  skipped index are ignored. Research MIDI-003-D5.
- `MIDILearnCatalog.learnable(in:applied:)`: registry descriptors that allow external control, are
  continuous and are in the applied set, in registration order.

App:

- `MIDIMappingCoordinator` (`Coordinators/`, `@MainActor @Observable`): owns the list, the session,
  live values, the one-step undo, the status text; loads and saves `settings.midi.mappings`
  (`[String]`); registers the input client `"mappings"` iff learning or the list is non-empty
  (MIDI-003-R12); ends learning when listening stops or the app leaves the foreground (input state
  observer); schedules the 30 s timeout through an injected scheduler; announces through the shared
  `.midi` announcer; pushes live values through an `applyValues` closure.
- `NativeSpectrumHost`: one new property, `externalValues: [ParameterID: Double]`; in
  `resolveEffectiveGlow` the glow's manual fields are replaced by present external values before
  MOD-002 modulation and the ACC-012 clamp (research MIDI-003-D6). Small edit to a shared file.
- `AppCoordinator`: creates the coordinator, sets `midi.mappings`, wires `applyValues` to
  `nativeVisual?.externalValues` and pushes the current values when a native visual is made
  (a few lines).
- `MIDIMappingsView` (`Views/`): status line with Cancel, rows per learnable parameter (name,
  control text, Learn, Delete), Undo; DEBUG `Send CC` panel with `-uitestFakeMIDI`. Reached by a
  `NavigationLink` row added to `MIDISettingsSection`.
- Backup and erase: the key joins `LibrarySettingsPolicy.includedKeys` (so FILE-011's Settings
  category erases it automatically); `ALLOWED_KEYS` in `run_device_tests.py`;
  `check_status_events.py` lists the two new app files.
- ADR-0038 is amended with Decision 8 (bindings), no new ADR.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/midi-learn.md](contracts/midi-learn.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PerformanceControl (MIDI-002 event model), ParameterGraph (MOD-001
registry), VisualParameters (catalog), FlashSafety (`SafetyClamp`), LibraryBackup (key policy). No
new package or system framework; no networking.

**Storage**: one UserDefaults key, `settings.midi.mappings` (`[String]`, one line per binding).

**Testing**: package `MIDILearnTests` (session, eligibility, list policy, codec, values) on the host
and the Linux shape `swift test -Xswiftc -DANALYSIS_NO_ACCELERATE`; LibraryBackup policy tests
(key included, erased by Settings); app `MIDIMappingCoordinatorTests` (acceptance through the
scripted input, timeout, cancel, persistence, privacy scan, glow under Strict); UI
`MIDILearnUITests` (`-uitestFakeMIDI`); script tests (allowed keys, status events list).

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (pure model).

**Project Type**: iOS app plus SwiftPM packages.

**Performance Goals**: per batch O(events + bindings) on the main actor at ≤ 30 Hz; nothing on the
real-time MIDI thread changes.

**Constraints**: public APIs only; explicit closure types; typed string steps; no C stdio globals; no
main-actor mutation in setUp/tearDown; no wall-clock assertions (injected clock and scheduler);
SwiftUI bodies under the 300 ms type-check warning; unit tests about 1-2 s, UI test under 30 s.
Parallel work: FX-004 and MED-006; `SettingsView.swift` is not edited, `AppCoordinator.swift` and
`NativeSpectrumHost.swift` get a few lines.

**Scale/Scope**: about 5 package sources and 1 test file, 1 coordinator, 1 view, small edits to 6
files, 1 app test file, 1 UI test file.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | No new system API | Pass |
| VI Modular boundaries | Learn and binding model pure in PerformanceControl; coordinator owns state; view only shows; the host only resolves | Pass |
| VII Real-time safety | MIDI thread unchanged (MIDI-002 ring); bindings run on the main actor at drain rate; bounded list (64) and per-batch work | Pass |
| VIII Upstream fidelity | Only the native glow is driven; nothing feeds projectM | Pass |
| X Evidence | Fake MIDI on the Mac; a physical controller is a `{device}` task (S9) | Pass |
| Privacy | Stored lines hold kind, channel, number and parameter ID only; values memory-only; scanned in tests | Pass |
| No networking (FR-068, ADR-0008) | No network code; binary scan unchanged | Pass |
| Accessibility (ACC-001, ACC-004, ACC-011, ACC-012) | Announcements through the router; combined row labels; no animation; values capped by the safety clamp | Pass |
| Permissions (FILE-013) | No new usage key | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/128-midi-003-midi-learn/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/midi-learn.md
└── checklists/requirements.md
docs/adr/0038-midi-local-endpoint-scope.md   # amended (Decision 8)
```

### Source Code (repository root)

```text
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/
├── MIDIControlBinding.swift     # binding, text form, binding list and its policy
├── MIDILearnSession.swift       # eligibility, session, outcome
└── MIDIBindingValues.swift      # catalog filter, linear values per batch
Packages/PerformanceControl/Tests/PerformanceControlTests/MIDILearnTests.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift          # one key
Packages/LibraryBackup/Tests/LibraryBackupTests/…                          # policy assertion
Apps/projectM-iOS/
├── Coordinators/MIDIMappingCoordinator.swift                               # new
├── Coordinators/MIDIDiscoveryCoordinator.swift, AppCoordinator.swift       # small edits
├── Visuals/NativeSpectrumHost.swift                                        # externalValues
├── Views/MIDIMappingsView.swift                                            # new
├── Views/MIDISettingsSection.swift                                         # one row
├── Debug/UITestFakeMIDI.swift                                              # Send CC 8 helper
├── Tests/MIDIMappingCoordinatorTests.swift                                 # new
└── UITests/MIDILearnUITests.swift                                          # new
scripts/check_status_events.py, scripts/run_device_tests.py
```

**Structure Decision**: extend MIDI-001/002's folders in PerformanceControl; no new package.

## Complexity Tracking

None.
