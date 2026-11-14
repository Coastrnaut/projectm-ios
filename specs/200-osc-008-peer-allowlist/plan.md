# Implementation Plan: OSC-008 OSC Peer Allowlist

**Branch**: `feature/osc-008` | **Date**: 2026-11-14 | **Spec**: `specs/200-osc-008-peer-allowlist/spec.md`

## Summary

Let the user restrict OSC to approved local hosts. The transport already reads each peer's address for
OSC-001's local check; it now also hands that address (memory only) to the receiver with each datagram.
The receiver asks a pure `OSCPeerAllowlist` before the dispatcher sees the datagram: while the allowlist
is on, a datagram from a host that is not approved (or from an unknown host) is dropped before rate
limiting and decoding, counted, and its host noted as recently blocked. Settings gets an "Approved
Devices" screen. Off by default, so OSC is unchanged unless the user opts in.

## Technical Context

**Language/Version**: Swift 6.4 (Xcode 27.2), SwiftUI

**Primary Dependencies**: `Packages/PerformanceControl` (pure Swift OSC, Linux-tested); Network
framework only in `OSCTransport/` (unchanged scope)

**Storage**: UserDefaults: `settings.osc.peerAllowlist.enabled` (Bool), `settings.osc.approvedPeers` ([String])

**Testing**: XCTest package tests (fake transport, seeded fuzz, loopback integration on Apple hosts);
app unit tests on "OSC8 iPhone 17" (iOS 27.2); one XCUITest under 30 s

**Target Platform**: iOS/iPadOS 26+ (app), macOS 15 and Linux (package tests)

**Project Type**: mobile app + Swift packages

**Performance Goals**: O(1) per datagram (one lock and one set lookup); no main-thread work per datagram

**Constraints**: no new network capability (OSC-008-R13); no wall-clock assertions; test budgets of owner rule 7

**Scale/Scope**: ≤16 approved hosts, ≤4 recently blocked hosts

## Constitution Check

- **I Public APIs only**: reads `NWEndpoint.host`, already used for the local check; no new symbol (`check_network_symbols`). PASS
- **VI Modular boundaries**: rule and filter in `PerformanceControl` (pure, Linux); app glue in a coordinator. PASS
- **VII Real-time safety**: OSC never runs on an audio thread; unchanged. PASS
- **VIII Upstream fidelity**: nothing reaches projectM. PASS
- **X Evidence**: acceptance test plus seeded fuzz; LAN check tagged `{device}`. PASS
- **Privacy**: approved hosts are stored only on the device, excluded from backups, erased with Settings;
  blocked hosts memory only; the privacy policy is updated. This narrows OSC-001-R13/R15, recorded in
  ADR-0058. PASS with ADR.

Re-check after design: unchanged, PASS.

## Project Structure

### Documentation

```text
specs/200-osc-008-peer-allowlist/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/osc-peer-allowlist.md
└── tasks.md
```

### Source Code

- `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCPeerAllowlist.swift` (new: host normalization, text form, allowlist)
- `OSC/OSCDatagramTransport.swift` (`.datagram` gains `peer:`), `OSC/OSCReceiver.swift` (filter before dispatch),
  `OSC/OSCDispatcher.swift` (`droppedUnapproved` counter)
- `OSCTransport/NetworkDatagramTransport.swift` (pass the address it already computed)
- Tests: `OSCPeerAllowlistTests.swift` (rule, text, acceptance, fuzz), `OSCLoopbackIntegrationTests.swift` (one case)
- `Apps/projectM-iOS/Coordinators/OSCPeersCoordinator.swift`, `Views/OSCPeersView.swift` (new)
- `OSCReceiverCoordinator.swift`, `AppCoordinator.swift`, `SettingsView.swift` (small edits)
- Keys: `LibrarySettings.swift` (excluded), `scripts/run_device_tests.py`, UI-test reset
- `docs/privacy-policy.md`, `docs/adr/0058-osc-peer-allowlist.md`

**Structure Decision**: follow OSC-003: pure logic in the package, app coordinator plus a pushed Settings screen.

## Complexity Tracking

None.
