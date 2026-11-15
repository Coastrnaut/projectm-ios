# Implementation Plan: OSC-006 OSC Bundles

**Branch**: `feature/osc-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Schedule bundle messages by their NTP time tag instead of applying them at receipt. At receipt the
`OSCDispatcher` reads its monotonic clock and an injected wall clock once, maps every message's effective tag
(raised to its enclosing bundle's tag) to a monotonic due time, applies what is due (late policy: ≤ 20 ms on
time, ≤ 1 s late applied and counted, older dropped), rejects what is more than 10 s ahead, and puts the rest in a
bounded `OSCBundleSchedule` (256 messages, ordered by due time then arrival sequence). One wake-up at a time runs
on the existing `OSCFlushScheduler`; due messages are dispatched through the unchanged per-message path (routes,
policy, learn, per-target limiter, live values). The receiver clears the schedule on stop and start.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26) · **Primary Dependencies**: PerformanceControl
(OSC), ParameterGraph · **Storage**: none (memory only; no new UserDefaults key) · **Testing**: XCTest: package
tests on the host and Linux (pure, injected clocks and a manual scheduler), the loopback integration test over a
real UDP listener (macOS/simulator), one app unit test on "OSC6 iPhone 17" (iOS 27.2) · **Target Platform**: iOS
26+ · **Performance Goals**: O(log n) insertion per message, O(k log n) per wake-up; no main-thread work per
message · **Constraints**: no new networking API; no encoder or sender (OSC-005 is parallel); the wall clock is the
only Foundation use, in one small file, and Linux keeps building.

## Constitution Check

- I Public APIs only: `Date` for the wall clock; the Network framework stays in `OSCTransport/` (FR-068, ADR-0008). PASS
- VI Modular boundaries: schedule logic pure in PerformanceControl; no app change beyond tests. PASS
- VII Real-time audio safety: wake-ups run on the scheduler's background task, never an audio or main thread. PASS
- X Evidence-based quality: deterministic acceptance tests with fake clocks; LAN sender check is `{device}`. PASS
- Privacy: nothing stored; counters only. PASS

## Project Structure

```text
Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCBundleSchedule.swift   (new: timing, wall clock, mapping, schedule)
Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCDispatcher.swift      (schedule bundles, wake-ups, counters, clear)
Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCReceiver.swift        (wall clock injection, clear on stop/start)
Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCPacket.swift          (comment only)
Packages/PerformanceControl/Tests/PerformanceControlTests/OSCBundleScheduleTests.swift (new: acceptance)
Packages/PerformanceControl/Tests/PerformanceControlTests/OSCDispatcherTests.swift  (OSC-002 bundle test uses "immediately")
Packages/PerformanceControl/Tests/PerformanceControlTests/OSCLoopbackIntegrationTests.swift (scheduled bundle over UDP)
Apps/projectM-iOS/Tests/OSCReceiverCoordinatorTests.swift                           (parameter changes at the scheduled time)
```

## Complexity Tracking

None.
