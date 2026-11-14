# Feature Specification: MIDI-004 MIDI CC Scaling

**Feature Branch**: `feature/midi-004` (spec directory `140-midi-004-cc-scaling`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (MIDI-004-T01-T15 verified on the Mac with the scripted MIDI system; device task T16 `{device}` open)

**Input**: User description: "Implement MIDI-004 (MIDI CC scaling) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Map 7-bit control changes to parameter ranges with curve and inversion."
Acceptance, verbatim: "CC 0 and 127 map to endpoints and inverted mode swaps them." Priority P1, effort M,
depends on MIDI-003 (integrated). Verification: unit tests with fake MIDI; a physical controller in the last
stage."

Identifiers in this feature carry the roadmap ID so they never collide with other features: requirements
are `MIDI-004-R1…`, success criteria `MIDI-004-S1…`, research decisions `MIDI-004-D1…`, tasks
`MIDI-004-T01…`. Other features are cited by their own IDs: MIDI-003 (MIDI learn and the mapping list),
MOD-003 (linear mapping), MOD-004 (curves and their text form), ACC-012 (sensory safety clamp), ACC-004
(announcer), MIDI-005 (14-bit controls, later).

## Baseline: what exists today (audit of 2026-11-14, branch point `ebfe4cca`)

The row's gap status is "Gap candidate". The audit confirms a gap: every mapped control is linear and
none can be inverted.

| Area | Today |
|---|---|
| Bindings | MIDI-003 `MIDIControlBinding` (control key + parameter ID) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIControlBinding.swift`; `MIDIBindingList` keeps one binding per control and per parameter, at most 64. Stored under `settings.midi.mappings` as `cc:<ch>:<num>=<id>` lines; text after `;` is ignored on read and dropped on the next save. |
| Values | `MIDIBindingValues.value(normalized:for:)` maps `value / 127` linearly over the continuous parameter's full range (minimum + position × span). |
| Curves | MOD-004 `MappingCurve` (`Packages/ParameterGraph/Sources/ParameterGraph/MappingCurve.swift`): 0…1 → 0…1, exactly 0 at 0 and 1 at 1, bounded, monotonic; `textForm` / `init?(textForm:)` (`linear`, `easeIn:<p>`, `easeOut:<p>`, `easeInOut:<p>`, `log:<k>`, `exp:<k>`, `piecewise:x,y/…`), never containing `;` or `=`; `validationProblem` for out-of-range parameters. |
| Interpolation | MOD-003 `LinearMapping.interpolate(from:to:at:)`: exactly the start at 0 and the end at 1, bounded, monotonic. |
| UI | MIDI-003 `MIDIMappingsView`: status, one row per learnable parameter (the four glow parameters) with Learn and Delete, one-step Undo. No per-mapping options. |
| Test fakes | `ScriptedMIDIInputProvider` + `MIDIInputCoordinator.drain()` (unit tests); DEBUG `-uitestFakeMIDI` stand-in panel (UI tests). |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What options does a mapping get? → A: A curve (default Linear) and an Invert switch (default off), per mapping. Both follow the parameter: relearning a parameter with a new control keeps its curve and inversion; a control moved to another parameter takes that parameter's options (default if it had none).
- Q: Is a sub-range (a minimum and maximum inside the parameter's range) in scope? → A: No. The row's acceptance is about the parameter's endpoints, and a sub-range needs two more accessible sliders and a pickup policy. The stored form keeps unknown option keys, so a later row can add `min=`/`max=` without breaking this one. The parameter's full registered range is used.
- Q: Does inversion apply before or after the curve? → A: Before: position = value / 127, inverted = 1 − position, then the curve, then the range. Inverted mode is then exactly "the knob runs the other way": the inverted mapping at value v equals the normal mapping at 127 − v, so the curve keeps its shape relative to the parameter (a logarithmic curve still gives fine control near the parameter's minimum) and its preview is a mirror image. Rejected: after the curve (1 − curve(x)) would change where the fine resolution lands in the parameter's range when inverting.
- Q: How are options stored? → A: Appended to the MIDI-003 line: `cc:<ch>:<num>=<id>;curve=<MOD-004 text form>;invert=1`. Only non-default options are written, so a linear, non-inverted mapping keeps exactly the MIDI-003 line. Unknown `;` segments are kept verbatim in order and written back after the known ones.
- Q: What happens with curve text that cannot be used (unreadable, or out of MOD-004's valid ranges)? → A: The mapping uses Linear, keeps the original text so nothing is lost on save (a newer version may know it), and the MIDI Mappings screen says "Curve not readable; using Linear." on that mapping. Choosing a curve replaces the text.
- Q: Which curves can be chosen? → A: Four presets: Linear, Ease in (`easeIn:2`), Ease out (`easeOut:2`), Logarithmic (`log:9`). Any other stored curve (for example `exp:4` or a piecewise curve from a later editor) is shown as "Custom" and kept until another preset is chosen.
- Q: 14-bit controls? → A: Out of scope (MIDI-005). Only 7-bit control changes are scaled here.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Where does the user open a mapping's options? → A: From a second row, "Curve", shown under each mapped parameter in MIDI Mappings (value: the curve summary, for example "Ease in, inverted"); it opens the options screen. Rejected: a third button in the parameter row (too cramped with Learn and Delete at large text sizes) and making the parameter row itself a link (it would change the row's accessibility element that MIDI-003's tests and VoiceOver users rely on).
- Q: Are curve and Invert changes part of MIDI-003's one-step Undo? → A: No. They are changed in place on the options screen and can be reverted there with one tap; Undo stays for learn, move, replace and delete. Leaving MIDI Mappings for the options screen ends learn mode and clears Undo, as leaving the screen does in MIDI-003.
- Q: Does changing a curve or Invert move the parameter at once? → A: No. The new mapping applies from the control's next message; the parameter never jumps when nobody is touching the controller (consistent with MIDI-003's "live values only from messages").
- Q: What does the preview show, and how is it described to VoiceOver? → A: A small static plot of parameter value (up) against control position (right) for the chosen curve and inversion, drawn from 33 samples of the same mapping function used for values. Its accessibility label names the curve and direction in words, for example "Curve preview: Ease in, inverted. Turning the control up lowers the value from maximum to minimum." No animation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A mapped knob reaches both ends of the parameter, either way round (Priority: P1) — MVP

A performer has mapped a fader to Glow intensity. Pulled fully down (CC 0) the glow intensity is exactly
its minimum and pushed fully up (CC 127) exactly its maximum. Their controller's fader is mounted upside
down, so they switch the mapping to Inverted: now fully down gives the maximum and fully up the minimum.

**Why this priority**: It is the row's acceptance.

**Independent Test**: For several parameters with different ranges and every curve kind, CC 0 and 127
give exactly the range's minimum and maximum, and with inversion exactly the maximum and minimum.

**Acceptance Scenarios**:

1. **Given** CC 7 is mapped to a parameter with any curve, **When** CC 7 sends 0 and then 127, **Then** the parameter's live value is exactly its minimum and then exactly its maximum.
2. **Given** the same mapping set to Inverted, **When** CC 7 sends 0 and then 127, **Then** the live value is exactly the maximum and then exactly the minimum.
3. **Given** a fake MIDI source and the mapping set to Inverted in the app, **When** the source sends 0, **Then** the glow's live value is its maximum.

---

### User Story 2 - I shape how a knob responds (Priority: P1)

The performer wants finer control of low glow intensities, so they open the mapping, pick
"Logarithmic", and see a small preview of the curve. Midway through the knob's travel the glow follows
the curve, not a straight line.

**Why this priority**: The curve is the other half of the row's behaviour.

**Independent Test**: With a curve chosen, the value at a middle control position equals the curve's
value at that position interpolated over the range.

**Acceptance Scenarios**:

1. **Given** a mapping with Ease in, **When** the control sends 64, **Then** the value is minimum + (64/127)² × span.
2. **Given** an inverted mapping with Logarithmic, **When** the control sends 64, **Then** the value equals the non-inverted mapping's value at 63.
3. **Given** the mapping's options screen, **When** the user picks a curve or toggles Invert, **Then** the change is saved, VoiceOver announces it, and the preview updates.

---

### User Story 3 - Old and future mappings keep working (Priority: P2)

Mappings made before this row still load as linear and not inverted. A mapping list written by a newer
version, with options this version does not know, loads and is saved back without losing them.

**Why this priority**: The mapping list is stored and backed up; it must not lose data.

**Independent Test**: Read and write stored lines: old lines read as linear, not inverted; options
round-trip; unknown segments are kept; unreadable curve text reads as linear and is reported.

**Acceptance Scenarios**:

1. **Given** the stored line `cc:0:7=effect.bloom.intensity`, **When** it is read, **Then** the mapping is linear and not inverted, and writing it back gives the same line.
2. **Given** `cc:0:7=effect.bloom.intensity;curve=log:9.0;invert=1;min=0.2`, **When** it is read and written back, **Then** the line is unchanged.
3. **Given** `cc:0:7=effect.bloom.intensity;curve=wobble:3`, **When** it is read, **Then** the mapping acts as Linear, the screen reports the unreadable curve, and the text is kept on save until a curve is chosen.

### Edge Cases

- Curve text with valid syntax but out-of-range parameters (`easeIn:50`): treated as unreadable (Linear, reported, kept).
- `invert=` with any value other than `1`: not inverted (`invert` is a known key; it is written back only as `invert=1` when inverted).
- A repeated known key (`curve=` twice): the first is used; later ones are dropped on save.
- Empty `;` segments (`…=id;;invert=1`): skipped.
- A segment without `=`: kept verbatim as unknown.
- Options are changed while the control is still: the new mapping applies from the control's next message (the parameter does not jump without a hand on the knob).
- A mapping is deleted: its options go with it; Undo restores them.
- The sensory safety clamp (ACC-012) still caps the live value after scaling, as for any mapped value.

## Requirements *(mandatory)*

### Functional Requirements

- **MIDI-004-R1**: Each mapping MUST have a curve (MOD-004; default Linear) and an inverted flag (default off).
- **MIDI-004-R2**: A control value v (0–127) MUST map to the parameter value by: position = v / 127; if inverted, position = 1 − position; shaped = curve(position); value = MOD-003 interpolation from the parameter's minimum to its maximum at shaped. The result is always within the parameter's range.
- **MIDI-004-R3**: For every curve kind, value 0 MUST give exactly the minimum and 127 exactly the maximum; inverted, exactly the maximum and the minimum.
- **MIDI-004-R4**: The stored line MUST be `cc:<ch>:<num>=<id>` followed by `;curve=<text form>` when the curve is not linear (or unreadable text is kept) and `;invert=1` when inverted, then any unknown segments in their original order. A linear, non-inverted mapping MUST store exactly the MIDI-003 line.
- **MIDI-004-R5**: Reading MUST accept MIDI-003 lines (linear, not inverted), keep unknown segments verbatim, and treat curve text that does not parse or is not valid as Linear while keeping the text and flagging the mapping.
- **MIDI-004-R6**: Options MUST follow the parameter when a mapping is rebound (relearned with a new control, or a control moved onto it).
- **MIDI-004-R7**: The MIDI Mappings screen MUST show, for each mapped parameter, a row with the curve summary ("Linear", "Ease in, inverted", …) that opens an options screen with a curve picker (Linear, Ease in, Ease out, Logarithmic; "Custom" shown only for another stored curve), an Invert switch, a curve preview reflecting both, and the unreadable-curve notice when flagged.
- **MIDI-004-R8**: Changing a curve or Invert MUST save at once and be announced through the shared announcer (`.midi` lane); the preview MUST have an accessibility label that describes the shape in words; nothing animates.
- **MIDI-004-R9**: The model MUST build and pass its tests on Linux; the app MUST still pass compliance, status events, motion policy, permission catalog, network symbol and privacy manifest checks. No new stored key, permission or usage string.
- **MIDI-004-R10**: A DEBUG UI test MUST be able to seed a mapping by launch argument and toggle Invert in under 30 s.

### Key Entities

- **Mapping options**: curve (MOD-004), inverted (bool), unreadable curve text (optional, kept), unknown segments (ordered text, kept).
- **Binding**: MIDI-003's control key and parameter ID plus the options.

## Privacy review *(Constitution, Privacy)*

- The options add a curve and a flag per mapping; still no device, endpoint, name or time is stored.
- No permission, network ability or new stored key is added.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MIDI-004-S1**: For 3 parameters with different ranges and all 7 curve kinds, value 0 → minimum and 127 → maximum exactly; inverted, 0 → maximum and 127 → minimum exactly (the row's acceptance).
- **MIDI-004-S2**: Midpoint values (32, 64, 96) equal the curve's value interpolated over the range; inverted equals non-inverted at 127 − v.
- **MIDI-004-S3**: Stored lines round-trip; MIDI-003 lines read as linear, not inverted, and write back unchanged; unknown segments are kept; unreadable curve text reads as Linear and is flagged.
- **MIDI-004-S4**: With a fake MIDI source, an inverted mapping in the app gives the parameter's maximum at value 0 and its minimum at 127.
- **MIDI-004-S5**: A UI test seeds a mapping, opens its options, toggles Invert and sees the summary change, in under 30 s.
- **MIDI-004-S6**: All repository checks pass and the package tests pass on the host (and Linux in CI).

## Assumptions

- The learnable parameters stay MIDI-003's four glow parameters.
- A physical controller check is the `{device}` task in the last stage; simulator results are never device evidence.
