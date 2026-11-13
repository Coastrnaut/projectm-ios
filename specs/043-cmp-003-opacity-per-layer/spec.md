# Feature Specification: CMP-003 Opacity per Layer

**Feature Branch**: `feature/cmp-003` (spec directory `043-cmp-003-opacity-per-layer`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement CMP-003 (Opacity per layer) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Set opacity 0 to 1 with
animated interpolation." Acceptance, verbatim: "Zero is transparent and one matches unmodified
layer output." Depends on CMP-002 (integrated: `LayerStack`, `Compositor.apply`, ADR-0013 and its
CMP-002 amendment). Implement only CMP-003; blend modes (CMP-004) and transforms (CMP-005) stay
refused."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-003-R1…`, success criteria `CMP-003-S1…`, tasks `CMP-003-T01…`. Requirements
of other features are cited by their own IDs: CMP-001-R9 (no per-frame allocation), CMP-001-R10
(composite flash guard), CMP-002-R7 to R11 (apply semantics), FX-019-R11 (new-scene reset).

## Baseline: what exists today (audit of 2026-11-13, commit `1eded3a`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Composite settings | Each stack entry (and each layer given to the compositor directly) carries an opacity in 0…1 (clamped on creation; a non-finite value reads 1). | The compositor refuses any opacity other than 1 (CMP-002-R11), so opacity cannot be used. |
| Compositor | Shown pictures are accumulated bottom to top with premultiplied "over" onto transparent; the flash guard limits the finished composite. | No per-layer scaling; no way to change a value gradually over time. |
| App | The Camera visual uses opacity 1 for both layers. | Nothing to change; a user-facing opacity control belongs to the layer inspector (CMP-015) and the modulation rows. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What does the compositor do with an opacity outside 0…1 or a non-finite one: clamp or refuse? → A: Two rules, by where the value comes from. A stored opacity (a stack entry's or a layer's composite settings) keeps CMP-001's rule: finite values are clamped to 0…1 when set, a non-finite value reads 1, so a stack can never hold an invalid opacity and `apply` never fails for opacity. A requested fade follows the parameter registry's convention (MOD-001: clamp on set, refuse non-finite): a finite target is clamped, a non-finite target or a negative or non-finite duration is refused with a typed error and changes nothing. Rejected: refusing out-of-range stored values at `apply` (an `apply` that fails for a slider overshoot is worse than a clamp, and CMP-001 already clamps).
- Q: At opacity 0, does the layer stop rendering, or only stop being composited? → A: Only its composite draw is skipped. The layer keeps rendering into its own picture each frame, so a fade-in shows current content at once, `.lastGoodFrame` fallbacks stay fresh and layers that integrate time see every frame. The saved work is the composite draw (one full-screen pass per layer). Rejected: pausing the layer's render (bigger saving, but a fade-in would first show a stale picture and time-integrating layers would see gaps); a later row (solo and mute, CMP-012) can add a real pause.
- Q: How does a caller ask for a fade, and where does the target live? → A: The stack entry's opacity is the target (the value the layer settles at). `Compositor.apply` takes an optional opacity transition (duration and curve; default immediate) used for every kept layer whose opacity changed in that apply; new layers appear at their opacity at once. The fade itself is a small value type (`LayerOpacityAnimator` with `setOpacity(_:duration:curve:)`) that the compositor keeps per layer and that callers and tests can use alone. Curves: linear and ease-in-out (smoothstep, 3t² − 2t³: exact ends, monotonic, zero slope at both ends). Rejected: a separate `setOpacity(of:)` on the compositor that bypasses the stack (the applied stack and the shown target would drift apart and the next `apply` would snap back).
- Q: Which clock drives a fade, and what happens after a stall? → A: The frame clock's frame durations (CMP-001-R3: the presentation-time difference clamped to 0…0.1 s), summed per layer. A fade therefore never jumps after a stall (the same rule every layer's animation follows) and is fully deterministic from the frame times; a fade of duration d ends exactly at the target on the first frame whose summed durations reach d. No wall clock is read. Rejected: absolute presentation time (a 2 s stall would complete a fade in one frame).
- Q: Is per-layer opacity registered as a modulation parameter (`layer.<id>.opacity`)? → A: No, not in this row. MOD-001 parameter IDs are catalog-stable dotted names whose segments start with a letter and are never reused, while layer instance IDs are per-stack runtime numbers; registering them would need dynamic registration that MOD-001 does not have. The MOD rows (modulation targets) and the UIX rows (layer inspector, CMP-015) expose opacity through the stack. This row exposes opacity to code only.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Opacity 0 hides a layer, 1 leaves it unchanged (Priority: P1)

