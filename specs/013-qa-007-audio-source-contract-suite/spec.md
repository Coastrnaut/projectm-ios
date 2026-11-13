# Feature Specification: QA-007 Audio source contract suite

**Feature Branch**: `feature/qa-007` (spec directory `013-qa-007-audio-source-contract-suite`)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Implement QA-007 (Audio source contract suite) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Exercise start, stop, permission
denial, interruption and switch across fakes." Acceptance, verbatim: "Every source implements same
state transition invariants." Dependencies: AUD-014 (integrated). Honor the repository constitution."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `QA-007-R1…`, success criteria `QA-007-S1…`, tasks `QA-007-T01…`. Requirements of
feature 001 (`specs/001-ios-projectm-visualizer/spec.md`, data model and
`contracts/audio-source.md`), of AUD-001 (`specs/003-…`), AUD-006 (`specs/007-…`), AUD-014
(`specs/009-…`) and AUD-016 (`specs/011-…`) stay in force. This feature writes down the behavior
they already require of every audio source as one contract, checks it for every source, and fixes
what the check finds.

## Clarifications

### Session 2026-11-12

Answered by Claude under the owner's best-judgement rule (CLAUDE.md, owner rule 4); each answer is
the conservative option that changes no user-visible behavior unless the suite finds a defect.

- Q: What is "a source" for this suite? → A: Five source configurations, each through its real
  adapter: System/App Capture (`ScreenCaptureSource` over the stream-driver seam), Microphone
  (`MicrophoneSource` over the microphone-backend seam), and In-App Playback
  (`InAppPlaybackSource` over the playback-backend seam) once per track kind: the bundled reference
  track, an imported file (AUD-001) and a generated test signal (AUD-016). The real `CaptureManager`
  sits on top in every case. Only the lowest platform seam is replaced, by a scripted fake.
- Q: What does "start is idempotent" mean for a source that is already started? → A: It never
  yields two concurrent sessions. At the manager, selecting the active source again is a restart
  (FR-055): exactly one stop of the old session, then one start. At the adapter, a `start` on a
  started source first ends the current session (its backend is stopped and its event stream
  finishes), then starts a new one. Rejecting the second start was rejected: the manager's restart
  path and the protocol's `start` return type expect a fresh session.
- Q: Where a source genuinely behaves differently (System/App Capture is not suspended in the
  background and not governed by interruptions), is the invariant skipped for it? → A: Never. Each
  difference is a documented per-source parameter of the contract with its citation, and the same
  test asserts the source's documented outcome (contracts/source-contract.md, "Per-source
  parameters").
- Q: What is "permission denial" for In-App Playback, which asks for no permission (FR-069)? → A:
  The blocked start that the source does have: a track that cannot be played ends as "Not started —
  In-App Playback failed" (FR-006, AUD-001-R19). The invariant (no session, no samples, a specific
  reason, a later start works) is the same.
- Q: The AUD-014 policy table says Microphone stays paused while an interruption is open (row 5),
  but feature 001 resumes Microphone on every return to the foreground (FR-050) and AUD-014-R9
  requires that behavior to stay. Which does the contract follow? → A: AUD-014-R9 and FR-050: the
  Microphone path was deliberately left outside the policy. The contract states the difference as
  a per-source parameter, and the suite asserts the Microphone outcome; the mismatch with the
  policy table's "rows 4 to 7 describe what CaptureManager already does" is reported as a finding
  for a later feature to decide, not changed here (no device can verify it in this feature).
- Q: Swift Testing or XCTest? → A: XCTest, like every other test in `CaptureKit`: one test class
  whose every test runs its invariant for each source configuration in turn and names the source in
  each failure. It runs unchanged under `swift test` on macOS and Linux and under `xcodebuild` on
  the simulator.
- Q: How does the suite wait for events without depending on thread scheduling? → A: Everything
  runs on the main actor with an injected clock and manual analysis steps. After an event whose
  effect is "no change", the harness sends a marker event through the same stream and waits for its
  log entry; events are handled strictly in order, so the earlier event is then fully handled. Waits
  are on conditions with a generous ceiling, never fixed sleeps.
