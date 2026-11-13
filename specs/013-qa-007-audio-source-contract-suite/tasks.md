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

- [X] QA-007-T01 Confirm the baseline: `swift test --package-path Packages/CaptureKit` passes on the host before any change and record the test count (log in `.build/scratch/`). — Verified 2026-11-12: `swift test --package-path Packages/CaptureKit` before any change, 287 tests, 0 failures (`.build/scratch/t01-baseline.log`)

## Phase 2: Foundational (blocks every story)

- [X] QA-007-T02 [P] Write the conformance fakes in `Packages/CaptureKit/Tests/CaptureKitTests/ContractFakes.swift`: an `OrderLog`; `ConformanceStreamDriver` (`StreamDriver`), `ConformanceMicrophoneBackend` (`MicrophoneBackend`, with a holdable permission prompt) and `ConformancePlaybackBackend` (`InAppPlaybackBackend`), each conforming to a `ConformanceBackend` protocol with the members of data-model.md ("liveSessions … must never exceed 1", `deliver`, `send`, `sendLate`, `denyNextStart`, `hasSink`, call counters). The fakes keep the sink only while a session is live. — Verified 2026-11-12: `ContractFakes.swift` compiles under Swift 6 strict concurrency with no warnings and is used by all 18 contract tests (the fakes count sessions as `liveStops`/`idleStops` rather than one `stopCalls`, data-model.md updated)
- [X] QA-007-T03 Write `SourceConfiguration` (5 cases), `SourceParameters` (P1 to P6 with citations in comments) and `ContractRig` (real `CaptureManager` over the three real adapters, `ManualClock`, `play`, `settle(marker:)`, `waitUntil`, `assertTransitionsAllowed` with the graph of contracts/source-contract.md) in `Packages/CaptureKit/Tests/CaptureKitTests/SourceConformance.swift`. Depends on T02. — Verified 2026-11-12: `SourceConformance.swift` (parameters P1-P7; P8 asserted by its own test; waits are `waitFor` and `settle(_:)`), exercised by every contract test

## Phase 3: User Story 1 — One contract, checked for every source (P1) 🎯 MVP

**Goal**: R1 to R5 and R8 to R14 run for all 5 configurations through the real adapters.
**Independent test**: `swift test --package-path Packages/CaptureKit --filter AudioSourceContractTests`.

