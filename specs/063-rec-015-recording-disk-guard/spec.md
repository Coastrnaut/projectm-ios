# Feature Specification: REC-015 Recording disk guard

**Feature Branch**: `feature/rec-015` (spec directory `063-rec-015-recording-disk-guard`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement REC-015 (Recording disk guard) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Estimate free space and stop
cleanly before storage exhaustion." Acceptance, verbatim: "Simulated low-space error finalizes or
reports incomplete file safely." P0, effort M, depends on REC-003 (integrated). Verification: fixture +
simulator (+ a device task: a nearly full D1 or a long recording until the guard stops it). A
pre-flight check at Record, a low-cost periodic check while recording that stops with a low-storage
reason and keeps a playable file, typed handling of real out-of-space writer errors (no corrupt file
is ever offered), injectable storage and writer-failure seams for tests, and the disk-space
required-reason API declared in the privacy manifest."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `REC-015-R1…`, success criteria `REC-015-S1…`, tasks `REC-015-T01…`. Requirements of
other features are cited by their own IDs: REC-003 (video recording, `specs/058-rec-003-video-recording`,
ADR-0027), REC-012 (share via Files, `specs/060-rec-012-share-via-files`), FR-065 (what the app may
store), FR-066 (privacy manifest), FR-070 (accessibility).

## Baseline: what exists today (audit of 2026-11-13, commit `edf30a0`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Free space before Record | Not checked (ADR-0027: "REC-015 adds a free-space estimate"). | A recording can start with almost no space left. |
| Free space while recording | Not checked. The writer runs until the 10-minute limit or a failure. | The device can fill up mid-recording. |
| Out-of-space writer errors | Any writer failure deletes the partial file and shows "The recording couldn't be finished." (REC-003-R17). | No specific reason is given; the user is not told storage is the cause. |
| Temporary files | `<tmp>/Recordings` is emptied at launch (REC-003-R13); `<tmp>/Sharing` likewise (REC-012-R6). | None (verified, not duplicated). |
| Privacy manifest | Declares user defaults, system boot time and file timestamp. No disk-space API is used. | A free-space read is a required-reason API (Disk space) and must be declared. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: How much free storage must remain, and how much recording must fit before Record starts? → A: A fixed safety reserve of 200 MiB (209,715,200 bytes) that the recording never eats into, plus room for 60 seconds at the estimated rate before Record starts. While recording, the stop comes when less than the reserve plus two check intervals (10 s) of writing remains. The reserve leaves room to finish the file (its index) and for the system, which misbehaves when the device is completely full. Rejected: a percentage of the device's capacity (meaningless across 64 GB and 2 TB devices); stopping only at the reserve (a write burst between two checks could cross it).
- Q: Which free-storage figure is read? → A: The system's "available capacity for important usage" of the volume holding the temporary recording folder: the figure Apple documents for user-initiated work, which counts space the system can purge for it. It is a required-reason API (Disk space), declared with reason E174.1 (check there is enough space to write files). Rejected: the "opportunistic" figure (too pessimistic for a user-started recording); the raw available capacity (ignores purgeable space, refusing recordings that would fit); file-system attribute dictionaries and `statfs` (same category, more than needed).
- Q: What happens when the free-storage value cannot be read? → A: The recording starts or continues; the sample is skipped. The guard is a safety net, not a gate the system's silence should close, and real out-of-space errors are still caught (REC-015-R7). Rejected: refuse to record (a transient read failure would block the feature).
- Q: Is a recording stopped for low storage kept or discarded? → A: Kept: the file is finished like every REC-003 stop and offered in the "Recording ready" panel (Save…, Share…, Discard; REC-012). Only an out-of-space writer failure, which leaves a file that cannot be finished, deletes the partial file and says "Storage is full; the recording couldn't be saved.". Rejected: discard on low storage (loses the user's work, which the acceptance's "finalizes" forbids); offer a partial, unfinished file (it would not play).
- Q: Should the app warn ahead of the stop (for example "1 minute of storage left")? → A: No. This row stops cleanly and says why; an ongoing storage warning in the recording overlay is REC-009 ("storage warnings only in UI"). Rejected: a countdown notice now (duplicates REC-009 and adds UI churn during recording).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Record refuses when there is no room (Priority: P1)

A user whose device is nearly full taps Record. Instead of starting a recording that would fail
seconds later, the app says there isn't enough free storage to record, and nothing starts.

**Why this priority**: It prevents the most common failure before any work is lost.

**Independent Test**: Unit test with an injected storage value below the requirement; UI test with a
DEBUG fake low-space value.

**Acceptance Scenarios**:

1. **Given** free storage below what one minute of video at the current size plus the safety reserve needs, **When** the user taps Record, **Then** no recording starts and the notice reads "There isn't enough free storage to record. Free up space and try again.".
2. **Given** enough free storage, **When** the user taps Record, **Then** recording starts as before.
3. **Given** the free-storage value cannot be read, **When** the user taps Record, **Then** recording starts (the in-recording checks and writer error handling still protect the file).

---

### User Story 2 - A recording stops cleanly before storage runs out (Priority: P1)

A user records a long session while free storage shrinks (the recording itself, or another app
downloading). Before the device is full, the recording stops by itself, the file is finished so it
plays, and the user is told why. The "Recording ready" panel offers it as usual.

**Why this priority**: It is the row's observable behavior and its acceptance ("finalizes").

**Independent Test**: Fixture test (offline writer, a fake storage value that drops at frame k): the
finished file decodes with about k frames and increasing times. UI test with a DEBUG fake drop.

**Acceptance Scenarios**:

1. **Given** a recording in progress, **When** free storage falls to the point where the next check could find less than the reserve, **Then** the recording stops with the notice "Recording stopped because storage is almost full." and the finished file is offered.
2. **Given** the stopped file, **When** it is read back, **Then** it plays: it has every frame written up to the stop, with strictly increasing times.

---

### User Story 3 - The device really runs out of space (Priority: P2)

Despite the checks (another app filled the device between two checks), the writer reports that the
disk is full. The partial file cannot be finished; the app deletes it and says so. No broken file is
ever offered.

**Why this priority**: It is the second half of the acceptance ("reports incomplete file safely").

**Independent Test**: Unit tests with an injected out-of-space writer failure.

**Acceptance Scenarios**:

1. **Given** a recording in progress, **When** the writer fails with an out-of-space error, **Then** the recording stops, the partial file is deleted, nothing is offered, and the notice reads "Storage is full; the recording couldn't be saved.".
2. **Given** a writer failure for any other reason, **Then** the REC-003 behavior is unchanged ("The recording couldn't be finished.").

### Edge Cases

- Free storage cannot be read (the system returns nothing): Record proceeds; the periodic check skips that sample.
- The free-storage value jumps up during a recording (the user deleted files): the recording continues.
- A stop for low storage arrives while another stop is already finishing: the first stop wins (REC-003 stops are idempotent).
- Fewer than two frames were written when the low-storage stop happens: "Nothing was recorded." as in REC-003 (no file).
- The finishing step itself fails for lack of space (writing the file index): the partial file is deleted and the out-of-space notice is shown.
- An out-of-space error is wrapped inside another error by the system: it is still recognized.
- A result is already offered: Record refuses for that reason first (REC-012-R10); no storage read happens.
- A recording reaching the 10-minute limit with plenty of space: unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **REC-015-R1**: Before a recording starts (after the REC-003 refusal rules and REC-012-R10), the app MUST read the free storage available for important use on the volume holding the temporary recording folder, once.
- **REC-015-R2**: The app MUST estimate the recording's write rate from its picture size and frame rate using the highest average bit rate among the codecs it may use, plus 25% headroom for bit-rate peaks and the file index.
- **REC-015-R3**: Record MUST refuse, start nothing and show "There isn't enough free storage to record. Free up space and try again." when the free storage is below the safety reserve (200 MiB) plus 60 seconds at the estimated rate.
- **REC-015-R4**: While recording, the app MUST read the free storage at most once every 5 seconds, off the main thread and never on the frame loop, together with the recording file's current size.
- **REC-015-R5**: The app MUST stop the recording with the reason "low storage" when the free storage is below the reserve plus two check intervals at the larger of the estimated rate and the measured rate (file size over recorded time).
- **REC-015-R6**: A low-storage stop MUST finish the file like every other REC-003 stop, offer it (REC-012-R1) and show "Recording stopped because storage is almost full.".
- **REC-015-R7**: A writer failure whose error (or any underlying error) is an out-of-space error MUST be reported as a distinct "storage full" failure: the partial file is deleted, nothing is offered, and the notice reads "Storage is full; the recording couldn't be saved.".
- **REC-015-R8**: Other writer failures keep the REC-003 behavior and notice.
- **REC-015-R9**: An unreadable free-storage value MUST NOT refuse or stop a recording.
- **REC-015-R10**: The free-storage value MUST be used only on the device to decide whether to start or stop a recording; it MUST NOT be stored, logged or sent.
- **REC-015-R11**: The privacy manifest MUST declare the disk-space category with reason E174.1, and the manifest check MUST accept exactly the declared reasons per category and flag any undeclared use.
- **REC-015-R12**: The storage reading and the writer failure MUST be replaceable in tests (injected values and an injected out-of-space failure); DEBUG builds MAY fake both with launch options; Release builds contain no fakes reachable from launch options.
- **REC-015-R13**: Temporary recording and sharing leftovers stay covered by REC-003-R13 and REC-012-R6 (verified, not duplicated).
- **REC-015-R14**: The notices MUST be announced like the other recording notices (FR-070).

### Key Entities

- **Storage estimate**: bytes per second for a recording's size, frame rate and codecs; bytes needed to start.
- **Storage reading**: the free bytes available for important use (or unknown), and the recording file's size.
- **Low-storage stop**: a new recording stop reason.
- **Storage-full failure**: a new recording failure.

## Success Criteria *(mandatory)*

- **REC-015-S1**: With a free-storage value below the start requirement, Record starts nothing and shows the exact refusal notice (unit and UI tests).
- **REC-015-S2**: With a free-storage value that drops below the threshold at frame k, the recording stops and the finished file reads back with k frames and strictly increasing times (fixture test).
- **REC-015-S3**: An injected out-of-space writer failure yields the storage-full outcome, leaves no file and shows the exact notice (unit tests).
- **REC-015-S4**: The estimate matches hand-computed values for representative sizes and codecs (unit tests).
- **REC-015-S5**: The manifest check passes on the built app with the disk-space declaration and fails when the declaration is missing or carries another reason (script tests, app scan).
- **REC-015-S6**: On D1, nearly full (or with a long recording), the guard stops the recording with the low-storage notice and the offered file plays (owner, device).

## Assumptions

- "Available for important use" is the system's figure for user-initiated work, which a recording is; it may count purgeable space the system can free.
- The written file grows roughly at the encoder's average rate; the measured rate covers encoders that exceed it.
- A 200 MiB reserve keeps room for finishing the file and for the system; a 60-second minimum avoids recordings that stop at once.
- The free-space read is quick (well under a millisecond) and runs once at Record and every 5 seconds while recording.
- REC-016 (interruption recovery) and REC-009 (status overlay with storage warnings) are separate rows.
