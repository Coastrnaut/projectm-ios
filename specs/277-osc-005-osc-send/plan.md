# Implementation Plan: OSC-005 OSC Send

**Branch**: `feature/osc-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Add an opt-in OSC sender. Pure Swift in PerformanceControl (`OSC/OSCSend.swift`, `OSC/OSCSender.swift`)
validates the destination (literal local address only), builds the three message kinds with the existing
`OSCEncoder`, gates beats to once per beat, caps the total at 60 messages per second on an injected clock, and
drives an `OSCSendTransport`. The one real transport, `NetworkOSCSender`, lives in `OSCTransport/` (the only
folder FR-068 allows the Network framework) and uses a UDP `NWConnection` to the validated host, never over
cellular; closing it bumps a generation synchronously so queued sends are dropped, then cancels the connection.
The app's `OSCSendCoordinator` stores five device-only keys, follows the OSC receiver switch (OSC-007), the
foreground, and OSC-008's allow list, polls the tempo grid for beats while beats are on, and receives scene and
status events from three one-line hooks in `AppCoordinator`. A "Send OSC" screen sits behind one row in
Settings › OSC. ADR-0088 lets `check_network_symbols.py` accept outbound `NWConnection` APIs in the image that
defines the reviewed sender, also in Release.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26) · **Primary Dependencies**: PerformanceControl
(OSC), Network.framework (only in `OSCTransport/`), SwiftUI · **Storage**: five UserDefaults keys
(`settings.osc.send.enabled`, `.host`, `.port`, `.kinds`, `.sceneNames`), device-only · **Testing**: XCTest:
package tests on the host (pure ones also on Linux), the real-UDP loopback test on the macOS host, app unit tests
(with the receiver's `NetworkDatagramTransport` as the loopback fixture) and one UI test on "OSC5 iPhone 17"
(iOS 27.2) · **Target Platform**: iOS 26+ · **Performance Goals**: O(1) per event; beat poll every 50 ms only
while beats are on and sending is active; no main-thread work per sent message beyond the event call ·
**Constraints**: no DNS, no host names, no networking API outside `OSCTransport/`, Linux-safe package code
(`#if canImport(Network)` around the transport).

## Constitution Check

- I Public APIs only: Network.framework `NWConnection` (public); no sockets, no `nw_*`. PASS
- Privacy / FR-068 (amended, ADR-0008): opt-in, off by default, local addresses only, no cellular, no DNS; names only on the user's choice; nothing stored but the five settings. ADR-0008 already lists OSC-005 among the rows unblocked by policy; ADR-0088 records the outbound scan rule. PASS
- VI Modular boundaries: pure logic in PerformanceControl, transport in `OSCTransport/`, glue in one app coordinator. PASS
- VII Real-time audio safety: nothing on audio threads; events come from the main actor; the transport has its own queue. PASS
- VIII projectM boundary: nothing feeds projectM. PASS
- X Evidence: byte-exact loopback tests, injected clocks; LAN check is `{device}`. PASS

## Project Structure

```text
Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCSend.swift            (new: destination, kinds, events, messages, cap, beat gate)
Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCSender.swift          (new: transport protocol, sender engine)
Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport/NetworkOSCSender.swift (new: NWConnection UDP)
Packages/PerformanceControl/Tests/PerformanceControlTests/OSCSendTests.swift        (new: pure)
Packages/PerformanceControl/Tests/PerformanceControlTests/OSCSendLoopbackTests.swift (new: real UDP, macOS host)
Apps/projectM-iOS/Coordinators/OSCSendCoordinator.swift                             (new)
Apps/projectM-iOS/Coordinators/OSCReceiverCoordinator.swift                         (one hook: conditions changed)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift, AppCoordinator+Show.swift      (wiring, three event lines, reset keys)
Apps/projectM-iOS/Views/OSCSendView.swift (new), Views/SettingsView.swift (one row)
Apps/projectM-iOS/Tests/OSCSendCoordinatorTests.swift, UITests/OSCSendUITests.swift (new)
Apps/projectM-iOS/Coordinators/PermissionCatalog.swift, project.yml, docs/privacy-policy.md (usage string, policy)
Packages/LibraryBackup/... LibrarySettings.swift, LibraryErasePolicy.swift; scripts/run_device_tests.py; LibraryBackupAppTests (keys)
scripts/check_network_symbols.py, scripts/test_scripts.py, docs/adr/0088-osc-send-outbound.md
```

## Complexity Tracking

None.
