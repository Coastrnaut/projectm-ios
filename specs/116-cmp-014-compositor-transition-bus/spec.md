# Feature Specification: CMP-014 Compositor Transition Bus

**Feature Branch**: `feature/cmp-014` (spec directory `116-cmp-014-compositor-transition-bus`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement CMP-014 (Compositor transition bus) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Blend whole scene outputs using
one consistent transition clock." Acceptance, verbatim: "Crossfade reaches exact start/end states with
no leaked textures." Verification: unit tests, snapshots and GPU performance. P1, size L. Depends on
CMP-002 (ordered layer stack)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-014-R1…`, success criteria `CMP-014-S1…`, tasks `CMP-014-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `9688f80a`)

The row's gap status is "Gap candidate". The audit confirms a gap: nothing blends two whole scene
outputs, and no two scene outputs ever exist at the same time.

| Area | Today | Gap for this row |
|---|---|---|
| Show cues (SHOW-001, ADR-0033) | A step applies the cue's scene through the Settings path (`AppCoordinator+Show.swift`): the visual and its options change at once. A cue has an ID, a scene ID and a label; `show.json` v1 has no transition field. | Every cue change is a cut. |
| Scene transition rows | SCN-007 ("store transition type, duration and easing with each cue", depends on CMP-014) and SHOW-004 (cue transition override) are not integrated. | No stored transition exists; storing one is SCN-007's row. |
| Live output (app) | Each visual is its own host: projectM through ANGLE, the native spectra, and one CMP-001 compositor per Photo, Text, Video and Camera visual. A cue that changes the visual swaps the host in the output slot (OUT-001 `VisualSlotView`). | No whole-scene compositor carries every visual, so two scenes cannot be rendered side by side in the app yet. |
| Compositor (CMP-001 to CMP-013) | One compositor = one layer stack → one composite → the composite flash guard (FX-019) → the output pass; `encodeOutput` repeats the output pass for recording (REC-003). | One scene only; the stack phase and the guard/output phase are fused in one call. |
| Blackout (OUT-010, SHOW-014) | A black cover layer above the visual in each slot; Restore fades it (a safety fade). | Unchanged: it stays above everything the bus draws. |
| projectM preset blend (FR-043, PRE-015 prewarm) | The engine's own soft cut between presets (at most 2 s); the warm-up starts 2.5 s after a switch. | Inside one visual; unrelated to scene changes. Unchanged. |
| PERF-014 placeholder | A 0.5 s linear safety fade over a failed visual. | Unchanged (a safety fade, outside Reduce Motion). |
| Reduce Motion (ACC-001 `MotionPolicy`) | Decorative app animations become instant; safety fades stay. | No scene transition exists to govern. |
| Flash limiting (FX-019) | The composite flash guard runs on each compositor's finished composite. | A blend of two composites would need the guard on the blended frame. |
| Render caching (CMP-013, ADR-0040) | Level 2 keeps a compositor's previous composite when nothing it is made of changed. | A blend must never be reused while its progress moves. |
| Pool (PERF-004), ping-pong (CMP-004), groups (CMP-011), solo/mute (CMP-012) | Every composite and picture comes from a `TexturePool` and goes back to it. | A blend target must come from the pool and go back. |

## Clarifications

### Session 2026-11-14

