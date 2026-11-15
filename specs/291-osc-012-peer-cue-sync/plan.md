# Implementation Plan: OSC-012 Peer Cue Sync

**Branch**: `feature/osc-012` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

A leader device sends its active cue to one approved follower; the follower steps its show to that cue. Pure
Swift in PerformanceControl (`OSC/OSCCueSync.swift`) holds the wire message `/projectm/cue ,siii` (cue ID, seq,
offset ms, session), the leader's bounded send schedule (burst at 0/100/300 ms, then a 2 s heartbeat), the
follower's newest-seq rule with unknown-cue and approval checks, and a bounded receive inbox with at most one
pending main-thread hop. Sending reuses OSC-005's reviewed `OSCSender` (new `postCue`, same 60/s cap, same flow
to the one literal local destination, no new network code). Receiving reuses OSC-001's receiver: the dispatcher
gets one message tap for `/projectm/cue`, reached only after the allow list (OSC-008) and the datagram rate
limits (OSC-009). The app's `OSCCueSyncCoordinator` stores the role (Off/Lead/Follow, one device-only key),
chains onto `ShowCoordinator.cueStarted` to learn cue changes and their start times, runs the leader's timer
while Lead is chosen, drains the follower's inbox and steps the show with `stepNow(.go(id))`, and holds SHOW-002's
timed advance while following. A "Cue Sync" screen sits behind one row in Settings › OSC. ADR-0102 records the
new outbound message class (amends ADR-0088 decision 4).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26) · **Primary Dependencies**: PerformanceControl
(OSC, existing sender and receiver), ShowControl/ShowCoordinator (SHOW-001), SwiftUI · **Storage**: one
UserDefaults key `settings.osc.cueSync.role`, device-only · **Testing**: XCTest: pure package tests with an
injected clock and a seeded lossy fake network (also Linux), a dispatcher-tap test through `OSCReceiver` with a
fake transport, a real-UDP loopback test on 127.0.0.1 (macOS host and simulator), app unit tests with a fake send
transport and a temporary show store, one UI test on "OSC12 iPhone 17" (iOS 27.2) · **Target Platform**: iOS 26+
· **Performance Goals**: ≤ 3 sends per cue change plus 1 per 2 s; ≤ 1 pending main-actor hop for received cues;
no work while Off · **Constraints**: no networking API outside `OSCTransport/` (none added at all), no new
destination type, no wall-clock dependence, Linux-safe package code.

## Constitution Check

- I Public APIs only: no new framework use; the existing reviewed sender and listener. PASS
- Privacy / FR-068 (ADR-0008, ADR-0088): opt-in (Off by default), local network only, one literal local destination, approved peers only (allow list required for both roles), no relay; the message carries a cue UUID, two counters and a random session number only. ADR-0102 records the new message class. PASS
- VI Modular boundaries: pure model in PerformanceControl, one dispatcher hook, glue in one app coordinator and one view file; small edits to shared files (`AppCoordinator`, `SettingsView`, `OSCReceiverCoordinator`, `OSCSendCoordinator`, `AppCoordinator+Show`). PASS
- Audio/capture path untouched; nothing runs on audio threads. PASS
- Tests short (owner rule 7): fixtures simulate 60 s on an injected clock in milliseconds of real time. PASS

Post-design re-check: unchanged, PASS.

## Project Structure

```text
specs/291-osc-012-peer-cue-sync/  spec, plan, research, data-model, contracts/osc-cue-sync.md, quickstart, tasks
docs/adr/0102-osc-peer-cue-sync.md
Packages/PerformanceControl/Sources/PerformanceControl/OSC/
  OSCCueSync.swift          (new: role, message, leader, follower, inbox)
  OSCDispatcher.swift       (message tap, `.tapped` outcome, `tapped` counter)
  OSCSender.swift           (`postCue`)
Packages/PerformanceControl/Tests/PerformanceControlTests/
  OSCCueSyncTests.swift, OSCCueSyncLossTests.swift, OSCCueSyncLoopbackTests.swift
Apps/projectM-iOS/Coordinators/OSCCueSyncCoordinator.swift (new)
Apps/projectM-iOS/Views/OSCCueSyncView.swift (new)
Apps/projectM-iOS/Tests/OSCCueSyncCoordinatorTests.swift (new)
Apps/projectM-iOS/UITests/OSCCueSyncUITests.swift (new)
small edits: OSCReceiverCoordinator, OSCSendCoordinator, AppCoordinator (+Show), SettingsView,
  run_device_tests.py ALLOWED_KEYS, LibrarySettings excludedKeys, LibraryBackupAppTests, privacy policy text
```

## Complexity Tracking

None: no new network code, no new dependency.
