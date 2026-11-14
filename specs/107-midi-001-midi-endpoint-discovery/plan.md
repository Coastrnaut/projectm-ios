# Implementation Plan: MIDI-001 MIDI Endpoint Discovery

**Branch**: `feature/midi-001` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/107-midi-001-midi-endpoint-discovery/spec.md`

## Summary

MIDI lives in `Packages/PerformanceControl` beside OSC, with the same split: a pure, Linux-testable
core in `Sources/PerformanceControl/MIDI/` and the one system implementation in
`Sources/PerformanceControl/MIDISystem/`, compiled only `#if canImport(CoreMIDI)`.

Pure core (`MIDI/`):

- `MIDIEndpointRecord`: what a provider reads per endpoint (system unique number, direction,
  display/endpoint/entity/device names, offline, virtual, transport attribution).
- `MIDIEndpointID` and `MIDIEndpointIdentity.assign(_:)`: the stable-ID rule (system number when
  non-zero and unique in the snapshot, else an FNV-1a 64-bit fallback over direction and names,
  with an ordinal for identical fallbacks). Research MIDI-001-D2.
- `MIDIEndpoint` and `MIDIEndpointList` (ordered: inputs, then outputs, by case-insensitive name,
  then ID; network-attributed endpoints dropped; on-screen names disambiguated " (2)", " (3)").
- `MIDIEndpointChange` and `MIDIEndpointDiff.changes(from:to:)` (spec MIDI-001-R5 order).
- `MIDIRefreshCoalescer`: pure gate, one pending refresh per burst (MIDI-001-R6).
- `MIDIEndpointProvider` protocol, `MIDIRefreshScheduler` (a serial queue in production, a manual
  scheduler in tests), `MIDIEndpointDiscovery` (lifecycle with generations, like `OSCReceiver`).
- `ScriptedMIDIEndpointProvider`: a public in-memory provider (plug, unplug, rename, set offline,
  notify) used by the package tests and the app's DEBUG `-uitestFakeMIDI`.

System (`MIDISystem/CoreMIDIEndpointProvider.swift`): one `MIDIClientCreateWithBlock` client created
on first start and kept (Apple advises against disposing clients on iOS); the notify block forwards
only a "setup changed" signal while started; `currentEndpoints()` enumerates
`MIDIGetNumberOfSources/Destinations` and reads `kMIDIPropertyUniqueID`, `kMIDIPropertyDisplayName`,
`kMIDIPropertyName`, `kMIDIPropertyOffline`, the entity and device (none = virtual) and the
device's `kMIDIPropertyDriverOwner` for transport attribution. No ports, no input subscriptions,
no network session API, no Bluetooth UI.

App:

- `AppSettings.midiEnabled` (`settings.midi.enabled`, default false).
- `MIDIDiscoveryCoordinator` (`Coordinators/`, `@MainActor @Observable`): runs discovery iff enabled
  and active; copies updates onto the main actor; status and row texts (static, unit-tested);
  announcement text per update through an injected closure that the app wires to
  `AccessibilityAnnouncer.announce(_:kind: .midi)` (new kind).
- `MIDISettingsSection` (`Views/`, its own small view) mounted by one line in `SettingsView`
  (optional `midi`, nil in previews).
- DEBUG `UITestFakeMIDI` (`Debug/`): `-uitestFakeMIDI` gives the coordinator a scripted provider
  with one virtual output and a panel with Plug/Unplug fake device buttons.
- Guards: `check_compliance.py` rejects `MIDINetworkSession`/`MIDINetworkHost`/
  `MIDINetworkConnection` and `CABTMIDI*` in sources; `check_network_symbols.py` rejects
  `MIDINetwork` symbols in the binary (MIDI-001-R14). New ADR-0038 records the scope.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/midi-discovery.md](contracts/midi-discovery.md); checks: [quickstart.md](quickstart.md);
decision record: ADR-0038 (MIDI scope: local only).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: CoreMIDI (Apple, system framework; discovery calls only). No new package
dependency, no networking.

**Storage**: one UserDefaults boolean (`settings.midi.enabled`). Nothing else.

