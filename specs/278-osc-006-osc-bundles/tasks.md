# Tasks: OSC-006 OSC Bundles

**Input**: `specs/278-osc-006-osc-bundles/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the roadmap row (pure tests with injected clocks, a loopback integration test, an app
test, device LAN last). No wall-clock assertions; unit tests about 1-2 s, package suite < 1 min (owner rule 7).
Tasks are ticked only when verified, with " — Verified 2026-11-14: <how>".

## Phase 1: Setup

- [ ] OSC-006-T01 Audit OSC-001/002/003/004/007/008/009, the encoder and the clocks; record the baseline table in `specs/278-osc-006-osc-bundles/spec.md`.

## Phase 2: Foundational (package)

- [ ] OSC-006-T02 `OSCBundleTiming`, `OSCWallClock`, `OSCTimeMapping`, `OSCScheduledMessage`, `OSCBundleSchedule` (min-heap on due, sequence) in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCBundleSchedule.swift` (R2, R4, R5, R8, R12; D1-D3, D9).
- [ ] OSC-006-T03 Scheduling in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCDispatcher.swift`: due-first flush on every datagram, classification (immediate, on time, late, too late, beyond horizon, overflow), apply-now ordering, wake-ups on `OSCFlushScheduler`, `flushScheduled`, `clearScheduled`, `pendingScheduledCount`, new counters and outcomes (R1-R9, R11, R12; contract B1).
- [ ] OSC-006-T04 `OSCReceiver` in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCReceiver.swift`: inject `wallClock`, clear the schedule on stop and on every launch (R10).

## Phase 3: User Story 1 - Cues land on the beat I scheduled (P2)

**Independent test**: dispatcher with fake clocks and a manual scheduler.

- [ ] OSC-006-T05 [US1] Acceptance tests in `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCBundleScheduleTests.swift`: two bundles in reverse order (t+20 ms, t+10 ms) apply in timestamp order at their ticks; equal tags keep arrival order; immediate applies at once; nested ordering (S1, S2).
- [ ] OSC-006-T06 [US1] Loopback integration in `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCLoopbackIntegrationTests.swift`: a bundle 200 ms ahead over real UDP is pending at receipt and applies no earlier than its due time, within 1 s after it (S4).
- [ ] OSC-006-T07 [US1] App test in `Apps/projectM-iOS/Tests/OSCReceiverCoordinatorTests.swift`: through the coordinator, a scheduled bundle changes the parameter only when the clock reaches its time.

## Phase 4: User Story 2 - Late and bogus timing is handled safely (P2)

- [ ] OSC-006-T08 [US2] Tests in `OSCBundleScheduleTests.swift`: late within tolerance, late applied and counted, too late dropped and counted, beyond horizon dropped, capacity overflow drops the newest, stop and switch off clear the queue, scheduled messages still pass routes and the per-target limiter (S3, S5).
- [ ] OSC-006-T09 [US2] Update `OSCDispatcherTests.testBundleMessagesAreAppliedImmediatelyInPacketOrder` (OSC-002) to the "immediately" tag: a 2036 tag is now beyond the horizon.

## Phase 5: Polish

- [ ] OSC-006-T10 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), the whole PerformanceControl and ImportFuzz OSC suites, Linux-safe build (no stdio globals), type-check budget.
- [ ] OSC-006-T11 {device} D1 with a LAN sender whose clock is network-synced: a bundle 500 ms ahead changes the test value about half a second later; one 30 s ahead never applies (quickstart step 3).

## Analysis (speckit-analyze, 2026-11-14)

Every requirement maps to a task: R1, R3-R5 → T05; R2, R12 → T02, T03; R6-R9, R11 → T08; R10 → T04, T08; S4 → T06.
Fixed: the contract's late test was written `due ≤ now + 0` (now `due ≤ now`); R9 names the per-target limiter, so
T08 also checks a scheduled message is coalesced like an immediate one. No constitution conflict.

## Dependencies

T02 → T03 → T04 → T05-T09 → T10. T11 needs a device and a person.
