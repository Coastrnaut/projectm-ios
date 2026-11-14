# Implementation Plan: MIDI-011 MIDI Hot-Plug Recovery

**Branch**: `feature/midi-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/166-midi-011-hotplug/spec.md`

## Summary

The shared MIDI input gets a subscription registry keyed by MIDI-001's stable endpoint ID that reconciles the wanted
IDs with the system's current sources, follows CoreMIDI setup notifications itself (coalesced), and reports endpoints
it saw disappear so held keys are released. Same split as MIDI-001 to MIDI-008: pure, Linux-testable code in
`Packages/PerformanceControl/Sources/PerformanceControl/MIDI/`, CoreMIDI only in `MIDISystem/`, a thin app layer.

Pure model (`MIDI/`):

- `MIDISourceSubscriptions.swift` (new):
  - `MIDISourceSystem` protocol: `snapshot()` (every endpoint with its system handle; 0 for destinations),
    `connect(_:) -> Bool`, `disconnect(_:)` (research MIDI-011-D1).
  - `MIDISubscriptionRegistry` (value type): `reconcile(wanted:snapshot:connect:disconnect:)` → result with connected,
    disconnected and lost IDs; `markRemoved(handle:)` (research MIDI-011-D2, D3).
  - `MIDISourceSubscriptions` (final class, `Mutex`): owns the registry, the stored wanted set, MIDI-001's
    `MIDIRefreshCoalescer` and a `MIDIRefreshScheduler`; `update(wanted:)` reconciles at once, `setupChanged()`
    schedules one coalesced reconcile, `sourceRemoved(handle:)` marks and schedules, `close()` drops everything;
    read-only counters (`activeIDs`, `connectCalls`, `disconnectCalls`, `reconcileCount`, `lossCount`) (D4, D5).
- `ScriptedMIDISourceSystem.swift` (new): an in-memory system with handles that change on every plug, per-handle
  active connection counts (a duplicate subscription would show 2 and deliver twice), removal and setup notifications
  and bursts, and `send(_:from:timestamp:)` that delivers once per live connection.
  `ScriptedMIDISourceInputProvider` is a `MIDIInputProvider` over it (D6).
- `MIDIInputService.swift`: `MIDIInputProvider.sourceLossCount` (default 0) and `MIDIInputService.sourceLossCount`.

System (`MIDISystem/CoreMIDIInputProvider.swift`): the input client gets a notify block (removed source → `sourceRemoved`;
added, removed, setup changed, property changed → `setupChanged`); `connect(sources:)` becomes
`subscriptions.update(wanted:)` over a `CoreMIDISourceSystem` (enumeration as before, `MIDIPortConnectSource` /
`MIDIPortDisconnectSource` on the port). The receive block is unchanged.

App:

- `MIDIInputCoordinator.drain()`: when `service.sourceLossCount` changed, runs the state observers first (MIDI-011-R5).
- `MIDIMappingCoordinator+Notes.swift` `releaseNotesIfInputChanged()`: a changed loss count also releases all held keys.
- `MIDIDiscoveryCoordinator`: remembers the IDs listed since start; `announcement(for:seen:)` says "reconnected".
- DEBUG `UITestFakeMIDI`: the input is a `ScriptedMIDISourceInputProvider`; Plug/Unplug also plug and unplug the
  source system (new handle each plug).

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/hotplug.md](contracts/hotplug.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PerformanceControl (MIDI-001 identity and coalescer, MIDI-002 input). CoreMIDI (already
linked) only in `MIDISystem/`. No new package or framework; no networking.

**Storage**: none (in-memory only).

**Testing**: package `MIDIHotplugTests` (A/B acceptance fixture, collision fallback, burst → one reconcile, 20-cycle
leak check, same-handle replug, failed connect, close; host and Linux shape); app `MIDIHotplugCoordinatorTests`
(mapped CC after a reconnect changes the parameter once, held key released on a quick replug, reconnect
announcement); existing `MIDIDiscoveryUITests`/`MIDIMonitorUITests` re-run on the new DEBUG fake.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (pure model).

**Project Type**: iOS app plus SwiftPM packages.

**Performance Goals**: a reconcile is O(endpoints) and runs at most once per coalescing window plus once per discovery
update; nothing per MIDI message; the receive block is unchanged.

**Constraints**: public APIs only; explicit closure types; no C stdio globals; no wall-clock assertions (manual
scheduler); unit tests about 1-2 s. `AppCoordinator.swift`, `SettingsView.swift`, `Compositor.swift`,
`VisualizerView.swift` untouched.

**Scale/Scope**: 2 new and 2 edited package sources, 1 package test file; 3 coordinator edits, 1 DEBUG edit, 1 app
test file.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | `MIDIClientCreateWithBlock` notify block, `MIDIPortConnectSource`/`DisconnectSource`, already used | Pass |
| VI Modular boundaries | Reconcile pure in PerformanceControl; CoreMIDI behind `MIDISourceSystem` | Pass |
| VII Real-time safety | Receive block unchanged; reconcile on a utility queue or the caller's thread, never per message | Pass |
| VIII Upstream fidelity | Nothing feeds projectM | Pass |
| X Evidence / unknown API behavior | Reference reuse on replug is unknown: handled both ways (D2), confirmation is the `{device}` task | Pass |
| Privacy | IDs and handles in memory only; nothing logged or stored | Pass |
| No networking (FR-068, ADR-0038) | Network endpoints are never listed, so never connected | Pass |
| Accessibility (ACC-004) | Reconnect announcement on `.midi` | Pass |
| Permissions (FILE-013) | No new usage key; no new UserDefaults key | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/166-midi-011-hotplug/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/hotplug.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/PerformanceControl/Sources/PerformanceControl/
├── MIDI/MIDISourceSubscriptions.swift     # new: protocol, registry, coalesced subscriptions
├── MIDI/ScriptedMIDISourceSystem.swift    # new: test system with handles + its input provider
├── MIDI/MIDIInputService.swift            # sourceLossCount
└── MIDISystem/CoreMIDIInputProvider.swift # notify block, CoreMIDISourceSystem, uses the subscriptions
Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIHotplugTests.swift   # new
Apps/projectM-iOS/
├── Coordinators/MIDIInputCoordinator.swift          # loss → observers
├── Coordinators/MIDIMappingCoordinator+Notes.swift  # loss releases held keys
├── Coordinators/MIDIMappingCoordinator.swift        # lastLossCount property
├── Coordinators/MIDIDiscoveryCoordinator.swift      # reconnected wording
├── Debug/UITestFakeMIDI.swift                       # fake input over the source system
└── Tests/MIDIHotplugCoordinatorTests.swift          # new
```

**Structure Decision**: extend MIDI-001/002 files; no new package.

## Complexity Tracking

None.
