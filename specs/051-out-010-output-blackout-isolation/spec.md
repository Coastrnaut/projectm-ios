# Feature Specification: OUT-010 Output Blackout Isolation

**Feature Branch**: `feature/out-010` (spec directory `051-out-010-output-blackout-isolation`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement OUT-010 (Output blackout isolation) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Black out selected output while
keeping control preview active." Acceptance, verbatim: "External output goes black within one
frame; editor remains responsive." Depends on OUT-001 (integrated). Verification: simulator external
display, then physical displays last (HDMI and AirPlay on D1/D2). Implement only OUT-010."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `OUT-010-R1…`, success criteria `OUT-010-S1…`, tasks `OUT-010-T01…`. Requirements
of other features are cited by their own IDs: OUT-001-R1 to R12 (external display scene), FR-072
(Reduce flashing), FX-019-R1 to R11 (strobe envelope), FR-065 (what the app may store), FR-070
(accessibility labels), FR-085 (Paused), PERF-011 (presentation loss).

## Baseline: what exists today (audit of 2026-11-13, commit `bc435fb`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Output | OUT-001: one visualization, drawn in one slot: the external display's window while one is connected, else the device. | No way to make the output black on purpose. |
| Pause | FR-085: Pause freezes the last frame (dimmed on the device, the frozen frame on the external display). | A frozen picture is still a picture: pause is not a blackout. |
| Stop | Stop ends the source and leaves the visualizer. | Stopping the music to hide the picture interrupts the set. |
| Flash safety | FX-019 envelope (projectM post-pass) and the composite flash guard limit what the visual draws. | Nothing limits a change made above the visual (a cover or fade). |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Does the device show a live preview of the visualization while the external display is blacked out ("control preview")? → A: No. The device keeps its controls, sheets and badges fully usable (the "control preview" is the control surface), and the visualization stays in the external display's slot under the blackout. Moving the one visualization back to the device while blacked out would resize its drawable twice per blackout (device size, then the projector's size on restore), so the first frames the audience sees after restore could be drawn at the wrong size or after a re-layout stall, exactly at the moment the restore must be clean; drawing it twice is excluded by OUT-001-R3. A device preview of the output belongs with OUT-012 (rehearsal) and OUT-006 (output variants). Rejected: move the visual to the device during blackout (two resizes per cycle, risk at restore); a second render (OUT-001-R3).
- Q: Does the visualization keep rendering while blacked out, or is it paused to save power? → A: It keeps running, hidden. Restore then shows the live current frame of a visual that never stopped (no restart, no stale frame, no first-frame shader stall on restore), the audio and the visual stay in step, and the flash envelope's history continues, so the revealed picture is already within its limits (FX-019-R11). Blackout is a short, deliberate state; its GPU cost is today's cost. Rejected: pausing (restore would show a stale frame and then jump; resuming ANGLE can stall the first frame); stopping the visual (a restart).
- Q: How does restore return the picture, and how is it kept flash-safe? → A: A linear fade of the output's luminance factor from 0 to 1 over 1 s of frame time (Reduce flashing off) or 4 s (on: a white picture rises at most 0.25 per second, FX-019-R8). Black out is always an immediate cut (a fall, the safe direction; FX-019-R6 always permits falls). A restore starts at least 1 s of frame time after the previous restore started; an earlier request waits, black. With a white picture this bounds the blackout alone to at most 4 transitions in any 1 s window, within both budgets (4 and 6). The fade happens above the visual's own envelope, so its limits are checked on a worst-case white picture with the shared flash analysis; the combination with the content's own transitions is a recorded limitation (ADR-0023 amendment). Rejected: a cut back to full brightness (a single large rise, repeatable by tapping); routing the cover through every renderer's envelope (four pipelines touched for one control; a later ACC-012 option).
- Q: Does Black out need a confirmation (long press, two taps) to avoid an accidental trigger? → A: No: one tap blacks out and one tap restores. Blackout is the safe direction (the output only goes black) and must be immediate in an emergency; restore is already slowed by the fade and the restore spacing. The state is always visible on the device (a persistent "Output blacked out" indicator with Restore) so an accidental blackout is noticed and undone at once. Rejected: long press or confirmation (slows the emergency use; VoiceOver users need a plain button).
- Q: What does Black out do without an external display, and does it survive leaving the visualizer? → A: It blacks out the device's visualization (the controls stay); it is offered on every visual (projectM, native spectra, Camera, Photo). The state follows the output across connect, disconnect, visual changes, background and leaving and re-entering the visualizer for the app's lifetime, and it is never stored (FR-065), so a launch always starts live. Rejected: hiding the control without a display (no way to rehearse it, and the device itself may be the output, for example on a mirrored screen); clearing it on disconnect or on leaving the visualizer (would reveal the picture by surprise).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Black out the projected picture at once (Priority: P1)