A caller (later: a layer inspector, a scene, a modulation) sets a layer's opacity in its stack and
applies the stack. At 0 the layer contributes nothing to the output; at 1 the output is exactly
what it was before opacity existed; in between, the layer is mixed over what is below in
proportion.

**Why this priority**: It is the row's acceptance.

**Independent Test**: Composite a red layer over a blue one at 64 × 64 with the red layer's
opacity at 0, 1 and 0.5 and compare every pixel with the stack without the red layer, the CMP-002
output and the premultiplied mix.

**Acceptance Scenarios**:

1. **Given** a stack [blue, red] with red at opacity 0, **When** a frame is composited, **Then**
   every output pixel equals the output of the stack [blue] exactly.
2. **Given** that stack with red at opacity 1, **When** a frame is composited, **Then** every
   output pixel is bit-identical to the CMP-002 output of the same stack.
3. **Given** red at opacity 0.5, **When** a frame is composited, **Then** every pixel is the
   premultiplied mix (0.5, 0, 0.5, 1) within 1/255.

---

### User Story 2 - Opacity changes animate smoothly over time (Priority: P1)

A caller changes a layer's opacity with a duration and an easing curve. Over the following frames
the layer fades from its current opacity to the new one, driven only by the frames' presentation
times, and ends exactly at the new value. A new change during a fade starts from wherever the fade
is; a duration of zero changes at once.

**Why this priority**: "With animated interpolation" is the rest of the observable behavior.

**Independent Test**: Unit tests of the fade with a fixed sequence of frame times (no GPU, every
host including Linux), plus one GPU test that a fade shows the expected intermediate value.

**Acceptance Scenarios**:

1. **Given** a layer at opacity 0, **When** opacity 1 is set with a 1 s linear fade, **Then** the
   shown opacity is 0 at the first frame, rises monotonically and is exactly 1 from 1 s on.
2. **Given** a fade in progress at 0.4, **When** a new target is set, **Then** the next frame
   starts from 0.4 (no jump) towards the new target.
3. **Given** any opacity, **When** a new one is set with duration 0, **Then** the next frame shows
   the new value.
4. **Given** an ease-in-out fade, **When** it runs, **Then** it starts and ends exactly at the two
   values, rises monotonically, and moves more slowly near both ends than linear.

---

### User Story 3 - Opacity edits are cheap and safe (Priority: P1)

Changing opacity never re-creates or re-prepares a layer and frames at a steady size allocate
nothing new. A layer at opacity 0 keeps its prepared state and costs no composite work. Rapid
opacity changes cannot get past the flash safety limit.

**Why this priority**: An opacity change must not stutter, leak GPU memory or create a strobe.

**Independent Test**: Count preparations and picture creations across opacity-only applies and a
60-frame fade; a 30 Hz 0↔1 opacity strobe of a white layer over black is limited with Reduce
flashing on.

**Acceptance Scenarios**:

1. **Given** an applied stack, **When** a stack differing only in opacity is applied, **Then** no
   layer is created, prepared or released.
2. **Given** a fade running at a steady size, **When** 60 frames are composited, **Then** no
   picture is created.
3. **Given** a white layer over black whose opacity alternates 0 and 1 at 30 Hz, **When** 2 s are
   composited with Reduce flashing on, **Then** the output's transitions per second stay within
   the Reduce flashing limit.

### Edge Cases