- Q: How can a fake show that a late sample of the old source is never counted for the new one,
  when every source writes into the manager's one shared sink? → A: By checking the two links the
  app relies on: the adapter stops its backend before `stop()` returns, and the manager awaits that
  stop before the next source's backend starts (a shared order log). The conformance fakes then drop
  the sink at stop, as the platform backends must (contracts/audio-source.md guarantee 4); whether
  each platform backend keeps that promise is tested where it can run (`PlaybackTapGateTests`,
  `InterruptionPipelineTests` for In-App Playback) and otherwise on a device (QA-011, `{device}`).
- Q: Does the suite measure FR-007's 1-second stop budget? → A: No. Wall-clock limits on fakes
  prove nothing and make tests depend on the runner's speed (the `PlaybackTapGateTests` lesson).
  The suite checks that stop completes and reaches the backend; the budget stays a device check.
- Q: Does the suite cover the analysis and normalized output (levels, resampling)? → A: Only as far
  as the audio states need it. Normalization and levels have their own suites
  (`NormalizedOutputTests`, AudioCore); the contract is about source lifecycles and states.

## Baseline: what exists today (audit of 2026-11-12, commit `d4d2a5f`)

This is an extension row ("Extension (existing source tests)"). Existing tests in
`Packages/CaptureKit/Tests/CaptureKitTests/` cover the invariants unevenly: most manager behavior is
tested only with the generic `FakeAudioSource` (not a real adapter), and each adapter is tested for
a few invariants of its own. The full matrix is in [research.md](research.md); in summary:

| Invariant | System/App Capture adapter | Microphone adapter | In-App Playback adapter |
|---|---|---|---|
| start → Waiting through the manager | `ScreenCaptureSourceTests` (one test) | `MicrophoneSourceTests` (via background test) | `InAppPlaybackSourceTests`, `InterruptionRecoveryTests` |
| start on a started source | none | none | none (a comment in `AVInAppPlaybackBackend`) |
| stop idempotent | adapter only | none | adapter only |
| no event after stop | none | none | AV backend only (`InterruptionPipelineTests`) |
| denial → reason, no session | adapter and manager | adapter only | adapter only |
| recovery after denial | none | none | none |
| no samples / silent / active | manager with fake only | none | AV pipeline only |
| transition graph | none | none | none |
| interruption per AUD-014 | manager with fake only | manager with fake only | real adapter (`InterruptionRecoveryTests`) |
| lifecycle (background, lock) | manager with fake only | real adapter (one test) | manager with fake, real adapter (AUD-014) |
| OS end / failure | real adapter (one test) | manager with fake only | AV backend only |
| restart after a terminal state | manager with fake only | none | real adapter (restart of a running session) |
| switch to every other source | manager with fake (one pair) | — | — |
| no callbacks after deallocation | none | none | none |

No test runs one invariant against every source, so "every source implements the same state
transition invariants" is not checked anywhere today.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One contract, checked for every source (Priority: P1)

A developer changing any audio source, or adding one, runs one suite and learns whether the source
still keeps every promise the app relies on: start, stop, a denied or blocked start, an
interruption, the app going to the background, the OS ending the session, and switching to another
source. The promises are written down once, in one contract, with the documented exceptions.

**Why this priority**: It is the roadmap row's acceptance. Without it a source can drift from the
others (and from the truthful status the user sees) without any test noticing.

**Independent Test**: Run the CaptureKit package tests; the contract suite reports, per invariant,
a result for each of the five source configurations.

**Acceptance Scenarios**:

1. **Given** any source configuration, **When** it is started, stopped twice and started again,
   **Then** it shows Waiting, then Stopped with no reason, then Waiting in a fresh session, and its
   backend saw exactly one stop per session.
2. **Given** any source configuration whose start is denied or blocked, **When** the user chooses
   it, **Then** the status is "Not started" with that source's documented reason, no session is
   left running, no samples were counted, and a later allowed start works.
3. **Given** any running source configuration, **When** iOS interrupts audio and ends the
   interruption with or without permission to resume, **Then** the outcome is the one the AUD-014
   policy (or, for System/App Capture, its documented exception) gives for that source.
