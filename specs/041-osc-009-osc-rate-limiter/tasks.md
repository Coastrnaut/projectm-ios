# Tasks: OSC-009 OSC Rate Limiter

**Input**: `specs/041-osc-009-osc-rate-limiter/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: test-first (the row's acceptance is a flood fixture). No wall-clock assertions: a fake
monotonic clock and a manual flush scheduler in package tests; counts, not time, bound the work. Unit
tests about 1-2 s (≤ 10 s), package suite < 1 min, UI test < 30 s (owner rule 7). Device-only checks
are tagged `{device}` and are not run by this row.

Format: `- [ ] OSC-009-Tnn [P?] [Story?] description`. A task is ticked only when verified, with
" — Verified 2026-11-13: <how>".

## Phase 1: Setup

- [X] OSC-009-T01 Record the baseline before any change: `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `swift test --package-path Packages/PerformanceControl`; note results here. — Verified 2026-11-13: before any change: check_compliance OK, validate_docs OK (397 files), PerformanceControl 73 tests 0 failures (1.27 s); PosterBoard reports 32.

## Phase 2: Foundational — clock, buckets, limiter (tests first)

- [X] OSC-009-T02 [P] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCRateLimiterTests.swift` with a fake clock: burst then exact refill (rate 200, burst 50: 50 at t=0, then exactly 1 per 5 ms), a clock jump refills to the burst only, a backwards clock refills nothing; per-source isolation (one source exhausted, another still admitted); the global cap across sources ("500/s, burst 100"); a source-limited datagram spends no global token; target limit 60/s burst 10; per-target isolation; coalescing (held value replaced by newer, `takeDue` returns only the latest, at the target's next token; `nextDue` is the exact delay); a direct apply discards an older held value; eviction at the caps ("at most 16 source buckets and 64 target buckets, least recently used evicted"), an evicted target's held value returned for application; `reset()` clears everything. — Verified 2026-11-13: OSCRateLimiterTests, 10 tests pass (0.015 s), `swift test --filter OSCRateLimiterTests`. No red run was recorded (tests and code written in one step).
- [X] OSC-009-T03 Implement `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCRateLimiter.swift` (`OSCRateLimit` with "`perSecond` ≥ 1" and "`burst` 1…1,000", `OSCRateLimitConfiguration.default`, `OSCTokenBucket`, `OSCSourceID`, `OSCRateLimiter`, `OSCTargetDecision`) and `OSCMonotonicClock.swift` (`OSCMonotonicClock`, `OSCFlushScheduler`, `OSCRefreshGate`) per research OSC-009-D1, D2, D5 to D7; T02 passes. — Verified 2026-11-13: OSCRateLimiter.swift and OSCMonotonicClock.swift; T02 and T07 pass.

## Phase 3: User Story 1 — a flood cannot freeze the visualizer (P1)

- [X] OSC-009-T04 [US1] Add `OSCSourceID` to the transport event (`.datagram([UInt8], source: OSCSourceID = .unattributed)`) in `OSC/OSCDatagramTransport.swift`, number accepted peers from 1 in `OSCTransport/NetworkDatagramTransport.swift`, pass the source through `OSCReceiver.handle`. — Verified 2026-11-13: `.datagram([UInt8], source:)` with default `.unattributed`; NetworkDatagramTransport numbers peers from 1; package builds with `-warnings-as-errors`; the loopback integration tests pass (0.509 s, 0.005 s).
- [X] OSC-009-T05 [US1] Extend `OSC/OSCDispatcher.swift`: limits, clock and scheduler in `init`; `handle(_:source:)` checks the datagram limits before decoding (`.rateLimited`, `rateLimited` counter) and the target limit before applying (`.coalesced`, `coalesced` counter; non-finite values refused before holding); store writes under the lock; `flush()`, at most one scheduled; `resetLimits()`. Extend `OSC/OSCReceiver.swift`: `limits`, `clock`, `scheduleFlush` parameters, `resetLimits()` on launch and stop, `onActivity(_:)`. — Verified 2026-11-13: OSCDispatcher (limits, `.rateLimited`/`.coalesced`, flush, resetLimits, onActivity) and OSCReceiver (limits/clock/scheduler, reset on launch and stop); exercised by T06 and T10; existing dispatcher and receiver tests unchanged and passing.
- [X] OSC-009-T06 [US1] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCFloodTests.swift`, the acceptance fixture: 100,000 `/projectm/test` datagrams from 3 sources through the receiver (fake transport) with a fake clock advancing 1 ms per 50 datagrams and the manual scheduler run when due; assert applied updates never exceed `burst + rate × window` for every window (sliding, from the recorded apply times), decoded datagrams ≤ `100 + 500 × 2 s`, every other datagram counted `rateLimited`, at most one flush pending at any time (OSC-009-S1, S3); datagrams to an unknown address and malformed ones take no target slot (OSC-009-R4); final value equals the last value that passed the datagram limits, and a value sent 100 ms after the flood is applied (S2). — Verified 2026-11-13: OSCFloodTests.testFloodFromThreeSourcesNeverExceedsTheConfiguredRates (0.161 s) and testIgnoredAndMalformedMessagesTakeNoTargetSlot pass: 100,000 datagrams, decoded ≤ 100 + 500/s, busiest 1 ms/100 ms/1 s apply windows within 10 + 60/s, at most one flush pending, final value = last admitted, post-flood value applied; testStopDiscardsHeldValuesAndRestartStartsWithFullBuckets passes.
- [X] OSC-009-T07 [US1] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCRefreshGateTests.swift`: first request runs at once (delay 0); requests while pending return nil; after `begin` at t, the next request's delay is `t + 1/30 s − now`; 10,000 requests over 1 simulated second start at most 31 refreshes (OSC-009-S4, rate part). — Verified 2026-11-13: OSCRefreshGateTests, 2 tests pass (0.001 s): one pending, interval, 10,000 requests over 1 simulated second start 29-31 refreshes.
- [ ] OSC-009-T08 [US1] App: `Apps/projectM-iOS/Coordinators/OSCReceiverCoordinator.swift` refreshes through `OSCRefreshGate` from `receiver.onActivity` (one pending main-actor task; `refreshCount` for tests; `rateLimitedCount`), and `Apps/projectM-iOS/Tests/OSCReceiverCoordinatorTests.swift` gains `testFloodCoalescesMainActorRefreshes`: 10,000 datagrams sent synchronously on the main actor start at most one pending refresh (refreshCount ≤ 2 after the flood is drained) and the shown test value ends at the last value sent (OSC-009-S4, one-pending part; the rate part is T07).
- [X] OSC-009-T09 [US1] Run the whole PerformanceControl suite, including `OSCLoopbackIntegrationTests` and the existing dispatcher and receiver tests (OSC-009-S5). — Verified 2026-11-13: `swift test --package-path Packages/PerformanceControl`: 89 tests, 0 failures (1.53 s), including OSCLoopbackIntegrationTests (2 passed, not skipped).

## Phase 4: User Story 2 — the last value always wins (P1)

- [X] OSC-009-T10 [US2] Add to `OSCRateLimiterTests` / `OSCFloodTests`: a fast sweep of 1,000 values to one target at one instant ends, after the flush, at the last value without any further message (US2 scenario 1). — Verified 2026-11-13: OSCFloodTests.testFastSweepEndsAtTheLastValueWithoutAnotherMessage passes: 1,000 values at one instant → 10 applied, 990 held, the flush at 17 ms applies 1.0.

## Phase 5: User Story 3 — see that limiting happened (P2)

- [ ] OSC-009-T11 [US3] Settings row "Rate-limited N" (`LabeledContent`, identifier `oscRateLimited`) under the test value while OSC is on in `Apps/projectM-iOS/Views/SettingsView.swift`; a unit test of `OSCReceiverCoordinator.rateLimitedText` in `OSCReceiverCoordinatorTests`.
- [ ] OSC-009-T12 [US3] Write `Apps/projectM-iOS/UITests/OSCRateLimiterUITests.swift` (< 30 s): OSC on via launch arguments on port 47125, Settings shows `oscRateLimited` with "0".

## Phase 6: Polish

- [ ] OSC-009-T13 Run the app tests on an own iOS 27.2 simulator (`-only-testing:` projectM-iOSTests, OSCReceiverUITests, OSCNetworkAccessUITests, OSCRateLimiterUITests); count PosterBoard reports before and after; delete the simulator.
- [ ] OSC-009-T14 `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`; `grep` confirms no `MainActor` or `DispatchQueue.main` in `Packages/PerformanceControl/Sources/PerformanceControl/OSC*` (OSC-009-R10); update the package header comment in `Packages/PerformanceControl/Package.swift` and the roadmap status if the roadmap lists one.
- [ ] OSC-009-T15 {device} On D1, a LAN controller floods `/projectm/test` at ~2,000 msg/s for 10 s: rendering continues, "Rate-limited N" grows, the value ends at the last one sent (quickstart C). Device LAN check, last stage; not run by this row.

## Dependencies

T01 → T02 → T03 → T04, T05 → T06, T07, T10 → T08 → T11 → T12 → T13 → T14. T15 last, on a device.
T02 and T07 are written in parallel (different files). US2 depends on US1's dispatcher; US3 on the
coordinator change in T08.

## Implementation strategy

MVP = US1 (limits, flood fixture, gated refresh). US2 is covered by the same coalescing code and
adds a focused test; US3 adds the Settings row and its UI test.

## Analyze (2026-11-13)

speckit-analyze findings, all applied: C1 (S4 split between T07's fake-clock gate test and T08's
one-pending app test, so no wall-clock assertion), C2 (R4 checked in T06), C3 (R10 checked in T14).
Coverage: R1-R12 and S1-S5 each have a task; no constitution conflict.
