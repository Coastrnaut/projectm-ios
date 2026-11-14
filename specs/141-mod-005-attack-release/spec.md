# Feature Specification: MOD-005 Attack/Release Envelope

**Feature Branch**: `feature/mod-005` (spec directory `141-mod-005-attack-release`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MOD-005 (Attack/release envelope) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Smooth mappings with separate rise and fall rates." Acceptance, verbatim:
"Step input follows selected time constants within tolerance." Priority P1, effort M, depends on MOD-002
(integrated). Verification: unit graph tests + simulator."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MOD-005-R1…`, success criteria `MOD-005-S1…`, research decisions `MOD-005-D1…`,
tasks `MOD-005-T01…`. Other features are cited by their own IDs: MOD-002 (audio feature bindings),
MOD-003 (linear mapping), MOD-004 (curve mapping), MOD-013 and SCN-012 (binding restore and scene
validation), QA-004 (migration matrix meta-test), MIDI-003 and MIDI-004 (MIDI learn and CC scaling),
ANL-003 (spectral smoothing, a separate smoother for the spectrum visuals).

## Baseline: what exists today (audit of 2026-11-14, commit `08c5551a`)

The row's gap status is "Gap candidate". The audit finds that MOD-002 already built most of it; the
gap is definition, robustness, live editing, scene reporting and the step-response proof.

| Question | Today (MOD-002) |
|---|---|
| Where | `AudioFeatureModulator.advance` (`Packages/ParameterGraph`) smooths each binding's 0…1 position (MOD-003 `position(of:)`) into the binding's signal; MOD-004's curve and MOD-003's interpolation apply to the smoothed signal afterwards. |
| Shape | One-pole exponential: `signal += (target − signal) · (1 − exp(−Δt/τ))`. Not linear. |
| Times | `AudioFeatureEnvelope(attackSeconds:releaseSeconds:)`, time constants τ in seconds, separate for rise (target above the signal) and fall (otherwise). 0 means instant. Valid: finite, 0…60 s; otherwise `bind` refuses with `invalidEnvelope`. |
| Frame-rate independence | Yes: Δt comes from the `timeNanoseconds` passed to `advance` (the app passes the frame's display time). Δt is 0 on a binding's first advance and when time does not increase; one step is capped at 0.25 s (a pause or suspension). |
| Per binding | Yes, a field of `AudioFeatureBinding`. Changing it means rebinding, which restarts the signal at 0. |
| Scenes | Persisted since SCN-001/MOD-013 as an optional `envelope: {attack, release}` object per binding; missing fields read 0. Invalid times reject that binding at restore (MOD-013 "rejected", SCN-012 `invalidBinding` at the binding's path, not the envelope's). |
| Tests | One test checks one attack and one release constant at 60 fps within 1 % relative, plus determinism and the clock rules. No jitter, no other frame rates, no 63.2 % crossing time, no NaN or boundedness checks, no scene round trip of specific times. |
| UI | None for users: bindings are made in code and restored from scenes (same as MOD-004). |
| MIDI | MIDI-003 sets CC values directly, unsmoothed; MIDI-004 (CC scaling) is being integrated in parallel. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option, recommended option first.

- Q: Are the stored times one-pole time constants (63.2 % at τ) or 10–90 % rise times? → A: Time constants τ, MOD-002's existing meaning, so every stored scene keeps its exact behaviour; the 10–90 % rise time (τ·ln 9 ≈ 2.197 τ) is documented and offered as a conversion helper, not stored. Rejected: storing 10–90 % times (every existing scene would need a migration and would still be ambiguous for τ = 0) (MOD-005-R2).
- Q: Should the allowed range shrink to 0…5 s, as the brief suggested as an example? → A: No, keep MOD-002's 0…60 s. Shrinking would reject bindings in scenes saved since MOD-002 (a behaviour change with no safety benefit: slow smoothing cannot flash). A future editor may offer a smaller slider range inside the valid one (MOD-005-R5).
- Q: How is a long frame gap (backgrounding, a stall) handled? → A: Keep MOD-002's cap: one step counts at most 0.25 s, so the visual resumes smoothly instead of jumping. The analytic curve is guaranteed only for gaps up to 0.25 s; frame gaps in normal running (8–50 ms) are far below it (MOD-005-R4).
- Q: When a binding's times change while it is moving, does the signal restart? → A: No: a new `setEnvelope` operation replaces only the times and continues from the current signal on the next frame; rebinding (a new binding) still restarts at 0 as MOD-002 defines. Invalid times are refused with MOD-002's `invalidEnvelope` and change nothing (MOD-005-R8).
- Q: How is a scene's invalid envelope reported? → A: With SCN-012's existing `invalidBinding` code, but at the envelope's path (`$.bindings[i].envelope`) instead of the binding's, and the binding kept for re-save (MOD-013 "rejected"). No new issue code: the fault class is unchanged, only its location is more precise (MOD-005-R10).
- Q: What happens to a non-finite or out-of-range previous signal (which valid inputs never produce)? → A: The step treats it as already at the target (snaps), and every result is clamped to 0…1. A non-finite source already reads position 0 (MOD-003). So no input can make the signal NaN or leave 0…1 (MOD-005-R6).
- Q: Is MIDI CC value smoothing (MIDI-003/MIDI-004) in scope? → A: No. MIDI values are set directly today, MIDI-004 is being integrated in parallel, and adding smoothing there would change MIDI-003's contract. MIDI files stay untouched; the pure step function (MOD-005-R11) is ready for a later row to reuse.
- Q: Is a user-facing attack/release control added? → A: No: there is no binding editor to host it (MOD-004 decided the same). The model, live change, scene persistence and validation are complete; the row's simulator verification is the app unit test host on the simulator (MOD-005-S4).
- Q: Does this row change how existing scenes and bindings behave? → A: No. For valid inputs the step formula is unchanged and bit-identical; the clamp and the non-finite guard only affect values valid inputs never produce. The only visible change is the more precise issue path (MOD-005-R9, R10).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A step in the source follows the chosen rise and fall times (Priority: P1)

Whoever configures a binding (a scene today; a binding editor later) picks how fast the bound
parameter rises when the source jumps up (attack) and how fast it falls when the source drops
(release). A bass hit can make the glow flare quickly and fade slowly, or the reverse. The response to
a sudden jump follows a documented curve, the same whether the display runs at 60 or 120 frames per
second or stutters.

**Why this priority**: This is the roadmap acceptance: "Step input follows selected time constants
within tolerance."

**Independent Test**: Feed a 0→1 step and then a 1→0 step at 60 fps, 120 fps and a seeded jittery frame
sequence with several attack and release settings; compare every frame with the analytic curve.

**Acceptance Scenarios**:

1. **Given** a binding with attack τa, **When** the source steps from 0 to 1, **Then** after t seconds
   the signal is 1 − exp(−t/τa) within 1 % absolute, and it first reaches 63.2 % within one frame of τa.
2. **Given** a binding with release τr, **When** the source steps from 1 to 0 after settling, **Then**
   the signal is exp(−t/τr) times its starting level within 1 % absolute, and crosses 36.8 % of it
   within one frame of τr.
3. **Given** the same binding, **When** the frame rate is 60 fps, 120 fps or jittery, **Then** the
   values at the same elapsed time agree within tolerance.
4. **Given** attack and release times that differ, **When** the source rises then falls, **Then** the
   rise uses only the attack time and the fall only the release time.

---

### User Story 2 - Smoothing is safe and predictable at the edges (Priority: P1)

Whatever arrives (an instant time of 0, repeated or backwards frame times, a missing or non-numeric
source value, a long pause), the smoothed value stays within 0…1, never becomes not-a-number, and two
runs with the same inputs give identical results.

**Why this priority**: A parameter driven by a broken value could flash or freeze the visual.

**Independent Test**: Unit tests with τ = 0, Δt = 0, backwards time, NaN and infinite sources, a long gap,
and two identical runs.

**Acceptance Scenarios**:

1. **Given** τ = 0, **When** the source steps, **Then** the signal equals the new position on that frame.
2. **Given** a frame time equal to or earlier than the previous one, **When** the binding advances,
   **Then** the signal does not move (except an instant time, which follows at once).
3. **Given** a non-finite source value, **When** the binding advances, **Then** the signal moves toward 0
   (MOD-003's rule) and stays finite and within 0…1.

---

### User Story 3 - Times can be changed live and are kept in scenes (Priority: P2)

Changing a binding's attack or release takes effect from the next frame without the parameter jumping
back to 0. A saved scene restores the same times and therefore the same motion; a scene with an invalid
time reports where the problem is.

**Why this priority**: Without it a future editor would make the visual jump on every adjustment, and
authors could not find a bad value in a scene.

**Independent Test**: Change the times mid-rise and check continuity; save and restore a scene and
compare step responses; restore a scene with an attack of −1 and check the report's path.

**Acceptance Scenarios**:

1. **Given** a binding halfway through a rise, **When** its times change, **Then** the signal continues
   from its current value with the new time constant.
2. **Given** a scene with envelope times, **When** it is saved and reopened, **Then** the times are equal
   and a step response is identical.
3. **Given** a scene whose envelope time is out of range, **When** it opens, **Then** that binding is not
   applied, is kept for re-save, and the report points at its envelope.

### Edge Cases

- τ = 0 for one direction and not the other.
- A frame gap longer than 0.25 s (backgrounding): one step counts as 0.25 s.
- Target equal to the current signal: no change.
- Times at the limit (60 s) and just over it, negative, NaN or infinite.
- A scene with an envelope object that has only one of the two times, or none.
- An integer target parameter: smoothing applies to the signal before rounding.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-005-R1**: Each binding MUST have separate attack (rise) and release (fall) times; attack applies
  when the target position is above the current signal, release otherwise.
- **MOD-005-R2**: The times MUST be one-pole time constants with a documented definition: after a step,
  the signal covers 1 − exp(−t/τ) of the distance (63.2 % at t = τ; the 10–90 % rise time is τ·ln 9 ≈
  2.197 τ).
- **MOD-005-R3**: Smoothing MUST depend only on the elapsed time from the injected clock, not on frame
  count: each advance applies α = 1 − exp(−Δt/τ) with Δt from the frame times.
- **MOD-005-R4**: Δt ≤ 0 MUST leave a smoothed signal unchanged; a single Δt above 0.25 s counts as
  0.25 s.
- **MOD-005-R5**: τ = 0 MUST mean instant; valid times are finite and within 0…60 s; anything else is
  refused when binding and when restoring a scene.
- **MOD-005-R6**: The signal MUST stay finite and within 0…1 for every input, including non-finite
  sources and a corrupted previous value.
- **MOD-005-R7**: Results MUST be deterministic: identical inputs give bit-identical outputs.
- **MOD-005-R8**: A binding's times MUST be changeable without restarting its signal; invalid times are
  refused and leave the binding unchanged.
- **MOD-005-R9**: Scenes MUST keep the times in the existing optional fields (no format version change);
  scenes stored before this feature MUST restore with identical behaviour.
- **MOD-005-R10**: A scene binding with invalid times MUST be reported with a path to its envelope and
  kept for re-save, not applied.
- **MOD-005-R11**: The smoothing step MUST be available as a pure function so other smoothers can reuse
  it and tests can check it without a parameter registry.

### Key Entities

- **Envelope**: attack and release time constants of one binding, in seconds.
- **Signal**: a binding's smoothed 0…1 value, carried from frame to frame.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-005-S1**: For every tested setting (at least three attack/release pairs) and frame pattern
  (60 fps, 120 fps, seeded jitter), every frame's value is within 0.01 of the analytic curve and the
  63.2 % crossing happens within one frame of τ.
- **MOD-005-S2**: No tested input (NaN, ±∞, τ = 0, Δt ≤ 0, long gaps) produces a value outside 0…1 or a
  non-number.
- **MOD-005-S3**: A scene round trip preserves the times exactly and produces a bit-identical step
  response.
- **MOD-005-S4**: In the app on the simulator, a binding with slow attack and fast release drives a
  parameter that rises slowly and falls quickly, matching the analytic values.
- **MOD-005-S5**: The ParameterGraph and SceneFormat suites keep passing on macOS and Linux, each under
  one minute.

## Assumptions

- There is no user-facing binding editor; times are set in code and scenes (as MOD-004 decided).
- MIDI CC values (MIDI-003, MIDI-004) are not smoothed by this row.
- ANL-003's spectrum smoother is separate and unchanged.