4. **Given** any two different sources, **When** the user switches from one to the other, **Then**
   the old source is fully stopped before the new one starts, exactly one source runs, the new one
   shows Waiting with nothing carried over, and a late callback from the old one changes nothing.

---

### User Story 2 - The status never claims audio that was not verified (Priority: P1)

The user sees "Active audio" only when non-silent audio of the current session was verified
(Constitution IV), and "No audio received" and "Audio received — silent" are told apart, whatever
the source.

**Why this priority**: Truthful labeling is a non-negotiable constitution rule, and today it is
checked through a real adapter only for In-App Playback.

**Independent Test**: For each source configuration, deliver nothing, silent samples, then
non-silent samples through the source's backend, and read the state after each.

**Acceptance Scenarios**:

1. **Given** a started source that delivers nothing for 5 s, **Then** the state is "No audio
   received".
2. **Given** a started source that delivers only silent samples, **Then** the state is "Audio
   received — silent" and never "Active audio".
3. **Given** a session that was Active, **When** it is restarted, resumed or replaced by another
   source, **Then** the state is Waiting and becomes Active only after new non-silent samples.

---

### User Story 3 - Defects the contract finds are fixed (Priority: P2)

Where a source breaks an invariant, the smallest production change fixes it, a regression test in
the suite keeps it fixed, and the spec records it.

**Why this priority**: The constitution requires start and stop to be idempotent and forbids
callbacks into released objects (VII); a contract that only documents a violation is not enough.

**Independent Test**: The suite's red run before the fix and its green run after it.

**Acceptance Scenarios**:

1. **Given** a source whose adapter breaks an invariant, **When** the fix is applied, **Then** the
   suite passes for that source and for every other source, and every existing test still passes.

### Edge Cases

- A start that is still waiting (system picker, permission prompt) when the user stops or switches:
  covered by existing tests (`ScreenCaptureSourceTests`, `CaptureManagerTests`, ADR-0001 ruling 7);
  the contract cites them and adds the same check for the microphone permission prompt.
- An event that arrives from the OS after the session ended (late delegate callback, late
  notification): delivered nowhere.
- Lifecycle events with no session: no backend call at all.
- Two "began" or two "ended" in a row: covered for In-App Playback by `InterruptionRecoveryTests`;
  the contract requires at most one resume per "ended".
- A source released while its backend still holds a callback: the callback is harmless.

## Requirements *(mandatory)*

### Functional Requirements

Each requirement is one invariant of [contracts/source-contract.md](contracts/source-contract.md)
and holds for every source configuration, with the per-source parameters the contract lists.

- **QA-007-R1** (start): A successful start from no session shows Waiting, runs exactly one backend
  session and labels it with the source's own mode (FR-013, FR-016); In-App Playback plays the
  selected track (AUD-001-R18).
- **QA-007-R2** (repeated start): Starting a source that is already started never yields two
  concurrent sessions: the manager restarts it (one stop, then one start), and the adapter ends its
  current session (backend stopped, event stream finished) before starting a new one
  (Constitution VII).
- **QA-007-R3** (stop): Stop is idempotent, reaches Stopped with no reason, stops the backend before
  it returns, and a second stop or a stop with no session reaches no backend (FR-007).
- **QA-007-R4** (no event after stop): After stop returns, the session's event stream is finished
  and an event from the OS delivers nothing; the manager ignores events from a source that is no
  longer current (contracts/audio-source.md guarantee 4).
- **QA-007-R5** (denied or blocked start): A denied or blocked start ends in Not started with the
  source's documented reason, no backend session, no samples counted, no verified audio and no
  current source; the next allowed start of the same source succeeds (FR-005, FR-015, FR-053).
- **QA-007-R6** (truthful states): No samples for 5 s gives "No audio received", silent samples give
  "Audio received — silent" and never "Active audio", and "Active audio" follows only non-silent
  samples of the current session (Constitution IV, FR-010 to FR-012).
