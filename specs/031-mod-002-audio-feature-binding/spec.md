# Feature Specification: MOD-002 Audio Feature Binding

**Feature Branch**: `feature/mod-002` (spec directory `031-mod-002-audio-feature-binding`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement MOD-002 (Audio feature binding) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Bind a normalized audio feature
to any compatible parameter." Acceptance, verbatim: "Band level drives test opacity and unbind
restores manual control." Dependencies: MOD-001 (integrated). Implementation hints: typed parameter
registry, DSP envelopes, deterministic clock; verification: unit graph tests + simulator."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MOD-002-R1…`, success criteria `MOD-002-S1…`, tasks `MOD-002-T01…`. Requirements
of other features are cited by their own IDs: MOD-001-R1 to R11 (parameter IDs, descriptors,
modulation policy, value store); ANL-002 (normalized bands), ANL-004 (onset detection value),
ANL-005 (beat confidence), ANL-016 (analysis frames); FX-001-R10 (the glow's luminance model),
FX-019 (the strobe safety envelope), FR-072 (Reduce flashing).

## Baseline: what exists today (audit of 2026-11-13, commit `304f3bc`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Parameters (MOD-001) | A validated catalog of 14 visual and glow parameters with stable IDs, ranges, units, defaults and a modulation policy (modulatable or not, allowed mix modes); a value store of manual values. | Nothing connects a parameter to an audio feature; the modulation policy is declared but nothing enforces it. |
| Audio features | Normalized band levels (0…1, ANL-002) reach the native spectra every frame; analysis frames (ANL-016) also carry the onset detection value (0…1) and the beat confidence (0…1). | Features drive only the bar heights; no parameter can follow them. |
| Glow (FX-001) | The glow intensity is a manual setting; the Reduce-flashing limiter (FX-019) bounds the composited frame using the glow's luminance model. | A modulated intensity would have to reach the luminance model too, or the limiter would underestimate. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option, recommended option
first.

- Q: Which audio features can be bound in this row? → A: Four normalized features already produced by analysis: one band's level (by band index, 0-based, below 128), the mean level of all bands, the onset detection value (ANL-004) and the beat confidence (ANL-005), each 0…1. A band index the current frame does not have reads 0 (silence), as does any feature missing from a frame. Tempo (BPM) is not a normalized feature and is not bindable here (MOD-009). Rejected: band ranges by fraction of the spectrum (more design than the acceptance needs; a later row can add a source kind without breaking these) (MOD-002-R1, R6).
- Q: What makes a parameter "compatible", and how are safety parameters protected? → A: A target must be registered, numeric (continuous or integer) and declared modulatable by its policy, and the binding's mix mode must be one the policy allows. Booleans, enums and colors are never targets in this row. Reduce flashing (FR-072) is not registered (MOD-001-R11), so it can never be a target; any unregistered ID is rejected. Rejections name the parameter and the reason (MOD-002-R2, R3).
- Q: How does the binding map the feature, and are smoothing and mix modes in scope? → A: A binding has an input range (the feature values mapped to 0 and 1, clamped), an output range, an optional attack/release envelope (rise and fall time constants in seconds, 0 = none, at most 60 s), and one mix mode allowed by the target: replace (output range within the parameter's range), add (offsets within ± the parameter's span) or multiply (factors within 0…1, so audio can only lower the manual value). The final value is always clamped to the parameter's range (integers rounded to the nearest valid step). Rejected: richer curves (MOD-004), multiple sources per parameter and their ordering (MOD-011): in this row a parameter has at most one binding, and binding it again replaces the earlier binding (MOD-002-R4, R5, R7).
- Q: How is "unbind restores manual control" guaranteed? → A: Modulation never writes the manual value: the effective value is computed each frame from the current manual value and the binding's signal. Unbinding removes the binding and its envelope state, so from the next read the effective value equals the manual value exactly, including manual changes made while bound. Rejected: writing modulated values into the store (unbind would then need to remember and restore, and a manual change during binding would be lost) (MOD-002-R8).
- Q: How much app wiring and UI is in scope? → A: No binding editor and nothing persisted (the modulation matrix UI is MOD-012, serialization MOD-013). The app evaluates bindings in the native spectra's frame loop with the frame's display time as the clock, applies a bound glow intensity to the glow and to the Reduce-flashing luminance model, and offers one Debug-only test path: a launch argument binds the lowest band to the glow intensity and shows a readable manual/effective readout with an Unbind control, for a simulator UI test. Release builds contain none of the test path. The app's settings keep their storage (the glow intensity setting stays the manual value); routing settings through the value store remains a follow-up for the first editor (MOD-012 or UIX-003), since this row needs only the one manual value the frame loop already holds (MOD-002-R9 to R12).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A band level drives a parameter, and unbinding hands it back (Priority: P1)

A later feature (the modulation matrix, a scene, a performer's preset) binds "bass band level" to a
parameter such as a layer's opacity or the glow intensity. While bound, the parameter follows the
band: loud bass, high value; silence, the low end of the mapping. When the binding is removed, the
parameter returns at once to the value the performer set by hand, including any change they made
while it was bound.

**Why this priority**: It is the roadmap's acceptance ("Band level drives test opacity and unbind
restores manual control").

**Independent Test**: Over a test catalog with an "opacity" parameter (range 0…1, manual value
0.25), bind band 0 with replace 0…1; feed band levels 0, 0.5, 1 on a fixed clock; the effective
opacity is 0, 0.5, 1. Unbind; the effective value is 0.25 and the manual value was never changed.

**Acceptance Scenarios**:

1. **Given** a test opacity bound to band 0 (replace, input 0…1 → output 0…1, no smoothing), **When** frames with band 0 at 0, 0.5 and 1 are evaluated, **Then** the effective opacity is 0, 0.5 and 1 and the manual value is unchanged.
2. **Given** that binding, **When** it is unbound, **Then** the effective value equals the manual value exactly, and a manual change made while bound is the value restored.
3. **Given** a binding with add (offsets −0.2…+0.2) or multiply (factors 0.5…1) mode, **When** band 0 goes from 0 to 1, **Then** the effective value moves from manual − 0.2 to manual + 0.2 (or from half the manual value to the manual value), clamped to the parameter's range.
4. **Given** an attack and release time, **When** band 0 steps from 0 to 1 and back on a fixed frame clock, **Then** the signal rises and falls with those time constants, identically on every run.

---

### User Story 2 - Incompatible bindings are refused with a reason (Priority: P1)

Whoever creates a binding (a later editor, a scene import) gets a readable refusal when the target
is unknown, not modulatable, not numeric, or a safety setting, when the mix mode is not allowed, or
when a range, band or envelope is invalid, so no audio feature can ever drive Reduce flashing or a
manual-only control.

**Why this priority**: "any compatible parameter" means compatibility is enforced; flash safety
must not depend on the editor being careful.

**Independent Test**: Try each invalid binding over a test catalog and the app's catalog; each is
refused with a message naming the parameter and the reason, and the existing bindings are unchanged.

**Acceptance Scenarios**:

1. **Given** the app's catalog, **When** a binding targets the bar count, orientation or glow on/off (manual only) or an unregistered ID such as a Reduce-flashing name, **Then** it is refused naming the parameter and the reason.
2. **Given** a modulatable target, **When** the binding's mix mode is not allowed by its policy, its input range is empty or not finite, its output range leaves the allowed bounds, its band index is out of range, or an envelope time is negative, not finite or above the limit, **Then** it is refused naming the defect.
3. **Given** every modulatable parameter of the app's catalog, **When** a band is bound with replace over the parameter's full range, **Then** the binding is accepted.

---

### User Story 3 - The glow follows the bass on screen, safely (Priority: P2)

On the simulator, a Debug test path binds the lowest band to the glow intensity of the native
spectrum while the reference track plays: the glow's effective intensity changes with the music, the
Reduce-flashing limiter sees the effective intensity, and an Unbind control returns the glow to the
intensity set in Settings.

**Why this priority**: The roadmap verifies this row on the simulator as well as in unit tests; it
proves the binding reaches a real render path without changing anything for users.

**Independent Test**: A UI test launches with the test binding, reads the readout until the
effective intensity takes at least two different values, taps Unbind, and reads "unbound" with the
effective intensity equal to the manual one.

**Acceptance Scenarios**:

1. **Given** the native spectrum with glow on and the test binding, **When** the reference track plays, **Then** the readout shows the effective glow intensity changing while the manual intensity stays at its setting.
2. **Given** the bound glow, **When** Unbind is tapped, **Then** the readout shows "unbound" and the effective intensity equals the manual intensity.
3. **Given** any build without the Debug launch argument, **When** the app runs, **Then** no binding exists and the glow behaves exactly as before this row.

### Edge Cases

- No audio or no analysis frame yet: features read 0; replace yields the output range's low end.
- A band index beyond the current frame's band count (fewer bars chosen): reads 0.
- Feature values outside the input range: clamped to the range ends before mapping.
- Inverted ranges: an output range whose first end is above its second inverts the mapping (louder → lower); an input range must have its minimum below its maximum.
- Clock: the first evaluation after binding has no elapsed time; time that goes backwards or repeats counts as zero elapsed time; an elapsed time above 0.25 s (a pause, a suspension) counts as 0.25 s so a resumed envelope cannot jump on stale state.
- Binding a parameter that is already bound replaces the earlier binding and restarts the envelope.
- Unbinding a parameter that is not bound: no effect, reported as not bound.
- Integer targets: the result rounds to the nearest valid step.
- The manual value changes while bound: the next evaluation uses the new manual value.
- Glow off while its intensity is bound: the glow stays off (on/off is manual only).

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-002-R1**: A binding source MUST be one of: one band's level by 0-based index (0…127), the mean of all bands' levels, the onset detection value, or the beat confidence; each normalized 0…1. A source MUST have a stable textual identifier (for later serialization, MOD-013) that round-trips.
- **MOD-002-R2**: A binding target MUST be a registered parameter (MOD-001) whose kind is continuous or integer and whose modulation policy is modulatable; the binding's mix mode MUST be one the policy allows.
- **MOD-002-R3**: Reduce flashing and every other unregistered setting MUST NOT be bindable. Every refused binding MUST name the target and the reason, and leave existing bindings unchanged.
- **MOD-002-R4**: A binding MUST carry an input range (finite, minimum below maximum; values outside are clamped), an output range, a mix mode, and an optional envelope (attack and release time constants in seconds, each finite, 0…60; 0 means no smoothing). Output range rules: replace, both ends within the target's range; add, both ends within ± the target's span; multiply, both ends within 0…1.
- **MOD-002-R5**: The signal MUST be the feature's position in the input range (0…1), smoothed by the envelope when present (rising with the attack constant, falling with the release constant). The mapped value MUST be exactly the output range's first end at signal 0 and its second end at signal 1. The effective value is the mapped value (replace), manual + mapped (add) or manual × mapped (multiply), then clamped to the target's range; integer targets round to the nearest valid step.
- **MOD-002-R6**: A feature missing from the current frame (no frame, a band index beyond the frame's band count) MUST read 0. Non-finite feature values MUST read 0.
- **MOD-002-R7**: A parameter MUST have at most one binding; binding it again MUST replace the earlier binding and reset its envelope. At most 32 bindings exist at once; another is refused.
- **MOD-002-R8**: Modulation MUST NOT change the manual value. Unbinding MUST make the effective value equal the current manual value exactly from the next read; unbinding an unbound parameter has no effect.
- **MOD-002-R9**: Evaluation MUST be deterministic: driven only by the frames and the timestamps the caller passes (no wall clock), so the same inputs give identical outputs on every run and platform. Elapsed time between evaluations MUST be treated as 0 when not positive and capped at 0.25 s.
- **MOD-002-R10**: Evaluating bindings each frame MUST NOT allocate memory or take locks after bindings are set up, and MUST run outside audio callbacks (Constitution VII). The binding model MUST be part of the dependency-free parameter module and build and test on every CI host, Linux included.
- **MOD-002-R11**: In the app, the native spectra's frame loop MUST evaluate bindings with the frame's display time as the clock and apply a bound glow intensity to the glow and to the glow's luminance model, so the Reduce-flashing limiter (FX-019) bounds the frame actually shown. With no binding the frame loop MUST behave exactly as before.
- **MOD-002-R12**: Debug builds MUST offer a test path, enabled only by a launch argument, that binds the lowest band to the glow intensity (replace over the full range) and shows the binding state, the manual and the effective glow intensity in a readable readout with an Unbind control. Release builds MUST contain none of it. No user-visible UI, setting or stored data is added (FR-065 unchanged).

### Key Entities

- **Audio feature source**: which normalized feature drives a binding (band level by index, mean level, onset value, beat confidence) and its stable identifier.
- **Audio feature frame**: one analysis frame's normalized features (band levels, onset value, beat confidence), any of them possibly absent.
- **Binding**: source, target parameter ID, input range, output range, mix mode, optional attack/release envelope.
- **Modulator**: the set of bindings (at most one per parameter) with their envelope state; evaluates a frame at a time and resolves a parameter's effective value from its manual value.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-002-S1**: With a band level bound to a test opacity, the effective opacity equals the mapped band level for every fixture frame, and after unbinding it equals the manual value exactly, in 100 % of runs.
- **MOD-002-S2**: Each refusal reason in MOD-002-R2 to R4 and R7 has at least one representative fixture, and each is refused with a message naming the parameter and the reason; Reduce flashing and every manual-only parameter of the app's catalog are refused.
- **MOD-002-S3**: Signal endpoints are exact (input range ends map to output range ends), every mix mode result stays inside the target's range, and an envelope step response matches its time constant within 1 % at one time constant, identically on repeated runs.
- **MOD-002-S4**: On the simulator, the bound glow intensity takes at least two different values while the reference track plays and returns to the manual intensity on Unbind; the UI test takes under 30 s.
- **MOD-002-S5**: Existing behavior is unchanged without a binding: the app's existing glow and native-visual tests pass unchanged; unit tests take about 1-2 s or less each and the package suite under 1 minute (owner rule 7).

## Assumptions

- The binding model lives in the MOD-001 parameter module; the app's catalog is unchanged (no new parameter is registered: the acceptance's "test opacity" is a test-catalog parameter in unit tests, and the glow intensity plays that role in the app).
- In the app, the native spectra's frame loop has band levels only; onset and beat sources read 0 there until a later row feeds analysis frames to the modulator (they are covered by unit tests).
- Smoothing beyond a one-pole attack/release envelope, tolerance tests on time constants for users (MOD-005), curves (MOD-004), multiple sources per parameter (MOD-011), the matrix UI (MOD-012), persistence (MOD-013) and graph cycles (MOD-014) are later rows; nothing here blocks them.
- Simulator results are never device evidence (Constitution X); no device step exists in this row.