A performer runs the visualizer on a projector. Something must not be seen (a preset misbehaves, a
speaker walks on stage, a camera picture shows the wrong thing). One tap on Black out on the device
makes the projector black at the next frame. The music keeps playing and the device's controls keep
working.

**Why this priority**: It is the row's acceptance and a stage safety control.

**Independent Test**: With a simulated external display, tap Black out; the external output reports
black at the first frame after the tap, the controls still open and close Settings, and the audio
source was started once.

**Acceptance Scenarios**:

1. **Given** the visualization is on an external display, **When** the user taps Black out, **Then**
   the next frame shown on the external display is black, and nothing of the visualization shows
   there until the user restores it.
2. **Given** the output is blacked out, **When** the user uses the controls (pause, next preset,
   Settings, the preset browser), **Then** they respond as before, and their effect is applied to
   the hidden visualization.
3. **Given** the output is blacked out, **Then** the audio source keeps running and is never
   restarted by blackout or restore.
4. **Given** no external display is connected, **When** the user taps Black out, **Then** the
   device's visualization goes black at the next frame and the controls stay usable.

---

### User Story 2 - Restore without a flash (Priority: P1)

The performer restores the output. The picture returns as a short fade from black to the current
frame of the still-running visualization; it never cuts from black to a bright picture and it never
restarts the visual.

**Why this priority**: A black-to-bright cut on a projector is the kind of luminance step the flash
envelope exists to limit (Constitution: photosensitive safety).

**Independent Test**: A pure model with a fake frame clock: restore produces a fade whose output
luminance (worst case: a white picture) rises within the strobe envelope's limits for both Reduce
flashing settings, and rapid blackout/restore toggling never exceeds the envelope's transition
budget.

**Acceptance Scenarios**:

1. **Given** the output is blacked out, **When** the user restores it, **Then** the visualization
   fades in from black over a fixed time and shows its current frame (not a restarted visual).
2. **Given** Reduce flashing is on, **When** the output is restored, **Then** the output's
   luminance rises no faster than the envelope's rise limit.
3. **Given** the user taps Black out and Restore repeatedly as fast as possible, **Then** the
   output never has more transitions in any one-second window than the envelope allows; a restore
   that would exceed it waits (black) until it fits.
4. **Given** the output is fading in, **When** the user taps Black out, **Then** it is black again
   at the next frame.

---

### User Story 3 - The blackout follows the output (Priority: P2)

The performer plugs or unplugs the display, changes the visual, or the app goes to the background
while the output is blacked out. The output stays black until the user restores it.

**Why this priority**: An unplug or a visual change must never reveal the picture by surprise.

**Independent Test**: Coordinator tests with slot views: connect, disconnect, reconnect, a visual
change and leaving and re-entering the visualizer while blacked out; the slot that holds the visual
is black after every step.

**Acceptance Scenarios**:

1. **Given** the external output is blacked out, **When** the display disconnects, **Then** the
   device's visualization is black (not revealed) and shows the blackout state.
2. **Given** the device output is blacked out, **When** a display connects, **Then** the external
   display shows black.
3. **Given** the output is blacked out, **When** the visual changes (Settings) or the app returns
   from the background, **Then** the output is still black.

### Edge Cases

- Blackout while the user has paused: the output is black; restoring shows the frozen paused frame
  (fading in).
- Blackout on the notice or chooser: the control exists only on the visualizer; the external
  display is already black there (OUT-001-R1).
- A display whose scene goes to the background while blacked out: the visual returns to the device
  under the same blackout (OUT-001-R5).
- VoiceOver: the control's label and value say whether the output is blacked out; the persistent
  blackout indicator is reachable without the controls.
- The app is terminated while blacked out: the next launch starts live (blackout is not stored,
  FR-065).
