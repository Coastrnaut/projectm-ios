# Tasks: QA-007 Audio source contract suite

**Input**: Design documents from `specs/013-qa-007-audio-source-contract-suite/` (spec, plan,
research, data-model, contracts/source-contract.md, quickstart)

**Tests**: This feature *is* a test suite; every task is test-first. The suite is written before any
production change, its red run is recorded, then defects are fixed.

**Format**: `- [ ] QA-007-Tnn [P?] [Story] Description` — IDs carry the roadmap ID (ADR-0008).
`{device}` marks a check that needs a physical device and is not run before the final device
stage (QA-011). A task is ticked `[X]` only when verified, with " — Verified <date>: <how>".

Paths are relative to the repository root; tests live in
`Packages/CaptureKit/Tests/CaptureKitTests/`.

## Phase 1: Setup

- [ ] QA-007-T01 Confirm the baseline: `swift test --package-path Packages/CaptureKit` passes on the host before any change and record the test count (log in `.build/scratch/`).

## Phase 2: Foundational (blocks every story)

- [ ] QA-007-T02 [P] Write the conformance fakes in `Packages/CaptureKit/Tests/CaptureKitTests/ContractFakes.swift`: an `OrderLog`; `ConformanceStreamDriver` (`StreamDriver`), `ConformanceMicrophoneBackend` (`MicrophoneBackend`, with a holdable permission prompt) and `ConformancePlaybackBackend` (`InAppPlaybackBackend`), each conforming to a `ConformanceBackend` protocol with the members of data-model.md ("liveSessions … must never exceed 1", `deliver`, `send`, `sendLate`, `denyNextStart`, `hasSink`, call counters). The fakes keep the sink only while a session is live.
- [ ] QA-007-T03 Write `SourceConfiguration` (5 cases), `SourceParameters` (P1 to P6 with citations in comments) and `ContractRig` (real `CaptureManager` over the three real adapters, `ManualClock`, `play`, `settle(marker:)`, `waitUntil`, `assertTransitionsAllowed` with the graph of contracts/source-contract.md) in `Packages/CaptureKit/Tests/CaptureKitTests/SourceConformance.swift`. Depends on T02.

## Phase 3: User Story 1 — One contract, checked for every source (P1) 🎯 MVP

**Goal**: R1 to R5 and R8 to R14 run for all 5 configurations through the real adapters.
**Independent test**: `swift test --package-path Packages/CaptureKit --filter AudioSourceContractTests`.