- [X] QA-007-T04 [US1] In `Packages/CaptureKit/Tests/CaptureKitTests/AudioSourceContractTests.swift`, write `testR1StartShowsWaitingWithOneSessionAndItsOwnLabel` and `testR2RepeatedStartNeverYieldsTwoSessions` (manager restart: one stop then one start; adapter `start` twice: `maxLiveSessions` 1, first stream finished, backend stopped before the second start). — Verified 2026-11-12: written; R1 passed in the red run for all 5 configurations; R2 failed (QA-007-D1) and passes after the fix
- [X] QA-007-T05 [US1] Same file: `testR3StopIsIdempotentAndReachesTheBackendBeforeReturning` (stop twice, stop with no session, adapter-level stop twice) and `testR3StopDuringAPendingMicrophonePermissionPromptEndsAsCancelled`. — Verified 2026-11-12: both tests pass for all 5 configurations (and the Microphone prompt case)
- [X] QA-007-T06 [US1] Same file: `testR4NoEventIsDeliveredAfterStop` (adapter: late `sendLate` after stop, the stream ends with no event; manager: state unchanged). — Verified 2026-11-12: passes for all 5 configurations
- [X] QA-007-T07 [US1] Same file: `testR5DeniedStartLeavesNoSessionAndALaterStartWorks` (per P1; also System/App Capture's cancelled picker). — Verified 2026-11-12: passes for all 5 configurations plus the cancelled picker
- [X] QA-007-T08 [US1] Same file: `testR9InterruptionFollowsThePolicyForEachSource` (began; ended with and without resume; one-tap resume; a duplicate "ended" resumes at most once; expected outcome computed with `InterruptionPolicy.decide` for P2) and `testR9ReturnDuringAnOpenInterruption` (P5). — Verified 2026-11-12: both tests pass for all 5 configurations
- [X] QA-007-T09 [US1] Same file: `testR10LifecyclePausesAndResumesPerSource` (background/foreground, lock/unlock, P3), `testR10LifecycleWithoutASessionReachesNoBackend`, `testR10ResumeRechecksPermission` (P6). — Verified 2026-11-12: the three tests pass for all 5 configurations
- [X] QA-007-T10 [US1] Same file: `testR11TerminalOSEventEndsTheSessionWithItsReason` (P4) and `testR12RestartAfterEveryTerminalOutcome` (stopped, ended by system / failed, denied). — Verified 2026-11-12: both tests pass for all 5 configurations (R12 after user stop, terminal OS event and denial)
- [X] QA-007-T11 [US1] Same file: `testR13SwitchFromEverySourceToEveryOther` (6 ordered pairs: order log stop-before-start, one live session, old backend has no sink, old late event changes nothing). — Verified 2026-11-12: passes, 14 ordered pairs asserted
- [X] QA-007-T12 [US1] Same file: `testR14AdaptersAndManagerAreReleasedAndLateCallbacksAreHarmless`. — Verified 2026-11-12: passes for all 5 configurations, with and without stop before release
- [X] QA-007-T13 [US1] Every test above calls `assertTransitionsAllowed()` before each new attempt and at its end (R8); add `testR8TransitionGraphMatchesSpec001` that checks the graph table itself against the classifier's documented rules (no edge outside data-model.md). — Verified 2026-11-12: every test calls `assertTransitionsAllowed`; `testR8TransitionGraphMatchesSpec001` passes
- [X] QA-007-T14 [US1] Red run: run the suite before any production change; record each failing test and its message in the spec's "Defects found by the suite" (expected at least R2 for adapters without a start guard; research D4). — Verified 2026-11-12: red run 18 tests, 1 failing (R2, 20 assertion failures), recorded in spec.md "Defects found by the suite" (`.build/scratch/t14-red.log`)

## Phase 4: User Story 2 — The status never claims audio that was not verified (P1)

**Goal**: R6 and R7 for every configuration.
**Independent test**: `--filter AudioSourceContractTests/testR6` and `testR7`.

- [X] QA-007-T15 [P] [US2] Same file: `testR6NoSamplesSilentAndActiveAreToldApart` (5 s without samples → No audio received; silent samples → silent, never Active; ≥ 250 ms non-silent → Active). — Verified 2026-11-12: passes for all 5 configurations
- [X] QA-007-T16 [US2] Same file: `testR6ActiveNeedsNewAudioAfterEveryResume` (after lifecycle and interruption resumes: Waiting until new non-silent samples) and `testR7EveryNewAttemptStartsFromACleanSlate` (restart, switch, start after a terminal state). — Verified 2026-11-12: R7 passes for all 5 configurations; the after-resume checks live in the R9 and R10 tests ("R6 after a resume Active needs new audio")

## Phase 5: User Story 3 — Defects the contract finds are fixed (P2)

- [X] QA-007-T17 [US3] Fix each defect from T14 with the smallest change in `Packages/CaptureKit/Sources/CaptureKit/` (expected: `MicrophoneSource.swift`, `ScreenCaptureSource.swift`, `InAppPlaybackSource.swift` end a running session before a new `start`); never change an invariant to make it pass. — Verified 2026-11-12: guard added to the three adapters' `start`; contract suite 18/18 green; a mutation check (2 temporary edits, reverted) made the suite fail with 66 assertion failures
- [X] QA-007-T18 [US3] Green run: the whole CaptureKit package passes on the host; record the count. Update the spec's "Defects found by the suite" with cause, fix and regression test. — Verified 2026-11-12: CaptureKit on the host 305 tests, 0 failures (`.build/scratch/t18-full.log`); spec updated
- [X] QA-007-T19 [US3] If production code changed: CaptureUI package tests on the host, and the app's unit tests plus `InterruptionUITests`, `TransportUITests`, `StatusUITests` on the iOS 27.2 simulator (`xcodegen generate`; known environmental failure `PresetTests.testBundledIncludedScopeMatchesRelease1_0`). — Verified 2026-11-12: production code changed, so: CaptureUI on the host 39 tests, 0 failures; `xcodegen generate` and `xcodebuild build-for-testing` of `projectM-iOS` for iPhone Air iOS 27.2 succeeded; app unit tests 111, 1 failure = the known environmental `PresetTests.testBundledIncludedScopeMatchesRelease1_0` (this worktree has no preset submodules: 28 presets indexed); `InterruptionUITests` 3, `StatusUITests` 7, `TransportUITests` 3, 0 failures (`.build/scratch/app-test.log`)

## Phase 6: Polish & cross-cutting

- [X] QA-007-T20 [P] Run CaptureKit's tests on the iOS 27.2 simulator (`77E17861-E687-4274-8A84-14224F32BE3E`) with `-test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO`; record which configurations ran (all 5: the driver seam compiles without ScreenCaptureKit); confirm the package scheme name used in quickstart.md. — Verified 2026-11-12: `xcodebuild test -scheme CaptureKit` on iPhone Air iOS 27.2 (77E17861-…): 309 tests, 0 failures, ** TEST SUCCEEDED **; all 18 contract tests passed, all 5 configurations (no compile guard; System/App Capture through its driver seam); scheme name `CaptureKit` confirmed
- [X] QA-007-T21 Run the CaptureKit host suite 5 times in a row; record each run's executed and failed counts and the suite's duration (QA-007-S2, S3). — Verified 2026-11-12: 5 consecutive host runs of CaptureKit, each 305 tests, 0 failures (31.4-31.8 s); the contract suite took 0.23-0.36 s per run (QA-007-S3: under 10 s); also passes with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO` (18 tests, 0 failures)
- [X] QA-007-T22 [P] `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/test_scripts.py` pass. — Verified 2026-11-12: `check_compliance.py` OK, `validate_docs.py` OK, `test_scripts.py` 98 tests OK (1 skipped, pre-existing)
- [ ] QA-007-T23 {device} (open: awaits the final device stage; not run in this feature) The real platform backends keep the seam's promises (no sink write after stop, interruption and end events mapped as the fakes model them) on D1-D3: part of the final device matrix (QA-011); not run in this feature.

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