(Filled by `/speckit-clarify`.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A crossfade starts and ends exactly (Priority: P1) 🎯 MVP

A performer moves from scene A to scene B. The output dissolves from A to B over the transition's
duration. The first frame is exactly A, the last frame and every frame after it is exactly B, and
nothing the transition used is left behind.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: Crossfade a red scene into a blue scene. Read back the frame at progress 0
(byte-identical to A alone), at the midpoint (the reference blend within tolerance) and at progress 1
and after (byte-identical to B alone). Count the pool's checked-out textures before and after: equal.

**Acceptance Scenarios**:

1. **Given** scene A shown, **When** a crossfade to B starts, **Then** the frame at progress 0 is
   byte-identical to A rendered alone.
2. **Given** a running crossfade, **When** progress is 0.5, **Then** every pixel is the reference
   blend of A and B within a half-float tolerance.
3. **Given** a running crossfade, **When** progress reaches 1, **Then** that frame and every later
   frame is byte-identical to B rendered alone, and A's resources are released.
4. **Given** the pool's checked-out count before the transition, **When** it ends, is cancelled or
   is interrupted, **Then** the count is the same as before.

---

### User Story 2 - One clock drives every transition (Priority: P1)

Transition progress follows the frames shown, not the wall clock: it pauses with the visualizer,
resumes where it stopped and finishes exactly at its duration.

**Independent Test**: Feed the clock injected presentation times: progress is a pure function of
them, holds across a pause, and is exactly 1 on the first frame at or after the duration.

**Acceptance Scenarios**:

1. **Given** a 1 s transition, **When** frames arrive every 1/60 s, **Then** progress rises
   monotonically and is exactly 1 on the first frame at or after 1 s.
2. **Given** a paused transition, **When** frames resume after any gap, **Then** progress continues
   from where it paused.

---

### User Story 3 - Safety and accessibility rules hold (Priority: P1)

Reduce Motion makes a scene transition instant; the flash guard limits the blended frame; render
caching never freezes a transition.

**Independent Test**: Resolve a crossfade with Reduce Motion on: a cut. Run a fast dip-to-black
between bright scenes with Reduce flashing: the guard's gain falls below 1. Run a transition between
two static scenes whose compositors reuse their composites: every transition frame differs.

---

### User Story 4 - GPU time is recorded (Priority: P2)

A bench records the GPU time of transition frames against single-scene frames on the Mac (recorded,
not asserted).

### Edge Cases

- A transition of duration 0, or any transition while Reduce Motion is on: a cut on the next frame.
- A new transition while one runs (interruption): decided in Clarifications.
- Cancel during a transition: decided in Clarifications.
- An output size change during a transition: the blend target is replaced from the pool; nothing leaks.
- A frame that fails to encode during a transition: the transition does not advance past what was shown.
- Blackout during a transition: the slot's black cover stays above the output; the transition keeps
  its own clock.

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-014-R1**: A transition clock gives progress 0…1 from the presentation times of the frames
  shown (the compositor's frame timeline), with an easing curve; exact 0 at the start, exact 1 on
  the first frame at or after the duration; it pauses and resumes with the visualizer.
- **CMP-014-R2**: A transition bus holds the outgoing and the incoming scene output and draws the
  shown frame: the outgoing scene alone before progress leaves 0, the blend while 0 < progress < 1,
  the incoming scene alone from progress 1.
- **CMP-014-R3**: Styles: cut, crossfade, dip to black. Crossfade weights are (1 − e, e); dip to
  black is the outgoing scene fading to black over the first half and the incoming scene fading in
  over the second half; e is the eased progress.
- **CMP-014-R4**: Exact ends: at progress 0 the output is byte-identical to the outgoing scene
  rendered alone, from progress 1 on to the incoming scene alone (given the same flash-guard
  history).
- **CMP-014-R5**: No leaks: the blend target comes from the texture pool; it and the outgoing
  scene's resources go back to the pool when the transition ends, is cancelled or is interrupted.
- **CMP-014-R6**: Interruption and cancel follow the Clarifications; at most two scene outputs are
  live at any time.
- **CMP-014-R7**: Flash safety: the bus runs the composite flash guard (FX-019) on the frame it
  shows, transition frames included; no transition frame reaches an output without it.
- **CMP-014-R8**: Render caching: a scene compositor's level-2 reuse stays correct for that scene,
  and the bus blends every frame of a transition again (never reuses a blended frame).
- **CMP-014-R9**: Every output fed from the bus (device, external display, recording) shows the
  same frame: the bus's output pass, repeated through `encodeOutput` like REC-003.
- **CMP-014-R10**: Reduce Motion: a scene transition is decorative, so with Reduce Motion on it
  resolves to a cut; blackout, Restore and the PERF-014 placeholder stay safety fades.
- **CMP-014-R11**: The compositor's existing single-scene output is unchanged (goldens unchanged).
- **CMP-014-R12**: The clock, easing and weights are plain Swift and build on Linux.

### Key Entities

- **Transition spec**: style, duration (seconds), easing. Validated (finite, 0…10 s).
- **Transition clock**: elapsed frame time, paused flag, progress.
- **Transition bus**: the live scene, the outgoing scene during a transition, the clock, the blend
  target, the flash guard.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-014-S1**: Progress 0 and progress ≥ 1 frames are byte-identical to the scene rendered alone.
- **CMP-014-S2**: The midpoint frame is within 0.002 of the reference blend in every channel.
- **CMP-014-S3**: The pool's checked-out count after a transition, a cancel and an interruption
  equals the count before (0 leaked textures).
- **CMP-014-S4**: The clock is exactly 1 on the first frame at or after the duration and does not
  advance across a pause.
- **CMP-014-S5**: Reduce Motion gives a cut (0 blended frames).
- **CMP-014-S6**: A fast dip-to-black between bright scenes with Reduce flashing is limited (gain < 1).
- **CMP-014-S7**: Every blended frame is drawn anew even when both scene compositors reuse their
  composites.
- **CMP-014-S8**: GPU time per transition frame is recorded on the Mac.

## Assumptions

- A scene output is one CMP-001 compositor with its stack (CMP-002). Two compositors may share one
  texture pool.
- The app's live output does not yet render visuals as one compositor stack; wiring the bus into the
  device slot is follow-up work recorded in the plan, not part of this row's acceptance.
- Persisting a transition with each cue is SCN-007's row (it depends on CMP-014); SHOW-004 adds the
  per-cue override.
