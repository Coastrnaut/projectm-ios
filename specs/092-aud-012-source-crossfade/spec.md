# Feature Specification: AUD-012 Source Crossfade

**Feature Branch**: `feature/aud-012` (spec directory `092-aud-012-source-crossfade`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement AUD-012 (Source crossfade) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md line 99. Observable behavior, verbatim: "Switch between permitted
sources with a bounded audio-analysis handoff." P1, L. Acceptance, verbatim: "Switch sources
mid-session; renderer receives no discontinuous NaN or stale source labels." Verification: unit
tests plus the simulator; device testing for routes and interruptions is last (every `{device}`
task stays open)."

Identifiers carry the roadmap ID: requirements `AUD-012-R1…`, success criteria `AUD-012-S1…`, tasks
`AUD-012-T01…`. Requirements of other features are cited by their own IDs: FR-001 (exactly one active
source), FR-002 (no source starts without a user action), FR-005 (the microphone explainer), FR-007
(Stop), FR-013/FR-042 (the source-and-state indicator), FR-016 (switching stops the old source
first), FR-052 (rapid commands end in the last command's state), FR-070 (accessibility), R-06 (the
normalized ring's freshness and underrun policy), ANL-001-R9 (the analysis tap), ANL-016-R9 (the
capture-session generation), AUD-007 (the route indicator), AUD-011-R3/R9 (the noise gate's
microphone flag and reset).

## Baseline: what exists today (audit and measurement of 2026-11-13, commit `64957c2`)

This is a gap row. There is no mid-session switch: the visualizer's "Choose source" action (status
banner) and Stop both stop the source and return to the chooser (`AppCoordinator.stop()`), which
pauses the visual; picking another row starts it again (`AppCoordinator.start(_:)`,
`CaptureManager.select(_:)`). `CaptureManager.select` while a source runs does switch at the manager
level (FR-016: old source stopped, then a new attempt). A unit harness with two fake sources
(`SwitchBaselineMeasurement`, CaptureKit, DC +0.5 from A then −0.5 from B at 44.1 kHz) measured that
manager-level switch:

| Question | Measured today |
|---|---|
| Gap of silence? | Yes. From A's stop until B's first buffer the renderer reads 0 frames (R-06: no silence is injected), so projectM keeps showing A's last PCM, frozen, for the whole start time of B (a permission prompt or the system picker can make that seconds). |
| Is the ring cleared? | Yes. `beginAttempt` drains the sink ring, projectM's ring and the analysis tap and advances the session generation (1 → 2); no unread A frame survives. |
| Stale A frames after the label changed? | Not observable on the main actor, but the label changes first: `activeMode` becomes B right after A's `stop()` returns and before the rings are reset (same synchronous step), so for an instant the analysis worker can read A frames while the label already says B. |
| Discontinuity | A hard cut: A's last sample 0.5, B's first sample −0.5, a step of 1.0 (full scale) in projectM's input and in the analysis copy. |
| NaN or Inf | Not sanitized anywhere. NaN/±Inf written by a source at 44.1 kHz reach projectM's ring and the analysis tap unchanged (3 of 3). One NaN at 48 kHz becomes 29 NaN samples after the resampler, and the level meter then reports −120 dBFS (floor) for a −12 dBFS buffer, so a NaN can make the audio-state classifier see silence. |
| Label before or after audio? | Before: the indicator shows "<B> · Waiting" as soon as A stopped, while no B frame exists. |

## Clarifications

### Session 2026-11-13

