# Implementation Plan: OSC-011 Local Peer Discovery

**Branch**: `feature/osc-011` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add opt-in Bonjour discovery for OSC peers on the local link. Pure Swift in PerformanceControl
(`OSC/OSCDiscovery.swift`) holds the service type `_projectm-osc._udp`, the `local.` domain, the per-launch
announced name ("projectM XXXX"), name cleaning, the found-device model and the activity rule (browse / announce
only while their switch, the OSC receiver switch and the foreground all hold). The browser protocol
`OSCPeerBrowsing` keeps the lifecycle testable with fakes. Two reviewed transport pieces live in `OSCTransport/`,
the only folder FR-068 allows the Network framework: `NetworkOSCPeerBrowser` (an `NWBrowser` for the one Bonjour
type, cellular and peer-to-peer off, each result resolved to its local address with a short UDP `NWConnection`
that sends nothing) and announcing through the receiver's own listener (`NWListener.service`), so the
announcement carries the real port and disappears with the listener. `OSCReceiver` gains
`setAdvertisement(_:)`, applied to the current and every later transport. The app's `OSCDiscoveryCoordinator`
stores two device-only switches, follows `OSCReceiverCoordinator.apply()` (switch and foreground, as OSC-005's
sender does), shows found devices and offers explicit "Allow" (OSC-008) and "Use as send destination" (OSC-005).
A "Nearby Devices" screen sits behind one row in Settings › OSC. `NSBonjourServices` declares only the app's
type. ADR-0100 records the policy change; `check_network_symbols.py` accepts `NWBrowser` and service
announcing only in the image that defines the reviewed browser, and `check_compliance.py` pins the service
type and rejects other endpoints in the discovery source.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26) · **Primary Dependencies**: PerformanceControl
(OSC), Network.framework (only in `OSCTransport/`), SwiftUI · **Storage**: two UserDefaults keys
(`settings.osc.discovery.browse`, `settings.osc.discovery.advertise`), device-only · **Testing**: XCTest:
pure package tests (also Linux), a host loopback test of announce + browse (skipped when the host's mDNS does
not answer in 5 s), app unit tests with a spy browser factory and a spy receiver transport, one UI test with a
fake browser on "OSC11 iPhone 17" (iOS 27.2), Python script tests for the scan rules · **Target Platform**:
iOS 26+ · **Performance Goals**: no work while off; results coalesced to one main-actor refresh per browser
change; at most 16 resolutions · **Constraints**: no DNS beyond mDNS on the local link, no host names, no
relay, no networking API outside `OSCTransport/`, Linux-safe package code (`#if canImport(Network)`).

## Constitution Check

- I Public APIs only: `NWBrowser`, `NWListener.Service`, `NWConnection` (public Network.framework); no `DNSService*`, no `nw_*`, no `NSNetService`. PASS
- Privacy / FR-068 (amended, ADR-0008): opt-in, both switches off by default, behind the OSC switch; local link only; generic announced name; nothing stored but two switches. ADR-0100 records the change. PASS
- VI Modular boundaries: pure logic in PerformanceControl, Network code in `OSCTransport/`, glue in one app coordinator and one view file. PASS
- VII Real-time audio safety: nothing on audio threads; browser on its own queue. PASS
- VIII projectM boundary: nothing feeds projectM. PASS
- X Evidence: fakes and spies for lifecycle, scan tests for no-relay; LAN discovery between two devices is `{device}`. PASS

## Project Structure

```text
Packages/PerformanceControl/Sources/PerformanceControl/
  OSC/OSCDiscovery.swift                 # type, domain, names, found device, activity rule, browser protocol
  OSC/OSCDatagramTransport.swift         # + advertise(_:) with a default no-op
  OSC/OSCReceiver.swift                  # + setAdvertisement(_:)
  OSCTransport/NetworkDatagramTransport.swift   # + listener.service
  OSCTransport/NetworkOSCPeerBrowser.swift      # NWBrowser + resolution
Packages/PerformanceControl/Tests/PerformanceControlTests/
  OSCDiscoveryTests.swift, OSCDiscoveryLoopbackTests.swift
Apps/projectM-iOS/
  Coordinators/OSCDiscoveryCoordinator.swift
  Views/OSCDiscoveryView.swift
  Debug/UITestFakeDiscovery.swift
  Tests/OSCDiscoveryCoordinatorTests.swift
  UITests/OSCDiscoveryUITests.swift
scripts/check_network_symbols.py, scripts/check_compliance.py, scripts/test_scripts.py
project.yml (NSBonjourServices, usage string), PermissionCatalog.swift, docs/privacy-policy.md
docs/adr/0100-osc-local-peer-discovery.md
key lists: run_device_tests.py, LibrarySettings.swift, LibraryErasePolicy.swift, AppCoordinator reset, LibraryBackupAppTests
```

**Structure Decision**: extend the existing OSC package and app coordinators; no new package.

## Complexity Tracking

None.
