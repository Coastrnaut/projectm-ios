# Implementation Plan: OSC-001 OSC Receiver

**Branch**: `feature/osc-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/032-osc-001-osc-receiver/spec.md`

## Summary

A local-network OSC receiver, off by default. The pure parts live in the `PerformanceControl`
target and build and test on Linux: a bounded OSC message decoder (and a small encoder for tests and
OSC-005), the local-address scope check, the port rules, a one-parameter test catalog on MOD-001's
`ParameterStore`, a dispatcher that applies a value only where `ModulationPolicy.allowsExternalControl`
is true, and `OSCReceiver`, a lifecycle state machine over a transport protocol. The one transport
that touches the Network framework, `NetworkDatagramTransport` (an `NWListener` for UDP, cellular
prohibited, non-local peers dropped before any read, at most 8 peers), and a debug-only loopback sender for the
integration test live in `Sources/PerformanceControl/OSCTransport/`, the only folder FR-068 (amended,
ADR-0008) allows. The app adds two settings, an `OSCReceiverCoordinator` (foreground-only listener,
status text, test value) and an "OSC receiver" section in Settings; Info.plist gets
`NSLocalNetworkUsageDescription`; the privacy policy and App Privacy notes describe the listener.
Research: [research.md](research.md); entities: [data-model.md](data-model.md); API:
[contracts/osc-receiver.md](contracts/osc-receiver.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 language mode), Xcode 27.2; CI also Xcode 26.

**Primary Dependencies**: ParameterGraph (MOD-001) added to the `PerformanceControl` target;
Network framework (Apple, public) in `OSCTransport/` only, behind `#if canImport(Network)`;
Synchronization (`Mutex`). No third-party dependency.

**Storage**: two UserDefaults keys (`settings.osc.enabled`, `settings.osc.port`). Nothing received is
stored.

**Testing**: XCTest. `swift test --package-path Packages/PerformanceControl` on the macOS host
(decoder, fuzz, scope, dispatcher, receiver with a fake transport, loopback integration); the same
suite on Linux in CI (the integration test compiles out); app unit tests (settings, coordinator with
a fake transport); one UI test (`OSCReceiverUITests`).

**Target Platform**: iOS/iPadOS 26.0+, macOS 15+ (host tests), Linux (CI).

**Project Type**: SwiftPM library package plus the iOS app target.

**Performance Goals**: decoding a datagram of at most 1,472 bytes is a single bounded pass; the
fuzz of 20,000 packets finishes in under 1 s on the host (OSC-001-S3). The listener runs on its own
serial queue.

**Constraints**: FR-068 one-folder exception; local network only; off by default; foreground only;
no C stdio globals; no main-actor mutation in XCTest setUp/tearDown; explicit closure types for
Xcode 26; unit tests about 1 s, package suite < 1 min, UI test < 30 s (owner rule 7); no wall-clock
assertions (expectations with generous ceilings).

**Scale/Scope**: about 600 lines of package Swift, 450 lines of package tests, 200 lines of app
Swift, 150 lines of app tests and UI test.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | Network framework (`NWListener`, `NWConnection`, `NWParameters`), SwiftUI | Pass |
| II-III Capture | Not touched | Pass (n/a) |
| IV Truthful labeling | Status says "Listening" only after the system reports the listener ready | Pass |
| V No universal claims | No controller or app is named as working; the device LAN test is `{device}` and open | Pass |
| VI Modular boundaries | Decoder, scope, dispatcher and lifecycle are pure and transport-agnostic; the Network code is one replaceable transport behind a protocol | Pass |
| VII Real-time safety | Nothing on an audio callback; datagrams are decoded and applied on the transport's serial queue (OSC-001-R14); the parameter store's lock is never taken from audio | Pass |
| VIII ProjectM fidelity | The only route is the test parameter; nothing reaches projectM (OSC-001-R7) | Pass |
| IX Dependencies | None added; OSC is implemented from the public OSC 1.0 format | Pass |
| X Evidence | Host, Linux and simulator tests; LAN on a device is `{device}` and not claimed | Pass |
| Privacy / FR-068 | Amended FR-068: off by default, local only, one folder, usage description, privacy policy updated in this row (ADR-0008 ruling) | Pass |

Post-design re-check: unchanged (Pass). No ADR is needed: the exception and its conditions were
decided by the owner in ADR-0008; this row follows them.

## Project Structure

### Documentation (this feature)

```text
specs/032-osc-001-osc-receiver/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/osc-receiver.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/PerformanceControl/
├── Package.swift                                   # + ParameterGraph dependency
├── Sources/PerformanceControl/
│   ├── OSC/
│   │   ├── OSCMessage.swift                        # OSCMessage, OSCArgument
│   │   ├── OSCDecoder.swift                        # OSCDecoder, OSCDecodeError, OSCLimits
│   │   ├── OSCEncoder.swift                        # encoder (tests, loopback sender, OSC-005)
│   │   ├── OSCPeerAddress.swift                    # local-network scope check
│   │   ├── OSCPort.swift                           # port rules and parsing
│   │   ├── OSCReceiverCatalog.swift                # test parameter and route
│   │   ├── OSCDispatcher.swift                     # policy-checked apply + counters
│   │   ├── OSCDatagramTransport.swift              # transport protocol and events
│   │   └── OSCReceiver.swift                       # lifecycle state machine
│   └── OSCTransport/                               # the FR-068 folder: Network framework only here
│       ├── NetworkDatagramTransport.swift          # NWListener (UDP), #if canImport(Network)
│       └── OSCLoopbackSender.swift                 # #if DEBUG: test-only loopback sender
└── Tests/PerformanceControlTests/
    ├── OSCDecoderTests.swift                       # cases + fixed-seed fuzz
    ├── OSCPeerAddressTests.swift
    ├── OSCDispatcherTests.swift
    ├── OSCReceiverTests.swift                      # fake transport lifecycle
    └── OSCLoopbackIntegrationTests.swift           # real listener over loopback (macOS host)

Apps/projectM-iOS/
├── Coordinators/AppSettings.swift                  # oscEnabled, oscPort
├── Coordinators/OSCReceiverCoordinator.swift       # foreground-only listener, status, test value
├── Coordinators/AppCoordinator.swift               # owns it; scene activity
├── Views/SettingsView.swift                        # "OSC receiver" section
├── Views/VisualizerView.swift                      # passes the coordinator to Settings
├── Tests/OSCReceiverCoordinatorTests.swift
└── UITests/OSCReceiverUITests.swift
project.yml                                         # NSLocalNetworkUsageDescription
docs/privacy-policy.md, docs/release/app-privacy.md # listener disclosure
```

**Structure Decision**: the `OSCTransport/` folder holds only code that names Network framework
types, so the compliance boundary is as small as possible and everything else is Linux-testable.
`OSC/` sits beside it in the same target (the folder is inside the `PerformanceControl` target by
the owner's ruling).

## Complexity Tracking

None.