(Filled by `/speckit-clarify`.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Switch source without leaving the visualizer (Priority: P1)

A user visualizing In-App Playback wants to react to the room instead. From the visualizer controls
they choose "Switch Source" and pick Microphone. The picture keeps running; the audio it reacts to
fades out, the indicator says the source is switching, and the new source fades in; the indicator
then names the new source with its state.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: A UI test with two fake sources switches mid-session and checks the indicator
and that the visual keeps rendering; unit tests drive the manager with fake sources.

**Acceptance Scenarios**:

1. **Given** the visualizer running source A, **When** the user switches to source B, **Then** the screen stays on the visualizer, the visual is not paused or recreated, and source A is stopped before source B starts (FR-001, FR-016).
2. **Given** a switch, **When** it runs, **Then** the indicator reads, in order, "A · <state>", "Switching source…", then "B · <state>", and never shows A again after the switch was requested.
3. **Given** a switch, **When** B delivers its first audio, **Then** the indicator shows B; if B fails to start or is cancelled, the indicator shows B with the failure state and the banner as for any start.
4. **Given** the switch list, **When** it opens, **Then** it offers only the other modes that are available on this device (System/App Capture is absent where it is unavailable), with the current source not offered.

---

### User Story 2 - Clean audio at the renderer boundary (Priority: P1)

Whatever the sources deliver and however fast the user switches, projectM and the native visuals
receive only finite samples within bounds, and the audio they react to changes smoothly at a switch.

**Why this priority**: It is the row's acceptance ("no discontinuous NaN").

**Independent Test**: Unit tests with fake sources that inject NaN and ±Inf and switch A → B, B → A
and during a switch.

**Acceptance Scenarios**:

1. **Given** a source that writes NaN or ±Inf, **When** the audio is normalized, **Then** projectM's ring and the analysis tap contain only finite samples, each bad sample is replaced by 0 and counted, and the audio-state levels are computed from the sanitized audio.
2. **Given** a switch between two constant-level sources, **When** the written stream is read in order, **Then** no sample-to-sample change caused by the handoff exceeds the ramp bound, and the stream reaches exactly 0 between the sources.
3. **Given** a switch, **When** it completes, **Then** the whole handoff (fade-out, gap, fade-in) took no longer than the handoff bound measured on the sample clock.
4. **Given** a switch, **When** the analysis consumers read the tap after the switch point, **Then** no frame of the old source's session is delivered to them, and the session generation tells them a new session began.

---

### User Story 3 - Stop, rapid switching and failures stay truthful (Priority: P2)

Stop during a switch, a second switch before the first finished, and a failed start all end in the
state of the last command, with no duplicate sessions and no stale label.

**Independent Test**: Unit tests with held starts and repeated switches.

**Acceptance Scenarios**:

1. **Given** a switch in its fade-out, **When** the user taps Stop, **Then** the old source stops, nothing starts, the label never shows the target, and the app returns to the chooser as Stop always does.
2. **Given** a switch to B not yet finished, **When** the user switches to C, **Then** B never runs (or is stopped), C runs, the gain never jumps, and the indicator ends on C.
3. **Given** the noise gate on (AUD-011), **When** the source switches to or from Microphone, **Then** the gate's microphone flag changes at the switch point and the gate restarts closed for the new session.

### Edge Cases

- The old source is paused, interrupted or delivers nothing: the fade-out cannot wait for audio; it completes at once from the last delivered sample.
- The target is Microphone and its explainer was never shown: the app returns to the chooser and shows the explainer (FR-005), like the chooser row.
- The target needs a system prompt or picker (permission, System/App Capture's picker): the indicator stays "Switching source…" until the source starts or fails; the visual keeps running on silence.
- A source starts but delivers no audio: the indicator shows the new source as soon as its state is decided (for example "No audio received").
- Switching to the source that is already active: nothing happens.
- Values much louder than full scale (a broken source): clamped to the bound and counted.
- The app goes to the background during a switch: lifecycle events wait for the switch (serialized) and then apply as today.

## Requirements *(mandatory)*

### Functional Requirements

- **AUD-012-R1**: The visualizer MUST offer a "Switch Source" control that lists the other available source modes and switches to the chosen one without leaving the visualizer; the visual MUST keep running (not paused, not recreated). Only modes the user already may start from the chooser are offered; nothing new is captured or permitted (FR-002).
- **AUD-012-R2**: A switch MUST keep exactly one source active (FR-001): the old source is stopped before the new one starts (FR-016).
- **AUD-012-R3**: Handoff shape: the audio handed to the renderer and to the analysis copy fades from the old source to silence over a fixed ramp, holds a short silence, then fades in from silence to the new source over the same ramp. The ramp and the bound are fixed values (set in Clarifications).
- **AUD-012-R4**: Ramp bound: every sample-to-sample change the handoff adds to the written stream MUST stay within a documented bound, and the stream MUST reach exactly 0 between the two sources.
- **AUD-012-R5**: The fade-out MUST NOT wait longer than a fixed limit; if the old source does not deliver enough audio within it (paused, interrupted, silent stream), the fade-out completes from the last delivered sample with a ramp that respects R4.
- **AUD-012-R6**: Handoff bound: fade-out wait + silence + fade-in ≤ the handoff bound (Clarifications), on the sample clock. The new source's own start time (a prompt, the picker) is not part of the bound.
- **AUD-012-R7**: Label rule: from the switch request until the new source's first audio has been observed (or its attempt has ended or its state is decided), the source-and-state indicator, its accessibility label and announcements read "Switching source…" and name no source; the old label MUST NOT be shown after the request; the new label is shown from that point on. The AUD-007 route indicator is hidden during the same window.
- **AUD-012-R8**: Generation rule: at the switch point (old source stopped) the analysis tap is emptied and only then the capture-session generation advances (ANL-016-R9), so analysis consumers can detect and drop frames of the old session; no old-session frame may be written to the tap after the generation advanced.
- **AUD-012-R9**: Sanitizer: every sample handed to the renderer's ring and the analysis tap MUST be finite and within a fixed bound; non-finite samples become 0 and out-of-range samples are clamped, and each replacement is counted in diagnostics (a count only; no audio content is logged or stored). Non-finite samples MUST also be replaced before level metering and conversion, so they cannot hide audio from the classifier or poison the converter.
- **AUD-012-R10**: The sanitizer MUST leave clean audio bit-identical and cost no copy when the audio is clean, and MUST NOT allocate, lock or log; it runs on the analysis queue, never on an audio callback (Constitution VII).
- **AUD-012-R11**: Stop during a switch stops the old source, starts nothing and returns to the chooser (FR-007); a second switch during a switch supersedes the first (FR-052) and continues the gain from its current value.
- **AUD-012-R12**: AUD-011's microphone flag follows the source at the switch point; the gate restarts closed for the new session (AUD-011-R9).
- **AUD-012-R13**: A switch to Microphone whose explainer is pending MUST go through the chooser's explainer (FR-005).
- **AUD-012-R14**: Accessibility (FR-070): the control's label is "Switch Source"; each choice is the mode's label (contracts/ui-states.md); identifiers `switchSource` and `switchSource:<mode raw value>`.
- **AUD-012-R15**: Starting a source from the chooser, Stop, Restart and the existing banner actions behave exactly as before (no fade, no switching label).

### Key Entities

- **Handoff**: target mode, phase (fading out, switching, fading in), a ramp position.
- **Renderer boundary**: the ring that feeds projectM and the analysis tap, with the sanitizer and the handoff gain; a sanitized-sample count.
- **Switching label**: the manager's "switching" state that the indicator reads.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-012-S1**: Across switches A → B, B → A and A → B → A (switch during a switch) with sources that inject NaN and ±Inf, 0 non-finite and 0 out-of-bound samples reach projectM's ring or the analysis tap; every injected bad sample is counted.
- **AUD-012-S2**: With constant-level sources, the largest sample-to-sample change in the written stream during a switch is within the ramp bound, and the stream holds exactly 0 between the sources.
- **AUD-012-S3**: Every handoff completes within the handoff bound on the sample clock.
- **AUD-012-S4**: The label sequence during a switch is exactly "A", "Switching source…", "B" (unit test on the manager and one UI test).
- **AUD-012-S5**: 0 frames of the old session are read from the tap after the switch point.
- **AUD-012-S6**: Clean audio through the boundary is bit-identical (projectM's ring equals the written frames).
- **AUD-012-S7**: The UI test switches mid-session in under 30 s; StatusUITests, TransportUITests and InterruptionUITests pass unchanged.
- **AUD-012-S8**: No new permission, usage string or entitlement; the permission catalog check and the privacy manifest check pass.

## Assumptions

- Audio at the boundary is Float32 interleaved stereo at 44.1 kHz (the normalized ring).
- Real routes, real interruptions and switches between real sources on D1-D3 are `{device}` work for the roadmap's last phase; simulator results are not evidence for them.
- No network; no audio is stored.
