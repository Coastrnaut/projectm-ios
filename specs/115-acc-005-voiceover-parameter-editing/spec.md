# Feature Specification: ACC-005 VoiceOver Parameter Editing

**Feature Branch**: `feature/acc-005` (spec directory `115-acc-005-voiceover-parameter-editing`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement ACC-005 (VoiceOver parameter editing) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Expose adjustable actions and numeric
values for sliders." Acceptance, verbatim: "Increment and decrement actions update actual parameter." P1,
effort M, depends on MOD-001 (integrated). Verification: accessibility unit and UI tests, then the device
in the last stage (a VoiceOver swipe up/down pass on D1)."

Identifiers in this feature carry the roadmap ID: requirements `ACC-005-R1…`, success criteria
`ACC-005-S1…`, tasks `ACC-005-T01…`. Other features are cited by their own IDs: FR-070 (accessibility),
MOD-001 (parameter registry), FX-001 (glow), MED-009 (text overlay), AUD-008 (input trim), AUD-011 (noise
gate), AUD-013 (visual delay), MED-003 (video loop), ACC-004 (announcer and audit), ACC-006 (large text),
SCN-010 (undo).

## Baseline: the audit (2026-11-14, commit `9688f80a`)

Every slider, stepper and continuous control in the app. "Real parameter" means the control writes the
stored setting or coordinator value that the renderer or analysis reads (not a copy local to the view).

| Control (feature) | Range | Value VoiceOver reads today | Swipe step today | Real parameter |
|---|---|---|---|---|
| Glow intensity (FX-001) | 0–100 % | "50%" (read "50 percent") | system default (no step given) | yes (`AppSettings`, saved, applied to the glow) |
| Glow radius (FX-001) | 0.5–6 % | "2.0%" | system default | yes |
| Glow threshold (FX-001) | 10–100 % | "70%" | system default | yes |
| Text size (MED-009) | 3–25 % of the height | "8%" | system default | yes (`TextOverlayCoordinator.spec`, saved) |
| Text outline (MED-009) | 0–15 % | "6%" | system default | yes |
| Input trim (AUD-008) | −12…+24 dB, 1 dB | "+6 dB" ("d B" letters) | the slider's 1 dB step | yes (`InputTrimSetting`, saved, analysis control) |
| Noise-gate threshold (AUD-011) | −80…−20 dBFS, 1 dB | "−50 dBFS" (letters) | 1 dB | yes (`NoiseGateSetting`) |
| Visual delay (AUD-013) | 0–250 ms, 5 ms | "180 ms" | 5 ms | yes (`LatencyOffsetSetting`, per source) |
| Video loop in / out (MED-003) | 0…duration, 0.1 s | "1.5 seconds" | 0.1 s | yes (`VideoCoordinator.setLoop`) |
| Scrubber (AUD-002, CaptureUI) | track time | "1:05 of 3:20" | own adjustable action, 10 s | yes (already adjustable; out of scope) |

Not continuous (out of scope, already VoiceOver-operable as one button per choice): the segmented
pickers for bars, oscilloscope line and window, orientation, spacing, smoothing attack and release,
camera crop, anchor and zoom, text alignment and position, the analysis channel, and the spectrum
palette toggle. The OSC port is a number field. The user preset editor and the show editor have no
sliders or steppers.

Findings: (1) every slider already writes the real parameter; (2) the five percent sliders have no
step, so VoiceOver uses the system's default step, which is not tied to the parameter; (3) dB and ms
values are spelled as abbreviations VoiceOver reads letter by letter; (4) nothing tells the user that a
swipe at an end did nothing; (5) no test proves that an accessibility increment or decrement reaches the
stored setting.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative option.

- Q: Which controls are in scope? → A: The ten continuous sliders of the audit table (glow ×3, text
  size and outline, input trim, gate threshold, visual delay, loop in and out). Segmented pickers are
  discrete; VoiceOver already selects each choice as a button and reads it, so they stay unchanged.
  The scrubber already has its own adjustable action. Applied to ACC-005-R1.
- Q: How are values spoken? → A: The number with its unit spelled out: "50 percent", "plus 6 decibels",
  "minus 50 decibels full scale", "180 milliseconds", "1.5 seconds". The visible readouts keep their
  short forms ("+6 dB", "180 ms"). Applied to ACC-005-R2, R3.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I change a setting with VoiceOver swipes (Priority: P1)

A VoiceOver user focuses the input trim in Settings, hears "Input trim, 0 decibels, adjustable", swipes
up twice and hears "plus 1 decibel", then "plus 2 decibels". The analysis now uses +2 dB, and the value
is still +2 dB after the app is relaunched.

**Why this priority**: the roadmap's acceptance ("increment and decrement actions update actual
parameter").

**Independent Test**: invoke the accessibility increment and decrement on each slider and read the
stored setting.

**Acceptance Scenarios**:

1. **Given** any in-scope slider, **When** VoiceOver's increment runs once, **Then** the stored setting
   rises by exactly one step of that control and the spoken value changes to match.
2. **Given** the same slider, **When** decrement runs once, **Then** the setting falls by exactly one step.
3. **Given** a value was changed by increment, **When** the app relaunches, **Then** the slider reads the
   changed value.

### User Story 2 - I hear values in words, with units (Priority: P1)

A VoiceOver user hears every slider's value as a number with its unit ("250 milliseconds", "minus 6
decibels", "40 percent", "1.5 seconds"), never a bare fraction like "0.43".

**Why this priority**: the roadmap's "numeric values for sliders"; FR-070.

**Independent Test**: format a representative value of each unit and read each slider's accessibility value.

**Acceptance Scenarios**:

1. **Given** the glow intensity is 0.5, **Then** VoiceOver reads "50 percent".
2. **Given** the trim is −6 dB, **Then** VoiceOver reads "minus 6 decibels".

### User Story 3 - I know when I reach an end (Priority: P2)

A VoiceOver user swipes up on the visual delay at 250 ms; the value cannot rise, and VoiceOver says
"Maximum, 250 milliseconds" once, not on every further swipe.

**Why this priority**: without it a swipe at an end is silent and looks broken.

**Independent Test**: increment a slider at its maximum several times in a burst and count the announcements.

**Acceptance Scenarios**:

1. **Given** a slider at its maximum, **When** increment runs, **Then** the value stays and "Maximum, <value>"
   is announced.
2. **Given** a slider at its minimum, **When** decrement runs, **Then** "Minimum, <value>" is announced.
3. **Given** ten increments at the maximum within one second, **Then** the end is announced at most once.

### Edge Cases

- A value between steps (dragged by touch, restored from an older version): increment moves to the next
  step above, decrement to the next step below, never more than one step.
- A disabled slider (the gate threshold while the gate is off) cannot be adjusted; VoiceOver says "dimmed".
- The loop sliders' range depends on the video's duration; their steps clamp at that duration and the
  loop rules of MED-003 (at least 0.25 s, in before out) still apply after a step.
- The visual delay edits the source picked in its picker; a step changes only that source's value.
- Undo (SCN-010): each swipe is one undo step, as a drag is.
- Large text (ACC-006): the visible rows are unchanged.
- VoiceOver off: nothing visible changes; touch dragging works as before.

## Requirements *(mandatory)*

### Functional Requirements

- **ACC-005-R1**: Every continuous slider in the audit table (except the scrubber) MUST expose an
  adjustable increment and decrement to VoiceOver.
- **ACC-005-R2**: Each such slider's accessibility value MUST be its number with the unit spelled out,
  from one formatter per unit: percent, decibels (signed), decibels full scale, milliseconds, seconds.
- **ACC-005-R3**: The visible readouts MUST keep their current short forms.
- **ACC-005-R4**: One increment or decrement MUST change the stored setting or coordinator value by
  exactly one step of that control, measured from the step grid that starts at the range's minimum; a
  value off the grid moves to the nearest grid value in the direction of the swipe.
- **ACC-005-R5**: Steps MUST follow each control's own granularity: the slider's snapping step where it
  has one (trim 1 dB, gate 1 dB, delay 5 ms, loop 0.1 s); otherwise a whole multiple of the parameter
  registry's step hint (MOD-001) chosen so the full range takes at most 25 swipes.
- **ACC-005-R6**: Ranges, step hints and units MUST come from the parameter registry where it describes
  the parameter (the glow), and from the owning setting's range otherwise; there is one table of
  accessible controls.
- **ACC-005-R7**: Values MUST be clamped to the range; a swipe at an end MUST leave the value unchanged and
  announce "Maximum, <value>" or "Minimum, <value>" through the app's announcer, rate-limited so a burst
  is announced at most once per second and an identical repeat within two seconds is dropped.
- **ACC-005-R8**: A step MUST be saved and applied exactly like a touch change (renderer, analysis,
  persistence), and form one undo step.
- **ACC-005-R9**: Existing accessibility labels and identifiers MUST NOT change.
- **ACC-005-R10**: The shared editing behaviour MUST be one reusable piece used by every in-scope slider.

### Key Entities

- **Accessible control spec**: a control's identifier, label, range, step and unit.
- **Spoken value**: the formatted value text for one unit.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ACC-005-S1**: For each of the ten sliders, one increment and one decrement change the stored value by
  exactly one step (table test, 10 of 10).
- **ACC-005-S2**: A user interface test that invokes the accessibility increment on a slider sees the
  spoken value change and the stored value persist across a relaunch.
- **ACC-005-S3**: No slider's spoken value is a bare number: every formatted value names its unit (unit
  tests per unit).
- **ACC-005-S4**: Ten end swipes within one second produce at most one announcement.
- **ACC-005-S5** `{device}`: on D1 with VoiceOver, swiping up and down on each slider changes the value
  by one step and reads it with its unit.

## Assumptions

- MOD-001's registry describes the glow parameters only among these controls; text, audio and loop
  ranges stay with their owning settings.
- XCTest's increment and decrement on an element invoke the same accessibility actions VoiceOver uses.
- The announcer (ACC-004) is reachable from Settings.
