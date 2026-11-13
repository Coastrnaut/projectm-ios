# OSC-009 OSC rate limiter — test report

Spec: `specs/041-osc-009-osc-rate-limiter/` (tasks OSC-009-T01…T15). Acceptance criterion: "Flood
fixture cannot starve render loop or exceed configured rate." Date: 2026-11-13, Mac Studio, Xcode
27.2, private iOS 27.2 simulator ("OSC9 iPhone 17", deleted afterwards). Simulator and host results
are not device evidence.

## Configured rates (research OSC-009-D6)

| Limit | Rate | Burst |
|---|---|---|
| per source (peer connection) | 200 datagrams/s | 50 |
| all sources | 500 datagrams/s | 100 |
| per target (parameter) | 60 applied updates/s | 10 |
| tables | 16 sources, 64 targets, least recently used evicted | — |
| main-thread refresh | ≤ 1 pending, ≥ 1/30 s apart | — |

## Acceptance mapping

| Part | Test | Result |
|---|---|---|
| Exceed configured rate: never | `OSCFloodTests.testFloodFromThreeSourcesNeverExceedsTheConfiguredRates`: 100,000 datagrams, 3 sources, fake clock 1 ms per 50 datagrams; decoded ≤ 100 + 500/s; busiest 1 ms, 100 ms, 1 s apply windows ≤ 10 + 60/s × window; ≤ 1 flush pending | passed, 0.161 s |
| Final state correct | same test: final value = last value past the datagram limits; a later value is applied. `testFastSweepEndsAtTheLastValueWithoutAnotherMessage` | passed |
| Bounded work per datagram | flood: every non-admitted datagram only checked (not decoded); ignored/malformed take no target slot (`testIgnoredAndMalformedMessagesTakeNoTargetSlot`) | passed |
| Cannot starve the render loop | `OSCRefreshGateTests` (≤ 31 refreshes per simulated second for 10,000 requests); app `OSCReceiverCoordinatorTests.testFloodCoalescesMainActorRefreshes` (no main-actor work during a 10,000-datagram flood, ≤ 3 refreshes after it, final value shown) | passed (5/5 repeats) |
| Limiter rules | `OSCRateLimiterTests` (10): burst and exact refill, clock jump and backwards clock, source isolation, global cap, target limit, coalescing, eviction, reset | passed |
| Visible count | `OSCRateLimiterUITests` ("Rate-limited, 0" in Settings) | passed, 14.9 s |

## Commands

| Check | Command | Result |
|---|---|---|
| Package suite | `swift test --package-path Packages/PerformanceControl` | 89 tests, 0 failures, 1.53 s (73 before) |
| Loopback integration | included above | 2 passed (not skipped) |
| App unit target | `-only-testing:projectM-iOSTests` | 186 tests; first run 2 failures: the new flood test (baseline counted setEnabled's state refreshes; fixed, then passed) and the known worktree failure `PresetTests.testBundledIncludedScopeMatchesRelease1_0` |
| UI tests | OSCReceiverUITests, OSCNetworkAccessUITests, OSCRateLimiterUITests | passed, 15.3 s, 20.3 s, 14.9 s |
| PosterBoard | count of `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` | 32 before, 32 after |
| Compliance, docs | `check_compliance.py`, `validate_docs.py` | OK |

## Not verified (pending)

- OSC-009-T15 `{device}`: a LAN flood on D1 (quickstart C). Owner, last stage.
- Linux: the package was not built on Linux here (CI's Linux job runs it).
- The render loop's frame rate under a real flood is not measured (no device run); the protection is
  shown by counts: no main-thread work per message.
- No red run was recorded before the implementation for the package tests (tests and code written in
  one step).