**Testing**: `Packages/PerformanceControl`: `MIDIEndpointIdentityTests`, `MIDIEndpointDiffTests`,
`MIDIRefreshCoalescerTests`, `MIDIEndpointDiscoveryTests` (scripted provider, manual scheduler;
also in the Linux shape `-DANALYSIS_NO_ACCELERATE`). App: `MIDIDiscoveryCoordinatorTests` (toggle,
foreground, texts, announcements, stored keys). UI: `MIDIDiscoveryUITests` (`-uitestFakeMIDI`).
Scripts: compliance and network-symbol rule tests in `scripts/test_scripts.py`.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (pure core).

**Project Type**: iOS app plus SwiftPM package.

**Performance Goals**: no per-message work (none subscribed); a refresh enumerates at most a few
dozen endpoints after a 100 ms coalescing delay, off the main thread.

**Constraints**: public APIs only; explicit closure types; typed steps for strings and numbers; no
C stdio globals; no main-actor mutation in setUp/tearDown; no wall-clock assertions (manual
scheduler); unit tests about 1-2 s, UI test under 30 s (owner rule 7). Parallel work: FILE-003,
MED-003 and a test-budget agent; `SettingsView.swift` and `AppCoordinator.swift` edits stay a few
lines; `DynamicTypeInspectorUITests` and `SessionRecoveryUITests` are not touched.

**Scale/Scope**: about 10 new package sources/tests, 1 coordinator, 1 view, 1 debug file, 2 app
test files, 2 script rules.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | CoreMIDI client, enumeration and property functions, documented notification IDs | Pass |
| VI Modular boundaries | Pure core behind `MIDIEndpointProvider`; the system implementation in its own folder; views only show | Pass |
| VII Real-time safety | No audio-thread change; no MIDI messages received; refresh on a utility queue | Pass |
| X Evidence | Fake provider on the Mac; a physical controller is a `{device}` task (S8) | Pass |
| Privacy | Off by default; only the toggle stored; names never logged or stored; no permission | Pass |
| No networking (FR-068, ADR-0008) | No network MIDI session; source and binary scans extended | Pass |
| Accessibility (ACC-001, ACC-004, ACC-011) | Rows have one combined label; announcements via the shared announcer; no animation (`check_motion_policy.py`) | Pass |
| Permissions (FILE-013) | No new usage key; Bluetooth pairing deferred | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/107-midi-001-midi-endpoint-discovery/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/midi-discovery.md
└── checklists/requirements.md
docs/adr/0038-midi-local-endpoint-scope.md
```

### Source Code (repository root)

```text
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/
├── MIDIEndpoint.swift               # record, ID, endpoint, list, display names
├── MIDIEndpointIdentity.swift       # stable-ID rule
├── MIDIEndpointDiff.swift           # changes
├── MIDIRefreshCoalescer.swift       # burst gate + scheduler
├── MIDIEndpointDiscovery.swift      # provider protocol + lifecycle
└── ScriptedMIDIEndpointProvider.swift
Packages/PerformanceControl/Sources/PerformanceControl/MIDISystem/
└── CoreMIDIEndpointProvider.swift   # #if canImport(CoreMIDI)
Packages/PerformanceControl/Tests/PerformanceControlTests/
├── MIDIEndpointIdentityTests.swift, MIDIEndpointDiffTests.swift
└── MIDIEndpointDiscoveryTests.swift
Apps/projectM-iOS/
├── Coordinators/MIDIDiscoveryCoordinator.swift   # new
├── Coordinators/AppSettings.swift, AppCoordinator.swift, AccessibilityAnnouncer.swift  # small edits
├── Views/MIDISettingsSection.swift               # new; SettingsView one line
├── Debug/UITestFakeMIDI.swift                    # new
├── Tests/MIDIDiscoveryCoordinatorTests.swift     # new
└── UITests/MIDIDiscoveryUITests.swift            # new
scripts/check_compliance.py, check_network_symbols.py, run_device_tests.py, check_status_events.py, test_scripts.py
```

**Structure Decision**: follow OSC-001's package split; no new package (PerformanceControl already
names MIDI as its scope and is in every CI package loop).

## Complexity Tracking

None.
