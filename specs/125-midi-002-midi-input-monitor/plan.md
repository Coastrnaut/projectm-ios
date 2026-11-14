# Implementation Plan: MIDI-002 MIDI Input Monitor

**Branch**: `feature/midi-002` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/125-midi-002-midi-input-monitor/spec.md`

## Summary

MIDI-002 adds the first received MIDI messages, in the same split MIDI-001 used: a pure,
Linux-testable core in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/` and the one
system implementation in `MIDISystem/`, compiled only `#if canImport(CoreMIDI)`.

Pure core (`MIDI/`):

- `MIDIEvent` (16-byte value: kind, channel, number, value, timestamp in nanoseconds), its
  `MIDIControlKey` (kind + channel + number, for MIDI-003 learn) and `normalizedValue` (for
  MIDI-004 scaling). No source field: identifiers cannot reach an event (MIDI-002-R7).
- `MIDIUMPDecoder`: Universal MIDI Packet words, MIDI 1.0 protocol (message types 0x1 system,
  0x2 MIDI 1.0 channel voice, 0x3 SysEx7 as length only; every other type skipped by its word
  count). Research MIDI-002-D1.
- `MIDIByteStreamParser`: MIDI 1.0 bytes with running status, real-time bytes interleaved,
  SysEx length only, stray data ignored. Used by the scripted provider and kept for any legacy
  byte source. Research MIDI-002-D2.
- `MIDIEventRing`: single-producer/single-consumer ring of 512 preallocated events with
  `Synchronization.Atomic` indices; drop-newest when full (counted); timing clock and active
  sensing are counted in atomics, never stored (MIDI-002-R4, R5). Research MIDI-002-D3.
- `MIDIInputProvider` protocol, `MIDIInputService` (state off / receiving / unavailable; opens
  the input once, connects exactly the given source IDs, idempotent start and stop; resets the
  ring's consumer on stop) and `ScriptedMIDIInputProvider` (bytes in, delivered only while open
  and connected to at least one source).
- `MIDIEventText`: type, channel, number and value texts and the spoken label (note names with
  60 = C4), built in typed steps.

System (`MIDISystem/CoreMIDIInputProvider.swift`): its own `MIDIClientCreateWithBlock` client
(kept for the process, as MIDI-001 does) and one input port from
`MIDIInputPortCreateWithProtocol(…, ._1_0, …)`, created on first open and kept; `connect(sources:)`
re-enumerates endpoints, assigns IDs with MIDI-001's rule and connects (`MIDIPortConnectSource`,
`connRefCon` nil) exactly the requested sources, disconnecting the rest. The receive block walks
the `MIDIEventList` in place, converts the host timestamp to nanoseconds with a precomputed
timebase and hands the words to `MIDIUMPDecoder` writing into the ring: no allocation, lock,
logging or dispatch per message. Research MIDI-002-D4.

App:

- `MIDIInputCoordinator` (`Coordinators/`, `@MainActor`): the shared input for MIDI-002 and later
  rows. Clients register by name with a batch handler; it receives iff a client is registered and
  MIDI-001 discovery is listening, passes the listed online inputs to the service on every list
  change, and drains the ring on a `CADisplayLink` capped at 30 Hz while receiving, fanning each
  batch out to clients. Research MIDI-002-D5.
- `MIDIMonitorCoordinator` (`Coordinators/`, `@MainActor @Observable`): entries (newest first, 64),
  pause/resume, clear, counters, status text; opens and closes its client with the screen.
- `MIDIMonitorView` (`Views/`): list rows with combined labels, Pause and Clear buttons, a summary
  line; reached by a `NavigationLink` row added to `MIDISettingsSection` (no `SettingsView` edit).
- `MIDIDiscoveryCoordinator`: one small addition, list-change observers for the input coordinator.
- DEBUG `UITestFakeMIDI`: a `ScriptedMIDIInputProvider` and "Send CC" / "Send Note" buttons on the
  monitor screen when `-uitestFakeMIDI` is set.
