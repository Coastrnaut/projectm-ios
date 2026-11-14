# Feature Specification: REC-006 Record frame rate

**Feature Branch**: `feature/rec-006` (spec directory `164-rec-006-record-frame-rate`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement REC-006 (Record frame rate) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Choose supported 24, 30 and 60 fps export targets." Acceptance,
verbatim: "Fixture output reports selected nominal frame rate and bounded dropped frames." P1, M,
depends on REC-003 (integrated); REC-005 (quality profiles) is integrated too."

Identifiers carry the roadmap ID: requirements `REC-006-R1…`, success criteria `REC-006-S1…`, tasks
`REC-006-T01…`, research decisions `REC-006-D1…`.

## Baseline: what exists today (audit of 2026-11-14, commit `13f384e5`)

| Area | Today |
|---|---|
| Frame times | REC-003 (ADR-0027 decision 2): each written frame's time is the frame loop's own presentation time relative to the first frame, rounded to 1/600 s. A rate cap skips frames closer than ¾ of an interval to the next slot; after a stall the slots restart from the late frame. Times are therefore close to, but not exactly, multiples of 1/fps, and a 120 Hz loop recorded at 30 fps takes frames up to ¼ interval early. |
| Frame rate | REC-005 profiles fix it: Draft and Standard 30 fps, High and Max 60 fps. A profile whose rate the display cannot show is unavailable (REC-005-R4) and Record falls back to a lower profile (X9c notice). No separate frame-rate choice. |
| Capabilities | `RecordingEncoderCapabilities`: `canEncode(codec, width, height)` and the display's `maxFramesPerSecond` (app: `UIScreen.maximumFramesPerSecond`). The app's render loop is capped at 30 fps in Low Power Mode and at serious thermal state (`QualityGovernor`), which REC-005 does not consider. |
| Drops | `RecordingStatistics` counts frames left out (queue full, encoder not ready, non-increasing time) and rate skips. Nothing counts frame *slots* of the output that got no picture. |
| Read-back | `RecordedVideoInspector`: frame count, every frame time (1/600 s), duration, `nominalFrameRate` computed as frames / duration. |
| Settings | Settings → Recording quality (REC-005): four profile rows, disabled with a reason when unavailable. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: A separate frame-rate setting, or a per-profile override? → A: A separate setting, "Frame rate", with four choices: Profile default (the default), 24, 30 and 60 fps. Profile default keeps REC-005 exactly (a user who never opens it records as before); an explicit rate overrides the profile's rate and nothing else (size, codec, bit rate). One extra short list is clearer than doubling the profile table.
- Q: Which rates? → A: Exactly 24, 30 and 60 fps: the roadmap's export targets. All divide the file's 1/600 s timescale exactly (25, 20 and 10 ticks).
- Q: How are frame times written? → A: On an exact grid: the n-th output slot is at n/fps from the first frame (n × 600/fps ticks). For each slot the recorder takes the rendered frame nearest to it (ties go to the earlier frame), so 60 → 24 fps decimates by nearest frame, not by every other frame. This replaces REC-003's rounded real times for all recordings; ADR needed (it amends ADR-0027 decision 2).
- Q: What happens to a slot that no rendered frame is near (a stall, a render loop slower than the target, a frame the bounded queue dropped)? → A: It is skipped: no sample is written for it, the previous picture stays on screen for the gap (a player shows exactly what a repeated frame would), and the slot is counted as a dropped frame in the recording result. Repeating the previous frame was rejected: it needs an extra retained pixel buffer and a burst of encoder work right after a stall, when a real-time encoder is least able to take it.
- Q: When is a rate unavailable? → A: When the display cannot show it (`maximumFramesPerSecond` below it), when the visual's render loop is capped below it (Low Power Mode or serious thermal state cap the loop at 30 fps), or when the encoder reports a lower frame-rate limit for the planned codec and size. Unavailable rates are shown disabled with a reason, never hidden, and cannot be picked.
- Q: What happens at Record with an explicit rate that is unavailable at that moment (Low Power Mode switched on)? → A: The recording uses the highest supported rate below it that is available, starts, and announces "Recording at 30 fps: <reason>." through the status router (row X9c, the same row as a profile fallback). The stored choice is unchanged. 24 fps is always available on a working display, so a rate fallback never refuses.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Does an explicit rate change a profile's bit rate? → A: Only through the profile's own rule. Fixed-rate profiles (Draft 4, High 20, Max 40 Mb/s) keep their bit rate at any frame rate; Standard keeps REC-003's per-pixel-per-frame rule, so its bit rate follows the effective rate (about 6 Mb/s at 1080p24 HEVC). The disk guard's estimate uses the same effective rate and bit rate.
- Q: Where is the dropped-frame count shown? → A: In the recording result (the recorder's result and the coordinator's last-recording facts, read by tests and the DEBUG probe). No new user-facing notice: a drop count means nothing to most users, and the notices already cover stops and fallbacks.
- Q: Where does the picker live in Settings? → A: Its own section, "Recording frame rate", directly under "Recording quality", with four rows built like the profile rows (buttons, not a menu Picker, so a disabled row stays visible with its reason).
- Q: What does "jittery rendering" mean in the acceptance fixture? → A: Deterministic: a 120 Hz loop whose frame times each move by a pseudo-random offset of up to ±2 ms (fixed seed), and a 60 Hz loop with up to ±3 ms. Both stay at or above every target on average; at most 1% of slots may be dropped (REC-006-S2).
- Q: Does the rate fallback apply to Profile default too? → A: Only the render cap and the encoder limit do: a 60 fps profile in Low Power Mode records at 30 fps with the rate notice. The display limit keeps REC-005's profile fallback for Profile default (High on a 30 fps display still falls back to Standard), so REC-005's behaviour is unchanged wherever no render cap applies.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Record at a chosen export frame rate (Priority: P1)

A user who edits recordings in a 24 fps or 30 fps project opens Settings → Recording quality, picks
"Frame rate: 24 fps", and records; the file plays at exactly 24 fps whatever the screen's refresh
rate was.

**Why this priority**: It is the roadmap row: supported 24, 30 and 60 fps export targets, with the
nominal rate reported.

**Independent Test**: Fixture: for 24, 30 and 60 fps, frames with injected render times (60 Hz,
120 Hz, jittery, and one 200 ms stall) are recorded with the real writer and read back: the nominal
frame rate equals the selection and every frame time is exactly n/fps.

**Acceptance Scenarios**:

1. **Given** 24 fps is selected and the visual renders at 60 Hz, **When** the user records, **Then** the file's nominal frame rate is 24, every frame time is a whole multiple of 1/24 s, and each written frame is the rendered frame nearest its slot.
2. **Given** Profile default is selected, **When** the user records with High, **Then** the file is 60 fps, exactly as REC-005 recorded it.
3. **Given** the user picks 30 fps, **When** the app is relaunched, **Then** 30 fps is still selected.

---

### User Story 2 - Dropped frames are counted and bounded (Priority: P1)

When the visual stalls during a recording, the recording result reports how many output frames had
no picture; steady rendering at or above the target reports none.

**Why this priority**: The acceptance names "bounded dropped frames".

**Independent Test**: Same fixture: the dropped count equals the slots inside the injected 200 ms
stall and is zero for steady 60 Hz and 120 Hz rendering at each target.

**Acceptance Scenarios**:

1. **Given** steady rendering at 60 Hz or 120 Hz, **When** recording at 24, 30 or 60 fps, **Then** the dropped count is 0 and the frame count is duration × fps.
2. **Given** one 200 ms stall, **When** recording at fps F, **Then** the dropped count equals the number of slots inside the stall with no rendered frame near them, or one more when the frame just before the stall was passed over for a predicted nearer one (REC-006-D2), and never more than ⌈0.2 × F⌉.

---

### User Story 3 - Unsupported rates are disabled with a reason (Priority: P2)

On a 30 fps-capped display, in Low Power Mode, or with an encoder limit, 60 fps is shown disabled
with its reason and cannot be picked.

**Independent Test**: Injected capabilities: display at most 30 fps, a Low Power render cap, an
encoder limit of 30 fps; the 60 fps row is disabled with the matching reason; 24 and 30 stay enabled.

**Acceptance Scenarios**:

1. **Given** the display shows at most 30 fps, **When** the rows are listed, **Then** 60 fps is disabled with "This display shows at most 30 fps."
2. **Given** Low Power Mode is on, **When** the rows are listed, **Then** 60 fps is disabled with "Low Power Mode limits the visual to 30 fps."
3. **Given** 60 fps is selected and Low Power Mode turns on, **When** the user records, **Then** the recording is 30 fps and the app announces "Recording at 30 fps: Low Power Mode limits the visual to 30 fps."

### Edge Cases

- The render loop runs slower than the target (30 Hz rendering, 60 fps target): every other slot has no picture and is counted as dropped; the file is still on the 60 fps grid.
- Jittery frame times: a frame is placed in the slot it is nearest; at most one frame per slot.
- A frame time not later than the last written frame's, or before the first frame: not written (REC-003 rule kept).
- The 10-minute limit: a slot at or beyond it stops the recording (REC-003 rule kept, on slot times).
- A profile fallback and a rate fallback at the same Record: both notices are shown, profile first.
- Profile default with a 60 fps profile in Low Power Mode: the render cap lowers the rate to 30 with the same rate notice (otherwise half the slots would be dropped).
- Audio (REC-004) is placed by its own clock from the first frame; slot times differ from render times by at most half a slot, so audio and video stay within half a frame and never drift.

## Requirements *(mandatory)*

### Functional Requirements

- **REC-006-R1**: The app MUST offer a frame-rate choice with exactly these values: Profile default (default), 24 fps, 30 fps, 60 fps. Profile default MUST record at the selected profile's rate (REC-005-R1); an explicit rate MUST replace only the profile's rate.
- **REC-006-R2**: Every written frame's time MUST be exactly n/fps after the first frame for a whole number n (n × 600/fps ticks of the 1/600 s timescale), strictly increasing.
- **REC-006-R3**: For each slot the recorder MUST write the rendered frame nearest to the slot time, deciding without waiting for later frames beyond a one-frame prediction; ties go to the earlier frame; at most one frame per slot.
- **REC-006-R4**: A slot with no rendered frame written for it, between the first and last written frame, MUST count as one dropped frame; the recording result MUST report the dropped count and the nominal frame rate. Slots MUST NOT be filled by repeated frames.
- **REC-006-R5**: The file's video track MUST declare the selected rate (expected source frame rate) so that, read back, its minimum frame duration is 1/fps and, without dropped frames, its nominal frame rate equals the selection.
- **REC-006-R6**: A rate MUST be available only when the display can show it, the render loop is not capped below it (Low Power Mode, serious thermal state), and the encoder's frame-rate limit for the planned codec and size allows it. Unavailable rates MUST be shown disabled with a one-line reason and MUST NOT be selectable.
- **REC-006-R7**: Record MUST check the rate again. With an unavailable explicit rate (or a profile rate above the render cap or encoder limit) it MUST record at the highest available supported rate below it and show and announce "Recording at <rate> fps: <reason>." (row X9c); the stored choice MUST stay unchanged.
- **REC-006-R8**: The choice MUST be stored on the device (key `settings.recording.frameRate`; absent or unknown reads as Profile default), reset by the UI-test reset, erased with the Settings category, and left out of the library backup.
- **REC-006-R9**: The choice MUST be in Settings as its own "Recording frame rate" section directly under "Recording quality"; each row MUST name the rate (Profile default shows the profile's rate) and, when disabled, its reason; VoiceOver MUST read the row, its selected state and its reason. The profile rows MUST describe the effective rate.
- **REC-006-R10**: A running recording MUST keep the rate it started with; a change applies to the next recording.
- **REC-006-R11**: Pacing MUST stay within the frame loop's existing budget: no waiting, no extra GPU copy, constant work per frame.
- **REC-006-R12**: An explicit rate MUST change a profile's bit rate only through the profile's own rule (fixed rates stay fixed; Standard's per-pixel rule uses the effective rate), and the disk guard MUST estimate with the effective rate.

### Key Entities

- **Frame-rate choice**: Profile default, 24, 30 or 60 fps; device-local.
- **Rate availability**: available, or unavailable with a reason (display limit, render cap, encoder limit).
- **Slot timeline**: the first frame's time, the next free slot, the last offered frame's time; maps a rendered frame to a slot or a skip.
- **Recording result**: frames written, dropped frames (empty slots), nominal frame rate.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **REC-006-S1**: For each of 24, 30 and 60 fps and each injected pattern (60 Hz, 120 Hz, jittery, one 200 ms stall), the read-back file's nominal frame rate (or minimum frame duration) equals the selection and 100% of frame times are exactly n/fps.
- **REC-006-S2**: Steady rendering at or above the target gives 0 dropped frames; the 200 ms stall gives the number of empty slots in the stall, or one more (the frame just before the stall passed over for a predicted nearer one), and at most ⌈0.2 × fps⌉; jittery rendering at or above the target drops at most 1% of slots.
- **REC-006-S3**: Decimating 60 Hz rendering to 24 fps writes, for 100% of slots, the rendered frame nearest the slot (ties to the earlier).
- **REC-006-S4**: With a 30 fps display, a Low Power cap or a 30 fps encoder limit, 60 fps is disabled with the matching reason and 24 and 30 stay enabled.
- **REC-006-S5**: The picker UI test selects a rate and sees it selected in under 30 s.
- **REC-006-S6**: On a device, a 24 fps recording of a 60 Hz or 120 Hz visual reads back at 24 fps with the reported dropped count (device stage, `{device}`).

## Assumptions

- The host Mac's encoders accept 24, 30 and 60 fps at the fixture size; the fixture uses a small drawable so it runs in seconds.
- VideoToolbox publishes no per-size frame-rate limit through public API; the real capability source reports 60 fps (the highest offered rate) and the writer's `canApply` stays the final gate. Tests inject lower limits.
- 25, 50 and 120 fps, variable frame rate exports and frame interpolation are out of scope.
- QA-008 will consolidate recording validation fixtures later; this feature's fixture stays self-contained.