- A stalled frame clock (long frame) during a fade: the fade advances by at most 0.1 s per frame
  (FX-019-R10), so it never jumps to full brightness.

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-010-R1**: The visualizer's controls MUST offer a Black out control that blacks out the
  current output: the external display while the visualization is on one (OUT-001-R2), otherwise the
  device's visualization. The same control restores the output.
- **OUT-010-R2**: Black out MUST make the output black at the first frame presented after the tap:
  the change is applied within the tap's handling, with no animation, before control returns to the
  system, so the next composited frame is black.
- **OUT-010-R3**: While blacked out, the output MUST show nothing of the visualization (an opaque
  black output), and nothing else (no text or badge on the external display, OUT-001-R1).
- **OUT-010-R4**: Black out and restore MUST NOT start, stop, pause or restart the audio source, the
  visual or its preset; the visualization keeps running hidden so restore shows its current frame,
  and its flash history continues (FX-019-R11).
- **OUT-010-R5**: While blacked out, the device's controls, sheets and badges MUST stay responsive
  and usable; Black out adds no work on the main thread beyond the tap's handling.
- **OUT-010-R6**: Restore MUST fade the output in from black: the output's luminance factor rises
  linearly in frame time over 1 s with Reduce flashing off and over 4 s with Reduce flashing on (so
  a white picture rises at most 0.25 per second, FX-019-R8). A blackout during a fade is applied at
  the next frame as in R2.
- **OUT-010-R7**: Blackout and restore together MUST never produce more luminance transitions
  (FX-019-R1) in any 1 s window than the envelope's budget for the current setting (FX-019-R7, R8):
  a restore starts at least 1 s of frame time after the previous restore started, and a restore
  requested earlier waits, black, until then.
- **OUT-010-R8**: The blackout MUST follow the output: connecting, disconnecting or backgrounding a
  display, changing the visual, leaving and re-entering the visualizer, and the app going to the
  background and back MUST keep the output black until the user restores it.
- **OUT-010-R9**: While blacked out, the device MUST show a persistent indicator ("Output blacked
  out") with a Restore action that stays visible when the controls hide; while the visualization is
  on an external display, the device note says the external display is blacked out.
- **OUT-010-R10**: The control and indicator MUST have accessibility labels and values that state
  the output's state (FR-070).
- **OUT-010-R11**: Blackout MUST NOT be stored (FR-065): every launch starts with a live output.
- **OUT-010-R12**: The blackout and fade rules MUST be testable without a display, the simulator or
  a device, with a fake frame clock and no wall-clock timing.
- **OUT-010-R13**: Only public, documented platform APIs (Constitution I); builds for iOS 26 and 27.

### Key Entities

- **Output blackout state**: live, blacked out, restore waiting, or fading in; the cover's opacity
  for the next frame; frame time since the last restore started.
- **Output**: the slot that holds the visualization (OUT-001's device or external slot).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **OUT-010-S1**: In 100% of runs, the first frame presented after Black out is black (model with a
  fake frame clock; the output slot is opaque black before the tap's handling returns; simulator UI
  check), then on physical displays last.
- **OUT-010-S2**: While blacked out, the controls open and close Settings and pause and resume
  within the UI test's normal waits, and the audio source is started exactly once across blackout
  and restore.
- **OUT-010-S3**: For a white picture, a restore and any blackout/restore toggling sequence stay
  within the envelope's transition budget in every 1 s window, and with Reduce flashing on rise at
  most 0.25 per second (measured with the shared flash analysis).
- **OUT-010-S4**: After every connect, disconnect, visual change and visualizer re-entry while
  blacked out, the slot holding the visualization is black (100% of the specified transitions).
- **OUT-010-S5**: On HDMI and AirPlay displays (D1/D2) the external output is black at the next
  frame after the tap (device stage, owner's hands; a 240 fps camera is optional).

## Assumptions

- "Control preview" is the device's control surface: OUT-001 shows no live preview on the device
  (OUT-001-R3), and this row keeps that (Clarifications).
- One output exists at a time (OUT-001); "selected output" is the output holding the visualization.
  Per-display selection belongs with OUT-006.
- Simulator results are never device evidence (Constitution X); physical display checks are
  `{device}` tasks left to the owner.