- No announcement for live traffic; both new app files join `check_status_events.py`'s list.
- ADR-0038 is amended (Decision 7: receiving), no new ADR.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/midi-input.md](contracts/midi-input.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: CoreMIDI (system framework: client, input port with protocol, connect and
disconnect source, enumeration and property calls). No new package dependency, no networking.

**Storage**: none new. Entries live in memory while the monitor is open.

**Testing**: `Packages/PerformanceControl`: `MIDIMessageDecodingTests` (UMP and byte-stream tables),
`MIDIEventRingTests` (overflow, counters, fixed storage over 10,000 messages), `MIDIInputServiceTests`
(lifecycle, sources, unavailable), `MIDIEventTextTests`; host and the Linux shape
`-Xswiftc -DANALYSIS_NO_ACCELERATE`. App: `MIDIMonitorCoordinatorTests` (acceptance: injected CC and
notes render, privacy scan, pause/clear/cap, receiving only while needed). UI: `MIDIMonitorUITests`
(`-uitestFakeMIDI`). Scripts: `check_status_events.py` list, rule tests unchanged.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (pure core).

**Project Type**: iOS app plus SwiftPM package.

**Performance Goals**: callback cost O(words) with no allocation; drain at ≤ 30 Hz; at most 64 rows.

**Constraints**: public APIs only; explicit closure types; typed steps; no C stdio globals; no
main-actor mutation in setUp/tearDown; no wall-clock assertions (injected clock, manual drain);
SwiftUI bodies under the 300 ms type-check warning; unit tests about 1-2 s, UI test under 30 s.
Parallel work: FX-003 and MED-004; `SettingsView.swift` is not edited, `AppCoordinator.swift` gets a
few lines.

**Scale/Scope**: about 8 new package sources/tests, 2 coordinators, 1 view, debug additions, 1 app
test file, 1 UI test file.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Documented CoreMIDI input port, event list and connect calls | Pass |
| VI Modular boundaries | Pure decoders, ring and service behind `MIDIInputProvider`; system code in `MIDISystem/`; views only show | Pass |
| VII Real-time safety | Callback writes into a preallocated SPSC ring; no allocation, lock, log or hop; bounded with a tested drop-newest policy; drain on the main thread at display rate; idempotent start/stop | Pass |
| X Evidence | Fake MIDI on the Mac; a physical controller is a `{device}` task (S8) | Pass |
| Privacy | Events carry no source; nothing stored or logged; entries dropped on close; scanned in tests | Pass |
| No networking (FR-068, ADR-0008) | Network MIDI endpoints are never listed, so never connected; binary scan unchanged | Pass |
| Accessibility (ACC-001, ACC-004, ACC-011) | Combined row labels; no live announcements; no animation | Pass |
| Permissions (FILE-013) | No new usage key | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/125-midi-002-midi-input-monitor/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/midi-input.md
└── checklists/requirements.md
docs/adr/0038-midi-local-endpoint-scope.md   # amended (Decision 7)
```

### Source Code (repository root)

```text
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/
├── MIDIEvent.swift                 # event, kind, control key, normalized value
├── MIDIUMPDecoder.swift            # UMP words → events
├── MIDIByteStreamParser.swift      # bytes → events (running status)
├── MIDIEventRing.swift             # SPSC ring, drop-newest, real-time counters
├── MIDIInputService.swift          # provider protocol + lifecycle
├── ScriptedMIDIInputProvider.swift
└── MIDIEventText.swift             # display and spoken texts
Packages/PerformanceControl/Sources/PerformanceControl/MIDISystem/
└── CoreMIDIInputProvider.swift     # #if canImport(CoreMIDI)
Packages/PerformanceControl/Tests/PerformanceControlTests/
├── MIDIMessageDecodingTests.swift, MIDIEventRingTests.swift
├── MIDIInputServiceTests.swift, MIDIEventTextTests.swift
Apps/projectM-iOS/
├── Coordinators/MIDIInputCoordinator.swift, MIDIMonitorCoordinator.swift   # new
├── Coordinators/MIDIDiscoveryCoordinator.swift, AppCoordinator.swift       # small edits
├── Views/MIDIMonitorView.swift                                             # new
├── Views/MIDISettingsSection.swift                                         # one row
├── Debug/UITestFakeMIDI.swift                                              # input stand-in
├── Tests/MIDIMonitorCoordinatorTests.swift                                 # new
└── UITests/MIDIMonitorUITests.swift                                        # new
scripts/check_status_events.py
```

**Structure Decision**: extend MIDI-001's folders in PerformanceControl; no new package.

## Complexity Tracking

None.
