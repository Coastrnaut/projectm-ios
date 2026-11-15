# Implementation Plan: OSC-004 OSC Learn

**Branch**: `feature/osc-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Add OSC learn: on OSC Routes, Learn beside a routable parameter arms a one-shot capture in the
`OSCDispatcher`. The first decoded message that passed OSC-008 (allow list) and OSC-009 (rate limits) and has a
learnable address and one numeric argument is captured, the capture disarms in the same locked step, and the app
binds the address to the parameter as an OSC-003 user alias. A 10 s deadline on an injected clock, Cancel,
leaving the screen and the receiver stopping end learn. The session mirrors MIDI-003's `MIDILearnSession`.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26) · **Primary Dependencies**: PerformanceControl
(OSC), ParameterGraph, SwiftUI · **Storage**: the existing `settings.osc.aliases` (no new key) · **Testing**:
XCTest: package tests on the host and Linux (pure), app unit tests and one UI test on "OSC4 iPhone 17" (iOS 27.2)
· **Target Platform**: iOS 26+ · **Performance Goals**: O(1) extra work per message while armed (one flag check
when not armed); no main-thread work per message (one hop only on the single capture) · **Constraints**: no new
networking API, no new UserDefaults key, Linux-safe package code (no Foundation in the new package file).

## Constitution Check

- I Public APIs only: no new API; the Network framework stays in `OSCTransport/` (FR-068, ADR-0008). PASS
- VI Modular boundaries: pure learn logic in PerformanceControl; app glue in a new coordinator. PASS
- VII Real-time audio safety: nothing on audio threads; capture runs on the transport queue. PASS
- X Evidence-based quality: acceptance tests with a fake clock and fake transport; LAN check is `{device}`. PASS
- Privacy: no peer address, no value stored; only the alias the user asked for. PASS

## Project Structure

```text
Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCLearn.swift          (new: eligibility, session, binding)
Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCDispatcher.swift     (learn capture flag)
Packages/PerformanceControl/Tests/PerformanceControlTests/OSCLearnTests.swift      (new)
Apps/projectM-iOS/Coordinators/OSCLearnCoordinator.swift                           (new)
Apps/projectM-iOS/Coordinators/OSCRoutesCoordinator.swift                          (bindLearned)
Apps/projectM-iOS/Coordinators/OSCReceiverCoordinator.swift                        (learn, dispatcher, stop hook)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                                (one wiring line, fake receiver)
Apps/projectM-iOS/Views/OSCRoutesView.swift, Views/OSCLearnSection.swift (new), Views/SettingsView.swift (pass learn)
Apps/projectM-iOS/Debug/UITestFakeOSC.swift                                        (new, DEBUG only)
Apps/projectM-iOS/Tests/OSCLearnCoordinatorTests.swift, UITests/OSCLearnUITests.swift (new)
scripts/check_status_events.py                                                     (list the new files)
```

## Complexity Tracking

None.