- [ ] QA-007-T04 [US1] In `Packages/CaptureKit/Tests/CaptureKitTests/AudioSourceContractTests.swift`, write `testR1StartShowsWaitingWithOneSessionAndItsOwnLabel` and `testR2RepeatedStartNeverYieldsTwoSessions` (manager restart: one stop then one start; adapter `start` twice: `maxLiveSessions` 1, first stream finished, backend stopped before the second start).
- [ ] QA-007-T05 [US1] Same file: `testR3StopIsIdempotentAndReachesTheBackendBeforeReturning` (stop twice, stop with no session, adapter-level stop twice) and `testR3StopDuringAPendingMicrophonePermissionPromptEndsAsCancelled`.
- [ ] QA-007-T06 [US1] Same file: `testR4NoEventIsDeliveredAfterStop` (adapter: late `sendLate` after stop, the stream ends with no event; manager: state unchanged).
- [ ] QA-007-T07 [US1] Same file: `testR5DeniedStartLeavesNoSessionAndALaterStartWorks` (per P1; also System/App Capture's cancelled picker).
- [ ] QA-007-T08 [US1] Same file: `testR9InterruptionFollowsThePolicyForEachSource` (began; ended with and without resume; one-tap resume; a duplicate "ended" resumes at most once; expected outcome computed with `InterruptionPolicy.decide` for P2) and `testR9ReturnDuringAnOpenInterruption` (P5).
- [ ] QA-007-T09 [US1] Same file: `testR10LifecyclePausesAndResumesPerSource` (background/foreground, lock/unlock, P3), `testR10LifecycleWithoutASessionReachesNoBackend`, `testR10ResumeRechecksPermission` (P6).
- [ ] QA-007-T10 [US1] Same file: `testR11TerminalOSEventEndsTheSessionWithItsReason` (P4) and `testR12RestartAfterEveryTerminalOutcome` (stopped, ended by system / failed, denied).
- [ ] QA-007-T11 [US1] Same file: `testR13SwitchFromEverySourceToEveryOther` (6 ordered pairs: order log stop-before-start, one live session, old backend has no sink, old late event changes nothing).
- [ ] QA-007-T12 [US1] Same file: `testR14AdaptersAndManagerAreReleasedAndLateCallbacksAreHarmless`.
- [ ] QA-007-T13 [US1] Every test above calls `assertTransitionsAllowed()` before each new attempt and at its end (R8); add `testR8TransitionGraphMatchesSpec001` that checks the graph table itself against the classifier's documented rules (no edge outside data-model.md).
- [ ] QA-007-T14 [US1] Red run: run the suite before any production change; record each failing test and its message in the spec's "Defects found by the suite" (expected at least R2 for adapters without a start guard; research D4).

## Phase 4: User Story 2 — The status never claims audio that was not verified (P1)

**Goal**: R6 and R7 for every configuration.
**Independent test**: `--filter AudioSourceContractTests/testR6` and `testR7`.

- [ ] QA-007-T15 [P] [US2] Same file: `testR6NoSamplesSilentAndActiveAreToldApart` (5 s without samples → No audio received; silent samples → silent, never Active; ≥ 250 ms non-silent → Active).
- [ ] QA-007-T16 [US2] Same file: `testR6ActiveNeedsNewAudioAfterEveryResume` (after lifecycle and interruption resumes: Waiting until new non-silent samples) and `testR7EveryNewAttemptStartsFromACleanSlate` (restart, switch, start after a terminal state).

## Phase 5: User Story 3 — Defects the contract finds are fixed (P2)

- [ ] QA-007-T17 [US3] Fix each defect from T14 with the smallest change in `Packages/CaptureKit/Sources/CaptureKit/` (expected: `MicrophoneSource.swift`, `ScreenCaptureSource.swift`, `InAppPlaybackSource.swift` end a running session before a new `start`); never change an invariant to make it pass.
- [ ] QA-007-T18 [US3] Green run: the whole CaptureKit package passes on the host; record the count. Update the spec's "Defects found by the suite" with cause, fix and regression test.
- [ ] QA-007-T19 [US3] If production code changed: CaptureUI package tests on the host, and the app's unit tests plus `InterruptionUITests`, `TransportUITests`, `StatusUITests` on the iOS 27.2 simulator (`xcodegen generate`; known environmental failure `PresetTests.testBundledIncludedScopeMatchesRelease1_0`).

## Phase 6: Polish & cross-cutting

- [ ] QA-007-T20 [P] Run CaptureKit's tests on the iOS 27.2 simulator (`77E17861-E687-4274-8A84-14224F32BE3E`) with `-test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO`; record which configurations ran (all 5: the driver seam compiles without ScreenCaptureKit); confirm the package scheme name used in quickstart.md.
- [ ] QA-007-T21 Run the CaptureKit host suite 5 times in a row; record each run's executed and failed counts and the suite's duration (QA-007-S2, S3).
- [ ] QA-007-T22 [P] `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/test_scripts.py` pass.
- [ ] QA-007-T23 {device} The real platform backends keep the seam's promises (no sink write after stop, interruption and end events mapped as the fakes model them) on D1-D3: part of the final device matrix (QA-011); not run in this feature.

## Dependencies

- T01 → T02 → T03 → T04 … T13 and T15, T16 (one file, sequential) → T14 (red run) → T17 → T18 → T19 → T20, T21, T22.
- US2's tests (T15, T16) need only T03; they are written before the red run is recorded so the red run covers them too.
- T23 waits for the final device stage.

## Parallel opportunities

- T02 can be written alongside the spec work; T15 is independent of T04-T13 apart from the shared file (one writer, so in practice sequential).
- T20 and T22 run in parallel with T21.

## Implementation strategy

MVP = Phases 1-3 (the contract runs for every source and finds what it finds). Then US2, then the
fixes and the full verification.
