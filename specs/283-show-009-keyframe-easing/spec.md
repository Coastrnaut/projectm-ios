# Feature Specification: SHOW-009 Keyframe Easing

**Feature Branch**: `feature/show-009` (spec directory `283-show-009-keyframe-easing`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-15 (SHOW-009-T01-T12 verified on the Mac, simulator "SHOW9 iPhone 17", iOS 27.2;
T13 `{device}` open; no device claim). ShowControl 170 tests (1.4 s; 6 new); app `ShowKeyframeEasingAcceptanceTests` 2
(the roadmap acceptance through the live path); `ShowKeyframeEasingUITests` 1 (22.5 s).

**Input**: Roadmap row SHOW-009 (P2, size M, depends on SHOW-008, integrated). Observable behavior, verbatim: "Support
linear, stepped, cubic and hold interpolation." Acceptance, verbatim: "Reference midpoints match expected interpolation
values."

Identifiers carry the roadmap ID: requirements `SHOW-009-R1…`, success criteria `SHOW-009-S1…`, tasks `SHOW-009-T01…`,
research decisions `SHOW-009-D1…`. Other features are cited by their own IDs: SHOW-007 (show timeline), SHOW-008
(keyframe tracks), SCN-015 (scene lock), ACC-005 (accessible controls).

## Baseline (audit of 2026-11-14, commit `268f5beb`)

| Area | What exists | Gap for this row |
|---|---|---|
| Keyframe tracks (SHOW-008) | A track holds keyframes on whole milliseconds; each keyframe carries the interpolation to the next one: Hold (the value stays until the next keyframe), Linear, Ease (smoothstep). Evaluation is a pure function of the time, exact at keys, segment-relative between keys; colours mix in linear light. | No cubic curve through several keys, and only one kind of "jump" (SHOW-008's Hold is the classic stepped curve). |
| Storage (SHOW-008) | Each keyframe stores `interpolation` (`hold`, `linear`, `ease`); a missing or unknown value drops the keyframe with a counted warning. | No room for new curves that an older build can still read; a missing field is not treated as Linear. |
| Editor (SHOW-008) | Per keyframe, a three-way picker (Hold, Linear, Ease). | No Stepped, Cubic or distinct Hold. |
| Easing helpers | Smoothstep in SHOW-008 (`ShowKeyframeInterpolation.ease`), SCN-007 transitions and MED-007 Ken Burns (Compositor); MOD-016 smootherstep (ParameterGraph `RandomWalk`). | No monotone cubic anywhere. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: Which keyframe carries the mode? → A: The earlier (left) keyframe, as in SHOW-008: its mode shapes the segment to the next keyframe. The one exception is Hold (below), which by definition also shapes the segment arriving at it.
- Q: How do Stepped and Hold differ? → A: **Stepped** (SHOW-008's former "Hold", same behavior): the value stays at this keyframe's value until the next keyframe, where it jumps. **Hold** makes this keyframe a cut: the value does not move towards it (the segment arriving at it stays at the previous keyframe's value, whatever that keyframe's mode) and it stays at its own value until the next keyframe. With two keys (0 s, 0.0) and (1 s, 1.0), both give 0.0 at 0.5 s; with (0 s, 0.0, Linear), (1 s, 1.0, Hold), (2 s, 0.0), Hold gives 0.0 at 0.5 s where Stepped on the second key gives 0.5.
- Q: Which cubic? → A: A monotone cubic (piecewise cubic Hermite with Fritsch–Butland tangents, the PCHIP rule). Through a run of consecutive Cubic keyframes the curve passes smoothly through each inner key; it never leaves the range of the two keys of a segment (no overshoot), and it is flat at a local peak or valley and at the ends of a run. With only two keys it is the symmetric ease-in-out 3u² − 2u³ (exactly 0.5 at the middle; 0.15625 and 0.84375 at a quarter and three quarters).
- Q: What happens to Ease? → A: SHOW-008's Ease (smoothstep at every key) stays, so existing shows keep their look. Cubic differs from Ease only when a run has more than two keys: Cubic flows through inner keys, Ease stops at each.
- Q: Colours and Cubic? → A: Colour tracks use the two-key cubic shape (ease-in-out) per segment, mixed in linear light as in SHOW-008; the multi-key flow applies to numbers only.
- Q: How are the new modes stored? → A: `interpolation` keeps the names SHOW-008 builds know (`linear`, `hold` for Stepped, `ease`); a missing `interpolation` now means Linear. A new optional `easing` field is written only for Hold (`"hold"`) and Cubic (`"cubic"`), next to the nearest older curve (`hold` and `ease`), so a SHOW-008 build reads a show with the new curves as Stepped and Ease instead of dropping the keyframes. An unknown `easing` falls back to `interpolation`. No version bump; shows without the new modes keep their bytes.
- Q: Key times? → A: Unchanged from SHOW-008: at a keyframe's time every mode returns the stored value bit for bit.

### Session 2026-11-14 (speckit-clarify)

Three questions, each answered with the recommended option (owner rules 4 and 9).

- Q: Which mode does Add Keyframe at Playhead give a keyframe? → A: A new keyframe gets Linear (as in SHOW-008); when it replaces a keyframe at the same time, that keyframe keeps its mode (only the value changes), so re-recording a value never silently undoes a chosen curve.
- Q: How does the editor present five modes? → A: The SHOW-008 segmented picker with five short names (Linear, Stepped, Hold, Ease, Cubic), each a VoiceOver button by name, plus a one-line description of the chosen mode under it, so the difference between Stepped and Hold is visible where it is chosen.
- Q: Does an unknown `easing` value raise a load warning? → A: No. It is a forward-compatible hint from a newer build; the keyframe loads with its `interpolation` curve and nothing is counted. An unknown `interpolation` with no known `easing` still drops the keyframe with SHOW-008's counted warning.

### Session 2026-11-14 (speckit-analyze)

- Coverage: R1 → T02, T05; R2 → T02, T05; R3 → T05; R4 → T03, T06; R5 → T04, T05; R6 → T08, T09, T10; R7 → T07; R8 → T11, T12. S1 → T05; S2 → T05; S3 → T06; S4 → T05; S5 → T07, T10. No constitution conflict, no critical or high finding.
- Fix applied (medium): the edge cases "Cubic key followed by a Hold key" and "peak key" had no test; T06 now covers both.
- Noted (low): SHOW-008's documents call the old curve "Hold"; this spec's Clarifications record that it is now named Stepped with the same behavior and the same stored name, so SHOW-008's documents stay correct about stored bytes.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose how a value moves between keyframes (Priority: P1) — MVP

A VJ has a Glow Intensity track 0.0 at 0:00 and 1.0 at 0:01. They try each curve: Linear rises evenly (0.5 at 0:00.5),
Stepped stays at 0.0 and jumps at 0:01, Hold stays at 0.0 and jumps at 0:01, Cubic eases in and out (0.5 at the middle,
slow near the keys).

**Independent Test**: evaluate the two-key track at 0.25 s, 0.5 s and 0.75 s for every mode against the reference
values.

**Acceptance Scenarios**:

1. **Given** keys (0 s, 0.0) and (1 s, 1.0), **When** evaluated at 0.5 s, **Then** Linear gives 0.5, Stepped 0.0, Hold 0.0, Cubic 0.5, Ease 0.5.
2. **Given** the same keys with Cubic, **When** evaluated at 0.25 s and 0.75 s, **Then** the values are 0.15625 and 0.84375 within 1e-9.
3. **Given** any mode, **When** evaluated at a keyframe's time, **Then** the stored value is returned exactly.

### User Story 2 - Smooth multi-key motion without overshoot (Priority: P1)

The VJ sets four keys to Cubic (0.2, 0.9, 0.85, 0.1). The glow flows through the inner keys without stopping and never
rises above 0.9 or dips below the lower key of any segment.

**Acceptance Scenarios**:

1. **Given** a multi-key Cubic track, **When** sampled densely, **Then** every value lies within the range of its segment's two keys.
2. **Given** an inner key between a rise and a further rise, **When** evaluated just before and after it, **Then** the curve continues without a flat stop (its slope at the key is not zero).
3. **Given** a show playing with an injected clock, **When** it crosses a Cubic segment, **Then** the applied values are the eased values.

### User Story 3 - Pick the curve in the editor (Priority: P2)

In Settings → Show → Keyframe Tracks → a keyframe, the VJ picks Linear, Stepped, Hold, Ease or Cubic; the keyframe row
reads the chosen curve ("0:30, 0.90, Cubic"), and VoiceOver reads each choice by name.

**Acceptance Scenarios**:

1. **Given** a keyframe, **When** Cubic is chosen, **Then** the row reads "…, Cubic" and the show file stores it.
2. **Given** the scene is locked (SCN-015), **When** the editor opens, **Then** the picker is disabled.

### Edge Cases

- A Hold keyframe first on the track: nothing arrives at it; it holds until the next key.
- Two Hold keyframes in a row: the value is flat everywhere and jumps at each.
- A Cubic key followed by a Hold key: the segment is held (Hold wins on its arriving segment); the cubic run ends there.
- A Cubic key whose neighbours form a peak or valley: the slope at that key is zero, so the curve does not overshoot it.
- The last keyframe's mode has no segment to shape (it only matters if a later key is added).
- A file with an unknown `easing` falls back to its `interpolation`; a missing `interpolation` means Linear; an unknown `interpolation` without a known `easing` drops the keyframe with a counted warning (SHOW-008 rule).

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-009-R1**: Each keyframe MUST carry one of Linear, Stepped, Hold, Ease and Cubic, shaping the segment to the next keyframe; Hold MUST also hold the segment arriving at it.
- **SHOW-009-R2**: At every keyframe time, every mode MUST return the stored value exactly; before the first and after the last keyframe the nearest value MUST hold (SHOW-008).
- **SHOW-009-R3**: Two-key reference values MUST hold: at the middle Linear 0.5, Stepped 0.0, Hold 0.0, Ease 0.5, Cubic 0.5; Cubic at a quarter and three quarters 0.15625 and 0.84375 (within 1e-9).
- **SHOW-009-R4**: Cubic MUST be monotone within each segment (never outside the segment's two key values) and smooth through inner keys of a Cubic run whose neighbouring segments rise or fall the same way.
- **SHOW-009-R5**: Storage MUST stay readable by SHOW-008 builds (nearest older curve), MUST read a missing interpolation as Linear, MUST round-trip every mode, and MUST keep the bytes of shows that use no new mode.
- **SHOW-009-R6**: The keyframe editor MUST offer the five modes with VoiceOver names and a description of the chosen mode, show the chosen mode in the keyframe row, and refuse changes while the scene is locked. Add Keyframe at Playhead MUST give a new keyframe Linear and MUST keep the mode of a keyframe it replaces.
- **SHOW-009-R7**: A playing show MUST apply the eased values (same live path as SHOW-008); evaluation stays a pure function of the time.
- **SHOW-009-R8**: No network access, no new UserDefaults key, no wall-clock assertions in tests; ShowControl MUST keep building on Linux.

### Key Entities

- **Interpolation mode**: Linear, Stepped, Hold, Ease, Cubic; stored as an older-compatible name plus an optional new name.
- **Keyframe** (SHOW-008): time, value, mode.

## Success Criteria *(mandatory)*

- **SHOW-009-S1**: The two-key reference midpoints (and Cubic quarter points) match the expected values for all five modes.
- **SHOW-009-S2**: 100% of keyframe times return the stored value bit for bit in every mode.
- **SHOW-009-S3**: A dense sample of a multi-key Cubic track never leaves any segment's key range.
- **SHOW-009-S4**: A show using every mode survives save and load unchanged; a SHOW-008-era show (no `easing`, or no `interpolation`) loads with the expected modes.
- **SHOW-009-S5**: A playing show applies the Cubic value at a segment's middle; a UI test (under 30 s) picks Cubic and sees it in the row.

## Assumptions

- Simulator results prove behavior only; a `{device}` task checks a Cubic glow ramp and a Hold cut during a running show on D1.
- Bézier handles, per-key tangent editing, overshooting curves (back, elastic) and drawing curves on a graph are out of scope.