- An opacity outside 0…1 is clamped to the range; a non-finite opacity in a stack entry reads 1
  (CMP-001's existing rule); a non-finite target or a negative or non-finite duration for a fade is
  refused with a typed reason and changes nothing.
- A layer whose frame failed shows its fallback (transparent or last good frame) at its current
  opacity.
- A layer that is unavailable (prepare failed) is skipped whatever its opacity.
- A new layer appears at its stack opacity immediately (no fade-in unless the caller adds it at 0
  and fades it in).
- A fade continues across stack edits that keep the layer; removing the layer ends it.
- A size change does not restart or jump a fade.
- A stall between frames advances a fade by at most 0.1 s (the frame clock's clamp), so a fade never
  completes in one frame because of a stall.
- Opacity is not a modulation parameter in this row (no `layer.<id>.opacity` ID; MOD and UIX rows).
- Frame times that repeat or go backwards (the frame clock clamps them) do not move a fade
  backwards.
- Blend modes other than normal and non-identity transforms are still refused (CMP-004, CMP-005).

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-003-R1**: The compositor MUST accept any layer opacity in 0…1 for stack entries and for
  layers given to it directly; values outside the range are clamped and a non-finite stored value
  reads 1 (CMP-001's rule for composite settings).
- **CMP-003-R2**: A layer at opacity `o` MUST be composited as its premultiplied picture with
  every channel (color and alpha) multiplied by `o`, then "over" what is below.
- **CMP-003-R3**: At opacity 1 the output MUST be bit-identical to the output without opacity
  support (CMP-002).
- **CMP-003-R4**: At opacity 0 the layer MUST contribute nothing: the output MUST equal that of
  the stack without the layer exactly, and the layer's composite draw MUST be skipped; the layer
  MUST stay prepared and keep rendering, so it reappears with current content.
- **CMP-003-R5**: A caller MUST be able to change a layer's opacity with a duration and a curve
  (linear and ease-in-out) when applying a stack; the stack entry's opacity is the target. The fade
  MUST be driven only by the frame clock's frame durations (CMP-001-R3, clamped to 0.1 s; no wall
  clock), start from the currently shown opacity at the first frame after the change, be monotonic
  between its ends, and reach the target exactly on the first frame whose summed frame durations
  reach the fade's duration. New layers appear at their opacity at once.
- **CMP-003-R6**: A change during a fade MUST start from the opacity shown last (continuity); a
  duration of 0 MUST take effect at the next frame.
- **CMP-003-R7**: A non-finite target or a negative or non-finite duration MUST be refused with a
  typed reason and change nothing; a finite target outside 0…1 is clamped.
- **CMP-003-R8**: Applying a stack that differs only in opacity MUST create, prepare and release
  nothing (CMP-002-R8 extended), and frames at a steady size MUST create no pictures during fades
  (CMP-001-R9).
- **CMP-003-R9**: Opacity MUST be applied before the composite flash guard, so every opacity
  change, however fast, is limited by it (CMP-001-R10); opacity changes MUST NOT reset its history.
- **CMP-003-R10**: The fade rules MUST build and be tested on Linux.
- **CMP-003-R11**: Blend modes other than normal and non-identity transforms MUST still be refused
  at apply (until CMP-004 and CMP-005).

### Key Entities

- **Layer opacity**: a number in 0…1 in each stack entry's composite settings; the value a layer
  settles at.
- **Opacity fade**: from the shown value to a target over a duration with a curve, timed by frame
  presentation times.
- **Opacity curve**: linear or ease-in-out.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-003-S1**: With opacity 0, 100% of output pixels equal the output without the layer exactly;
  with opacity 1, 100% are bit-identical to the CMP-002 output (the acceptance).
- **CMP-003-S2**: Opacity 0.5 of opaque red over opaque blue reads (0.5, 0, 0.5, 1) within 1/255 in
  every pixel.
- **CMP-003-S3**: 100% of fade cases (endpoints, monotonicity, retarget continuity, zero duration,
  refused inputs) pass on macOS and in the Linux shape.
- **CMP-003-S4**: 0 layer preparations for opacity-only edits and 0 pictures created over 60 fade
  frames at a steady size.
- **CMP-003-S5**: A 30 Hz 0↔1 opacity strobe stays within the Reduce flashing transition limit in
  every measured area of the output.
- **CMP-003-S6**: The composite cost of opacity is covered by the per-layer frame-cost measurement
  on D1-D3 already open as CMP-002-T15 (device stage); no separate device task.

## Assumptions

- A user-facing opacity control belongs to the layer inspector (CMP-015) and the editing UI rows;
  exposing opacity to modulation and OSC belongs to the MOD and UIX rows. This row exposes opacity
  to code only and changes nothing a user sees.
- Opacity is per layer, not per group (groups: CMP-011).
- The opacity multiply is negligible next to the existing composite draw; it is measured with the
  per-layer frame cost of CMP-002-T15.
