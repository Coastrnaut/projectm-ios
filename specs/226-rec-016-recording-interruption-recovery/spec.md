# Feature Specification: REC-016 Recording interruption recovery

**Feature Branch**: `feature/rec-016` (spec directory `226-rec-016-recording-interruption-recovery`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement REC-016 (Recording interruption recovery) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Handle app interruption, thermal warning and writer failure gracefully." P1, effort L,
depends on REC-003 (integrated). Acceptance, verbatim: "Injected writer failure releases resources and preserves usable
segments when possible.""

Identifiers carry the roadmap ID: requirements `REC-016-R1…`, success criteria `REC-016-S1…`, tasks
`REC-016-T01…`, research decisions `REC-016-D1…`.

## Baseline: what exists today (audit of 2026-11-14, commit `0ec67c56`)

| Area | Today |
|---|---|
| Writer | `VideoFileWriter` (REC-003): one `AVAssetWriter` writing a plain MP4. The movie header is written only when the file is finished, so a writer that fails mid-recording leaves no readable file. |
| Writer failure | The recorder marks itself failed on a failed append; the tap reports `.writerFailed`; `finish` deletes the file (REC-003-R17, "no partial file is kept") and the notice is "The recording couldn't be finished." An out-of-space error becomes `storageFull` (REC-015-R7). |
| Failure injection | `RecordingWriterFault` (REC-015-R12): after N frames every append fails with a given error; finishing cancels the real writer (file deleted). Only the "append fails" kind exists. |
| Start failure | If the writer starts but the recorder's texture cache cannot be made, the started writer is dropped without being cancelled; its file stays in `<tmp>/Recordings` until the next launch (REC-003-R13 cleanup). |
| Background | `didEnterBackground` stops with `.background` inside a background-task grant; the file is finished and offered in the "Recording ready" panel (REC-012) with "Recording stopped when the app left the screen." |
| Thermal | Visual hosts and PERF-008's `QualityGovernor` lower render quality on `ProcessInfo.thermalState`; recording ignores the thermal state (it starts and runs at Critical). |
| Resources | The recorder owns a texture cache, a pixel-buffer pool (in the writer) and the writer; they are released when the coordinator drops the recorder. Nothing counts them. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: How are usable segments preserved when the writer fails? → A: The writer writes a fragmented MP4 (a movie fragment every second), so the frames of every completed fragment stay readable even when the writer fails and never finishes. A normal finish still produces an ordinary (defragmented) MP4, so playback, sharing, Photos and the QA-008 validator see the same kind of file as before. Segment rotation (several files) was rejected: it gives the user several files per recording and needs a join step.
- Q: Which writer failures keep a partial file? → A: Every writer failure except running out of storage. A failed append while the writer is still healthy finishes the file normally at the last good frame; a writer that itself failed keeps its completed fragments. Out of storage keeps REC-015-R7: the partial file is deleted (a full disk is where a kept file hurts most, and finishing needs space).
- Q: When is a partial file "usable"? → A: When AVFoundation reads it back with a video track of at least two frames (REC-003's minimum). Otherwise the file is deleted and the failure notice is shown as before.
- Q: What does the user see after a failure that kept a file? → A: The recording stops, the "Recording ready" panel offers the kept part (Keep, Save…, Share…, Discard as for any recording), and the notice "Recording stopped because of a write error. The part recorded before it was kept." is shown and announced (row X13).
- Q: What happens on a thermal warning? → A: At Serious the recording goes on and the notice "The device is getting hot. Recording stops if it gets hotter." is shown once per recording; at Critical the recording stops normally (the file is finished and offered) with "Recording stopped because the device is too hot." Record is refused at Critical with "The device is too hot to record. Try again when it cools down." Reducing the recording's quality mid-file was rejected (the writer's size and rate are fixed per file).
- Q: What counts as an app interruption? → A: The app leaving the screen (background), which already stops and finishes the file; this feature proves the file is finished and offered on return. Audio-session interruptions (calls) do not stop the video; REC-004 already ends the audio when the source stops.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Which fragment interval? → A: 1 s. At most about one second (plus the encoder's lag) is lost on a writer failure; the cost is one small fragment header per second while recording and a header rewrite at finish. 0.5 s doubles the headers for little gain; 2 s (the key-frame interval) loses up to two seconds.
- Q: Does a kept partial recording report its real length? → A: Yes. The recorder reads the kept file back and reports the frames and duration the file actually holds (not what was appended), so "Recording ready" and REC-006's facts are honest.
- Q: How are "resources released" proven? → A: A process-wide ledger of live recorders and writers (each writer owns its pixel-buffer pool), counted on creation and release, plus the recorder's frames-in-flight count; tests compare against the count before the recording. The ledger is diagnostics only (memory, never stored).
- Q: Which thermal source does the coordinator read? → A: `ProcessInfo.thermalState`, injected in tests; DEBUG's existing `-uitestThermalState` argument also drives it. It is read at Record and by the 0.25 s check.
- Q: Is the injection seam reachable in Release? → A: No user-visible path. The fault type lives in the package (tests use it); the app accepts `-uitestWriterFault` only in DEBUG builds.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A writer failure keeps what was recorded (Priority: P1)

The user records; the file writer fails part-way (a system encoder error, a failed append). The
recording stops, the app keeps running, every recording resource is released, and the part recorded
before the failure is offered in "Recording ready".

**Why this priority**: It is the roadmap acceptance: an injected writer failure releases resources and
preserves usable segments when possible.

**Independent Test**: A short fixture (about 2 s of 64×48 frames) with an injected failure of each
kind: append failure, writer failure, finish failure. The test asserts the recorder's resources are
released (live writer and recorder counts back to the baseline, no frame in flight), and reads the kept
file back: a readable video whose frame count and duration are within one fragment of what was
appended before the failure.

**Acceptance Scenarios**:

1. **Given** a recording with an injected append failure after 45 frames, **When** the failure happens, **Then** the recording stops, the coordinator is idle, the notice is "Recording stopped because of a write error. The part recorded before it was kept.", and the offered file reads back with 45 frames.
2. **Given** a recording whose writer itself fails after about 1.5 s, **When** it fails, **Then** the kept file reads back with at least the frames of every completed fragment (at most one fragment interval plus the encoder's lag short of what was appended) and strictly increasing times.
3. **Given** a writer failure before two frames reached a completed fragment, **When** it fails, **Then** no file is kept and the notice is "The recording couldn't be finished."
4. **Given** any writer failure, **When** the recording has ended, **Then** no recorder, writer or pixel buffer of it is alive and Record works again.

---

### User Story 2 - A failed start leaves nothing behind (Priority: P1)

Record fails to start (no encoder, no pixel buffers, an injected start failure). Nothing is left on
disk and the app says why.

**Independent Test**: An injected start failure after the writer was created: the recording folder is
empty, the state is idle, the notice is shown.

**Acceptance Scenarios**:

1. **Given** an injected start failure, **When** the user taps Record, **Then** the state stays idle, "The recording couldn't be finished." is shown, and the recording folder holds no file.

---

### User Story 3 - Leaving the app finishes the file (Priority: P1)

The user leaves the app while recording. The file is finished while the system still runs the app,
and on return the "Recording ready" panel offers it with "Recording stopped when the app left the screen."

**Independent Test**: An app test sends the background event during a fake-source recording and checks
the offered file reads back and the notice.

**Acceptance Scenarios**:

1. **Given** a recording, **When** the app goes to the background, **Then** the recording stops, the file is finished, and it is offered (not deleted) with the background notice.

---

### User Story 4 - The device gets hot (Priority: P2)

**Acceptance Scenarios**:

1. **Given** a recording at Fair, **When** the thermal state becomes Serious, **Then** the recording goes on and the hot-device warning is shown once.
2. **Given** a recording, **When** the thermal state becomes Critical, **Then** the recording stops, the file is finished and offered, and "Recording stopped because the device is too hot." is shown.
3. **Given** the thermal state is Critical, **When** the user taps Record, **Then** nothing starts and the too-hot refusal is shown.

### Edge Cases

- A failure while frames are still in flight: those frames are dropped; the kept file ends at the last frame the writer accepted (or its last completed fragment).
- A failure during finishing (finish failure): the completed fragments are kept when usable.
- An out-of-storage failure: REC-015 unchanged (file deleted, "Storage is full; the recording couldn't be saved.").
- A failure while a countdown runs: impossible (no writer exists during a countdown, REC-007).
- Thermal Serious then Critical in one recording: one warning, then the stop.
- The app is terminated by the system before finishing completes: the completed fragments are on disk, but REC-003-R13 deletes leftovers at the next launch (unchanged; recovering files across launches is out of scope).

## Requirements *(mandatory)*

### Functional Requirements

- **REC-016-R1**: The writer MUST write movie fragments at a fixed interval (1 s) so that, after any writer failure, the frames of every completed fragment remain readable; a normally finished file MUST remain an ordinary MP4 that passes the QA-008 validation.
- **REC-016-R2**: The recorder MUST offer a failure-injection seam with three kinds — append failure, writer failure and finish failure — plus a start failure, used only by tests and DEBUG launch arguments.
- **REC-016-R3**: On a writer failure other than out-of-storage, the recorder MUST keep the file when it reads back with a video track of at least two frames (finishing it at the last appended frame when the writer is still healthy), and MUST delete it otherwise.
- **REC-016-R4**: After any stop or failure, the recorder MUST release its resources: no frame in flight, the texture cache flushed, and the writer, its pixel-buffer pool and the recorder freed once the app drops them; the coordinator MUST be idle with no tap attached, no audio tap armed and no timer running.
- **REC-016-R5**: A kept partial recording MUST be offered like any finished recording, with the notice "Recording stopped because of a write error. The part recorded before it was kept." (X13).
- **REC-016-R6**: A start failure MUST leave no file in the recording folder (a started writer is cancelled and its file deleted).
- **REC-016-R7**: The app going to the background while recording MUST finish the file and offer it (REC-003-R11, REC-012), never delete it.
- **REC-016-R8**: At thermal Serious the recording MUST continue and show the hot-device warning once per recording; at Critical it MUST stop with the new stop reason `thermal`; Record MUST be refused at Critical with the new refusal `thermal`.
- **REC-016-R9**: Out-of-storage failures MUST keep REC-015-R7's behaviour.

### Key Entities

- **Writer fault**: the kind (append, writer, finish, start), after how many frames, and the error reported.
- **Salvage outcome**: finished (healthy writer finished early), partial (completed fragments kept), nothing (deleted).
- **Thermal guard**: the per-recording state that warns once at Serious and stops at Critical.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **REC-016-S1**: Injected append, writer and finish failures in a 2 s fixture: in every case the recorder's live writer and recorder counts return to their baseline and no frame is in flight; the kept file reads back with strictly increasing times and a frame count within one fragment interval (plus 0.5 s of encoder lag) of the frames appended before the failure.
- **REC-016-S2**: An injected start failure leaves zero files in the recording folder.
- **REC-016-S3**: A background stop offers a finished file that reads back with the recorded frames.
- **REC-016-S4**: Thermal Serious warns once and keeps recording; Critical stops with the thermal notice and the file is offered; Record at Critical is refused.
- **REC-016-S5**: A normally finished recording is still an ordinary MP4 (no movie fragments) that passes QA-008's validation.

## Assumptions

- Recovering a recording across an app termination is out of scope (REC-003-R13 cleanup is kept).
- The 1 s fragment interval's cost is a small header per second while recording and a header rewrite at finish; it is measured on a device in the `{device}` task.
