# Implementation Plan: OSC-009 OSC Rate Limiter

**Branch**: `feature/osc-009` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

## Summary

Token-bucket limits per source (200/s, burst 50), across all sources (500/s, burst 100) and per
target (60/s, burst 10), checked before decoding (datagram limits) and before applying (target
limit, with latest-value coalescing and one deferred flush). Deterministic: integer arithmetic on an
injected monotonic clock. The app copies OSC state to the main thread through a gate: one pending
refresh, at most ~30/s. Research: [research.md](research.md); contract:
[contracts/osc-rate-limiter.md](contracts/osc-rate-limiter.md).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the build Mac; CI also Xcode 26 and Linux)

**Primary Dependencies**: ParameterGraph (store), Synchronization (`Mutex`); Network only in
`OSCTransport/` (one line: source numbering)

**Storage**: none (in-memory counters only)

**Testing**: XCTest — package tests on the host and Linux; app unit and one UI test on an iOS 27.2
simulator

**Target Platform**: iOS 26+ app; PerformanceControl also macOS host and Linux

**Project Type**: mobile app + Swift packages

**Performance Goals**: O(1) limiter per datagram; ≤500 decodes/s; ≤60 applies/s per target; ≤30
main-thread refreshes/s

**Constraints**: no wall clock; bounded memory (16 + 64 table entries); tests ~1-2 s each (owner rule 7)

**Scale/Scope**: ~5 new source files, ~4 changed, 4 test files

## Constitution Check

| Principle | Check |
|---|---|
| I Public APIs | Pure Swift; Network stays in `OSCTransport/` (FR-068 amendment) — pass |
| IV Truthful labeling | "Rate-limited N" counts exactly what was dropped or held — pass |
| VI Modular boundaries | Limiter in PerformanceControl, Linux-testable; app only gates refreshes — pass |
| VII Real-time audio safety | Nothing runs on an audio thread — pass |
| VIII projectM fidelity | No OSC value reaches projectM (OSC-001-R7) — pass |
| X Evidence | Unit, flood fixture, app tests; device LAN check left `{device}` — pass |
| Privacy | No addresses or payloads stored (opaque source numbers) — pass |

No violations; re-checked after design: unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/041-osc-009-osc-rate-limiter/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/osc-rate-limiter.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/PerformanceControl/Sources/PerformanceControl/OSC/
├── OSCRateLimiter.swift        # new: OSCRateLimit(Configuration), OSCTokenBucket, OSCRateLimiter
├── OSCMonotonicClock.swift     # new: clock + flush scheduler + OSCRefreshGate
├── OSCDispatcher.swift         # limits, coalescing, flush, counters
├── OSCReceiver.swift           # source-aware events, resetLimits, onActivity
└── OSCDatagramTransport.swift  # OSCSourceID, .datagram(_, source:)
Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport/NetworkDatagramTransport.swift  # source numbers
Packages/PerformanceControl/Tests/PerformanceControlTests/
├── OSCRateLimiterTests.swift   # new
├── OSCFloodTests.swift         # new (acceptance fixture)
└── OSCRefreshGateTests.swift   # new
Apps/projectM-iOS/Coordinators/OSCReceiverCoordinator.swift   # gated refresh, rateLimitedCount
Apps/projectM-iOS/Views/SettingsView.swift                    # "Rate-limited N"
Apps/projectM-iOS/Tests/OSCReceiverCoordinatorTests.swift      # flood coalescing test
Apps/projectM-iOS/UITests/OSCRateLimiterUITests.swift          # new, one test < 30 s
```

**Structure Decision**: extend the existing OSC folder; no new package or target.

## Complexity Tracking

None.