- **QA-007-R7** (clean slate): Every new attempt (restart, switch, start after a terminal state)
  starts in Waiting with no verified audio, zero statistics and no reason (FR-016).
- **QA-007-R8** (transition graph): Every state transition the manager records is an edge of the
  spec 001 transition graph (data-model.md, "Transitions").
- **QA-007-R9** (interruption): An interruption follows `InterruptionPolicy` for the source
  (AUD-014-R1 to R9): Interrupted on "began" while running, exactly one resume when iOS indicates
  it and the policy allows it, none otherwise, and one-tap resume continues; System/App Capture is
  not changed by an interruption (FR-051, policy rule 1).
- **QA-007-R10** (lifecycle): Background and lock pause Microphone and In-App Playback (backend
  paused once), foreground and unlock resume them (one backend resume, Waiting); System/App
  Capture is neither paused nor stopped by the lifecycle (data-model lifecycle matrix, ADR-0001
  ruling 17); lifecycle events with no session reach no backend.
- **QA-007-R11** (OS end or failure): The source's terminal OS event ends the session in its
  documented terminal state with its reason, stops the backend once and leaves no current source
  (US6-AS3, FR-015).
- **QA-007-R12** (restart): After every terminal outcome (Stopped, Ended by system, failed, denied)
  a restart starts the same source again in a new session (FR-055).
- **QA-007-R13** (switch): Switching from any source to any other stops the old backend before the
  new backend starts, leaves exactly one backend session, shows the new mode in Waiting with a clean
  slate, and a late event of the old source changes nothing; the old backend has no sink when the
  new one starts, so no late sample can be counted for the new source (FR-001, FR-016).
- **QA-007-R14** (release): An adapter or a manager that is no longer referenced is released even
  if its backend still holds an event callback, and that callback is harmless afterwards
  (Constitution VII).
- **QA-007-R15** (one suite): One parameterized suite runs R1 to R14 against all five source
  configurations through the real adapters and the real manager, with fakes only at the platform
  seams; no invariant is skipped for any source.
- **QA-007-R16** (defects): A violation found by the suite is fixed in production code with the
  smallest change and recorded in this spec; the invariant is never weakened.

### Key Entities

- **Source contract**: the invariants R1 to R14 and the per-source parameters
  ([contracts/source-contract.md](contracts/source-contract.md)).
- **Conformance harness**: per source configuration, how to allow or deny its start, deliver
  silent or non-silent samples, send an interruption, end the session from the OS and observe its
  backend's sessions.
- **Per-source parameters**: the documented differences (denial reason, interruption and lifecycle
  exemptions of System/App Capture, terminal OS event, Microphone's FR-050 return path).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **QA-007-S1**: Every invariant R1 to R14 passes for all 5 source configurations; 0 invariants
  skipped or disabled for any source.
- **QA-007-S2**: The CaptureKit package tests, including the suite, pass 5 times in a row on the
  macOS host with identical test counts, and pass on the iOS 27.2 simulator.
- **QA-007-S3**: The suite needs no audio hardware and no AVFAudio, so it also runs in CI's Linux
  job; the whole suite completes in under 10 seconds on the Mac host.
- **QA-007-S4**: Every defect the suite found has a test that failed before its fix and passes
  after it, and is listed in this spec.
- **QA-007-S5**: Every existing CaptureKit, CaptureUI and app test still passes (known
  environmental failure excepted: `PresetTests.testBundledIncludedScopeMatchesRelease1_0`).

## Defects found by the suite

Filled in by implementation (QA-007-R16).

## Assumptions

- Physical-device behavior of the real platform backends (AVAudioEngine, ScreenCaptureKit) is out
  of scope here: the suite replaces only the platform seam. Whether the real backends keep the
  seam's promises on a device is a QA-011 (final device matrix) check, tagged `{device}`.
- System/App Capture's real driver exists only on iOS 27 devices; the iOS Simulator SDK has no
  ScreenCaptureKit, but the adapter and the driver protocol compile everywhere, so the System/App
  Capture configuration runs on every platform through its fake driver.
- No user-visible text, stored data, entitlement, dependency or network use is added.
