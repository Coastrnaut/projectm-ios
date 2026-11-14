# Feature Specification: QA-008 Recording Validation Suite

**Feature Branch**: `feature/qa-008` (spec directory `163-qa-008-recording-validation`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement QA-008 (Recording validation suite) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Decode exported fixtures and check
duration, timestamps and audio sync." Acceptance, verbatim: "Bad files fail CI before device testing
begins." P1, effort L, depends on REC-003 (integrated). Consolidate the read-back checks that REC-003,
REC-004 and REC-015 already make into one reusable validator, prove it with generated good and
deliberately bad fixtures, run it in CI's host package tests, and keep the pure timestamp logic
Linux-testable."

Identifiers carry the roadmap ID: requirements `QA-008-R1…`, success criteria `QA-008-S1…`, tasks
`QA-008-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `f51e2ddf`)

| Area | Today | Gap for this row |
|---|---|---|
| Read-back | REC-003 `RecordedVideoInspector` (`Packages/Compositor/Sources/FrameRecording`) reads codec, size, every frame's presentation time (1/600 s ticks, no decoding), duration, track counts, metadata count and (REC-004) the audio format. `timesStrictlyIncrease` is its only rule. | No rule set: each test asserts its own subset. No gap, duration-vs-frames, audio contiguity or privacy check beyond a metadata count. |
| Timestamps | REC-003 `CompositorRecordingTests` (10 s fixture: 300 frames at 20-tick spacing), `MetalFrameRecorderTests` (REC-015 low-storage stop: strictly increasing), all Metal-gated. | Not reusable; skipped where there is no Metal device. |
| A/V sync | REC-004 `RecordingAudioMuxTests`: a flash frame and a 2 ms click at 1.0 s must line up within `RecordingAudioTimeline.toleranceSeconds` (20 ms); the flash and click finders are private to the test. | Not reusable; Metal-gated. |
| Quality | REC-005 (`RecordingQualityFixtureTests`: codec, size, fps ±1, bit rate ±25 %) is being implemented in parallel on `feature/rec-005` and is not on this branch. | Its tests can adopt the validator after both merge; QA-008 does not edit them. |
| Bad files | None: nothing proves a broken file is rejected. | The acceptance needs a corpus of bad files that fail. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where does the validator live? → A: In the existing `FrameRecording` target (`Packages/Compositor`), next to `RecordedVideoInspector`: the rules, expectation, measurement and report are plain Swift (Linux-buildable, `RecordingValidation.swift`); the file reader is AVFoundation-only (`RecordingValidator.swift`, compiled out on Linux). No new target or package: the app's DEBUG probe can use it too, and CI already tests the target on the macOS host, the iOS simulators and Linux.
- Q: Which fixture writer makes the corpus, and does it need a GPU? → A: No GPU. Good fixtures go through the recorder's own `VideoFileWriter` (the same AVAssetWriter settings as the app, `@testable`) fed with CPU-filled pixel buffers and LPCM chunks; bad fixtures that the real writer cannot make (wrong codec, location metadata, a repeated time) use a small test-only AVAssetWriter helper. Every fixture is 160 × 120 (or smaller), at most 2 s, written to the temporary folder and deleted after the test; nothing binary is committed.
- Q: How is a "duplicate time" made and judged, given AVAssetWriter refuses two samples at the same time? → A: Times are judged on the recorder's 1/600 s grid (`RecordingSettings.timescale`; device files are written at that timescale, so nothing is lost): two frames on the same 1/600 s tick are duplicates. The fixture writes at a 90,000 timescale with one frame 1/90,000 s after the previous one, which lands on the same tick.
- Q: How does each bad file fail with exactly one reason when one fault breaks several rules? → A: Root cause first: an unreadable file reports only `unreadable`; the frame-count rule is reported only when the timestamps and the duration passed (a gap or a wrong duration already explains a wrong count); a marker that is not found reports `syncMarkerMissing` instead of `syncOutOfTolerance`; audio format and sync rules are not checked when the audio track is missing; personal metadata reports `personalMetadata`, not also `unexpectedMetadata`.
- Q: How is a device export checked? → A: No new script or executable product (an executable would also have to build on Linux and the iOS scheme). An on-demand test, `RecordingValidationCorpusTests.testExternalRecording`, runs only when `QA008_RECORDING=<path>` is set (optional `QA008_EXPECT_AUDIO=1`, `QA008_FPS=<n>`, `QA008_MARKER_SECONDS=<s>`), prints the report and fails on a bad file: `QA008_RECORDING=~/x.mp4 swift test --package-path Packages/Compositor --filter testExternalRecording`. The device run itself is a final-phase `{device}` task.
- Q: Decode order or presentation order? → A: The recorder never reorders frames (`AVVideoAllowFrameReorderingKey` false), so the times are read in file order and must strictly increase in that order; a file with B-frames is out of scope and fails `notIncreasing`.

## User Scenarios & Testing *(mandatory)*

The "users" are developers and agents who change the recorder, and the owner who checks a device
export in the final QA phase.

### User Story 1 - Bad recordings fail CI before device testing (Priority: P1)

A developer changes the recorder and pushes. CI's host package tests generate small recordings,
including deliberately broken ones, and run the validator on each. A recording with a timestamp gap, a
repeated timestamp, a wrong length, audio out of sync, missing audio, the wrong codec or personal
metadata is rejected with a reason that names the fault.

**Why this priority**: It is the row's acceptance.

**Independent Test**: Run the corpus test alone on the macOS host: every good fixture passes, every bad
fixture fails with exactly its expected reason.

**Acceptance Scenarios**:

1. **Given** a good video-only fixture and a good fixture with owned audio and a flash/click marker,
   **When** they are validated, **Then** both pass with no issue.
2. **Given** each bad fixture (gap, duplicate time, too long, too short, truncated file, wrong frame
   rate, audio 80 ms late, audio missing, unexpected audio, wrong codec, location metadata), **When**
   it is validated, **Then** the report fails and its issue set is exactly the expected reason.

---

### User Story 2 - The recorder's own tests use the same rules (Priority: P1)

The REC-003, REC-004 and REC-015 tests check their recordings with the validator instead of
hand-written subsets, so a rule tightened once applies everywhere.

**Independent Test**: The existing recorder tests still pass and assert at least what they asserted
before.

---

### User Story 3 - The timestamp rules are tested everywhere (Priority: P2)

The timestamp, duration and frame-count rules work on plain number series, so they are tested on Linux
and on every host, without decoding a file.

**Independent Test**: The rule tests in the Linux package job.

---

### User Story 4 - A device export can be checked on the Mac (Priority: P3)

In the final QA phase the owner copies a recording from a device and runs one command on the Mac; it
prints the report and exits non-zero when the file fails.

### Edge Cases

- A file that is not a movie, is empty, or was cut short: one "unreadable" reason, no crash.
- A file with no video track: "unreadable".
- A recording of a single frame: no interval rules apply; duration must still be one frame.
- A recording stopped by a source switch (REC-004 S4): the audio ends before the video; that is not a
  fault (audio may be shorter than the video).
- A recording at another frame rate (24, 60): the expectation names the rate; all intervals scale.
- Audio expected absent but present (a System/App Capture recording with audio): a fault.
- A marker that cannot be found (no flash, or no click): a "marker missing" fault, never a pass.

## Requirements *(mandatory)*

### Functional Requirements

- **QA-008-R1**: A validator MUST take a recording and an expectation and return a structured report: a
  pass/fail verdict, the measured values, and a list of issues, each with a stable reason code and a
  readable detail.
- **QA-008-R2**: The codec MUST be in the expectation's allow-list (by default the two codecs the
  recorder writes).
- **QA-008-R3**: Video presentation times MUST strictly increase (a repeat is a "duplicate" fault, a
  decrease is "not increasing"), no interval may exceed 1.5 × the frame interval ("gap"), and the first
  time MUST be the expected start (0 by default).
- **QA-008-R4**: The duration MUST match the expectation within ±1 frame interval when one is given,
  and MUST equal the last frame time plus one interval within ±1 frame interval in every case.
- **QA-008-R5**: The frame count MUST equal duration × frame rate within ±1.
- **QA-008-R6**: The audio track MUST be present or absent as expected. When present: the expected
  sample rate and channel count, and a sample count that is non-zero and contiguous (no break between
  decoded buffers beyond one sample). Audio may be shorter than the video (a source switch ends it).
- **QA-008-R7**: When the expectation names a sync marker, the first bright frame and the first loud
  audio sample MUST both be found and lie within the tolerance (20 ms, REC-004-R6) of each other; and
  when the expectation names the marker time, the flash MUST be at it within one frame.
- **QA-008-R8**: The file MUST carry no location or other personal metadata, and by default no
  metadata items at all (REC-003-R8).
- **QA-008-R9**: An unreadable file MUST give one "unreadable" issue and no other.
- **QA-008-R10**: The timestamp, duration and frame-count rules (R3-R5) and the verdict MUST be plain
  logic over numbers, built and tested without the media frameworks (Linux).
- **QA-008-R11**: A fixture corpus MUST be generated at test time (never committed as binaries): good
  fixtures and one bad file for every fault in R2-R8 that a real writer can produce (gap, duplicate,
  wrong duration, truncated, wrong frame rate, audio offset, audio missing or unexpected, wrong codec,
  location metadata), each failing with exactly its reason. Faults a writer refuses to produce
  (decreasing times, a wrong first time, a wrong audio format, audio breaks, a missing marker, other
  metadata) MUST be covered by tests on synthetic measurements.
- **QA-008-R12**: The corpus MUST run in the package tests CI already runs on the macOS host, without
  needing a GPU, within the test budget (a few seconds per fixture).
- **QA-008-R13**: The existing REC-003, REC-004 and REC-015 read-back assertions MUST use the validator
  where natural, with no assertion lost.
- **QA-008-R14**: A developer MUST be able to validate one exported file on the Mac with one command
  that prints the report and fails on a bad file.

### Key Entities

- **Recording expectation**: allowed codecs, frame rate, expected start, expected duration (optional),
  audio expected (yes/no), audio format, sync marker (optional, with its time), metadata rule.
- **Recording measurement**: the values read from the file: codec, size, presentation times, duration,
  audio format and sample count, audio buffer breaks, marker times, metadata identifiers.
- **Validation report**: verdict, measurement, issues (reason code + detail).

## Success Criteria *(mandatory)*

- **QA-008-S1**: Every good fixture passes and each of the bad fixtures fails with exactly its expected
  reason code (one corpus test run on the macOS host).
- **QA-008-S2**: The corpus runs in CI's existing macOS host package step on every push, so a bad file
  fails CI before the final device phase; the whole corpus takes under 30 s.
- **QA-008-S3**: The timestamp rules are covered by synthetic series tests that pass on Linux.
- **QA-008-S4**: The REC-003/004/015 tests pass using the validator with no assertion removed.
- **QA-008-S5**: A device export can be checked with one documented command.

## Assumptions

- The recorder's own files are the reference: 1/600 s timescale, no frame reordering, H.264 or HEVC in
  MP4, AAC 44.1 kHz stereo audio (REC-003, REC-004).
- A file's "start" is the first frame at time 0 (the writer starts its session at 0).
- REC-005's quality checks (bit rate) stay in REC-005's tests until both features are integrated.
- Device runs of the export check are a final-phase `{device}` task.
