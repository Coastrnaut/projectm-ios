# Feature Specification: ACC-008 High Contrast Overlay

**Feature Branch**: `feature/acc-008` (spec directory `119-acc-008-high-contrast-overlay`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement ACC-008 (High contrast overlay) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Improve readability of control UI over
bright visuals." Acceptance, verbatim: "Control text meets chosen contrast target in snapshot fixtures."
P1, effort M, depends on UIX-001 (integrated). Verification: accessibility unit and UI tests, then the
device in the last stage (D1 over the brightest presets)."

Identifiers in this feature carry the roadmap ID: requirements `ACC-008-R1…`, success criteria
`ACC-008-S1…`, tasks `ACC-008-T01…`. Other features are cited by their own IDs: ACC-004 (accessibility
audit; the controls' dark backing, contract C3 of `specs/082-acc-004-voiceover-scene-browser`), ACC-003
(accessible accent, Increase Contrast palette, opaque bordered badges, grayscale snapshot method), ACC-006
(large text), ACC-011 (status captions), UIX-002 (scene switcher), FR-042 (source-and-state indicator),
FR-048 (performance overlay), FR-085 (paused state), REC-003 (recording indicator), CAM-012 (camera badge),
OSC-007 (listener badge), OUT-010 (blackout badge), SHOW-014 (emergency blackout), AUD-007 (route
explanation), AUD-015 (background notice), FILE-013 (permission notices), PERF-010 (recovery offer),
REC-001, REC-012 (capture notices and panels).

## Baseline: the audit (2026-11-14, commit `357adccc`)

Every piece of interface drawn over the visualization. "Backing" is what sits between the text and the
visual. "Worst case" is the lowest WCAG 2.x contrast of the element's weakest text over a pure-white visual
frame (dark appearance) or a pure-black frame (light appearance), **counting the blur material as
transparent**: a material's look depends on the system, the device and what is behind it, so it guarantees
nothing (see Clarifications). A busy high-contrast frame is never worse than the white or black frame,
because its brightest and darkest pixels are those colours.

| Element (feature) | Backing today | Text colours | Worst case today |
|---|---|---|---|
| Controls overlay (ACC-004, FR-082) | thick material + 45% black, always dark | white; secondary grey (times, tempo, cue); accent buttons; bordered buttons | about 3.4:1 (white), about 2:1 (secondary) |
| Source-and-state indicator (FR-042) | ultra-thin material, follows light/dark; opaque bordered with Increase Contrast | primary + status-colour symbol | about 1:1 (no backing without the material) |
| Camera, OSC, blackout and recording badges (CAM-012, OSC-007, OUT-010, REC-003) | regular material; opaque bordered with Increase Contrast | primary; accent "Stop"; red bordered "Stop"; prominent "Restore" | about 1:1 |
| Status caption (ACC-011) | regular material | primary | about 1:1 |
| Route explanation (AUD-007), show notice (SHOW-001) | regular material | primary | about 1:1 |
| Background notice (AUD-015), permission notices (FILE-013), photo, video, frame and recording notices, capture result panels (REC-012), recovery offer (PERF-010), status banner, native-visual and preset failure banners | regular material | primary; secondary; accent and bordered buttons; prominent "Reopen" | about 1:1 |
| Scene switcher card (UIX-002) | regular material over a 35% black dim | primary; secondary | about 1:1 (35% dim alone: about 1.9:1 for primary) |
| Emergency blackout button (SHOW-014) | regular material circle | primary symbol | about 1:1 |
| Performance overlay (FR-048) | 60% black | white monospaced | about 5.7:1 (passes) |
| "Paused" label (FR-085) | 50% black over the whole visual | white large title | about 4.0:1 (large text: passes 3:1) |
| External display note (OUT-001) | the black backdrop (no visual on the device) | white 80% | above 10:1 (passes) |

Findings: (1) only the performance overlay, the paused label and the external display note guarantee
contrast by themselves; (2) every other element relies on a blur material, so a white preset behind a
dark-appearance badge (or a black preset behind a light-appearance one) can wash out its text; (3) the
controls' 45% black (ACC-004) is not enough for white text on its own, and the secondary grey and the system
accent fall further below; (4) white text on the system-accent "prominent" buttons is about 3.7:1 even on an
opaque background; (5) no test measures the text of an overlay over a visual.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative option.

- Q: Which contrast target? → A: WCAG 2.x: at least 4.5:1 for normal text and 3:1 for large text (18 pt
  regular or 14 pt bold and larger) and for symbols and other graphical parts (WCAG 1.4.11). The app already
  uses WCAG 2.x ratios (ACC-003-R6, ACC-004); APCA is still a draft and has no iOS tooling. Applied to
  ACC-008-R1.
- Q: Does a blur material count toward the contrast? → A: No. The guarantee comes from a backing whose
  contrast can be computed and measured; the material stays for its look on top of that guarantee. Applied
  to ACC-008-R2, R6.
- Q: Which elements are "control UI"? → A: Every element of the audit table: anything with text or a symbol
  drawn over the visualization, shown with or without the controls. Sheets and Settings are not over the
  visual and are out of scope. Applied to ACC-008-R3.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read the controls over a bright preset (Priority: P1)

A performer runs a preset that fills the screen with white or saturated colour and taps to show the
controls. Every word, time, and button title stays readable, without changing any setting.

**Why this priority**: the controls are the app's main interface and the roadmap row's subject.

**Independent Test**: render the controls' backing and text styles over a white frame and measure the
contrast of the text glyphs against the backing behind them.

**Acceptance Scenarios**:

1. **Given** a pure-white visual, **When** the controls are shown, **Then** every text style in them measures
   at least 4.5:1 against its local background.
2. **Given** a dark preset, **When** the controls are shown, **Then** they look as before (a dark backing
   with white text), only darker.

---

### User Story 2 - Read badges, captions and notices over any visual (Priority: P1)

A badge ("Camera on", "OSC listening", "Output blacked out", "REC 0:05"), a status caption, the source
indicator or a notice appears while a bright or a black visual plays. Its text stays readable whatever the
system appearance.

**Why this priority**: these elements stay on screen without the controls and carry critical status.

**Independent Test**: the snapshot table renders each element over white, black, a saturated gradient and a
noisy pattern and asserts the target.

**Acceptance Scenarios**:

1. **Given** any audited element and any of the four fixture frames, **When** it is measured, **Then** its
   text meets 4.5:1 (normal) or 3:1 (large text and symbols).
2. **Given** Increase Contrast is on, **When** an element is shown, **Then** its backing is opaque.

---

### User Story 3 - Trust the measurement (Priority: P2)

A maintainer changes an overlay's colours. The snapshot table fails if the text drops below the target, and
a deliberately low-contrast label proves the check can fail.

**Independent Test**: the negative control fails the check; the old ACC-004 backing measures below target.

**Acceptance Scenarios**:

1. **Given** a grey label on the dark backing, **When** measured, **Then** it measures below 4.5:1 and the
   check reports a failure.

### Edge Cases

- A busy frame with white and black pixels behind one word: the worst local background decides.
- Accessibility text sizes (ACC-006): the controls scroll inside the same backing, so the guarantee holds.
- Increase Contrast: the backings become opaque; ACC-003's opaque bordered badges stay.
- Translucent secondary text: its colour depends on what is behind it, so it is measured composited.
- The "Paused" dim and the external display note: not changed (they pass).
- The visualization itself, sheets and Settings: not changed.

## Requirements *(mandatory)*

### Functional Requirements

- **ACC-008-R1**: The contrast target is WCAG 2.x: normal text at least 4.5:1, large text and symbols at
  least 3:1, measured between text pixels and the background directly behind them.
- **ACC-008-R2**: Every audited element that fails the target over a white or black frame gets a backing that
  meets the target by itself, with the blur material counted as transparent.
- **ACC-008-R3**: The audit covers every element of the baseline table; a new element drawn over the visual
  uses the same backing.
- **ACC-008-R4**: All overlay backings share one dark appearance (light text on a dark backing), as the
  controls already do (ACC-004), so one guarantee covers both system appearances.
- **ACC-008-R5**: Accent-coloured text and bordered or prominent buttons inside an overlay meet the target on
  its backing.
- **ACC-008-R6**: With Increase Contrast on, the overlay backings are opaque.
- **ACC-008-R7**: Elements that already pass (performance overlay, paused label, external display note) keep
  their look; the controls keep ACC-004's dark look apart from a darker backing.
- **ACC-008-R8**: Snapshot fixtures render each audited element's backing and text styles over four frames
  (white, black, a saturated gradient, a noisy high-frequency pattern) and assert ACC-008-R1 per text style.
- **ACC-008-R9**: A negative control (a deliberately low-contrast label) must fail the same check, and the
  previous backings' measurements are recorded.
- **ACC-008-R10**: The fix adds no work to the render path (no reading back of visual frames).
- **ACC-008-R11**: Accessibility identifiers, labels, announcements and layouts are unchanged.

### Key Entities

- **Overlay surface**: the shared backing (dark scrim plus material, opaque with Increase Contrast) and its
  tint.
- **Contrast fixture**: an element's backing and text styles rendered over a frame, with and without text.
- **Contrast measurement**: per text style, the low percentile of per-pixel contrast over glyph pixels.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ACC-008-S1**: Every text style of every audited element measures at least its target (4.5:1 or 3:1)
  over all four fixture frames.
- **ACC-008-S2**: The negative control measures below 4.5:1 and fails the check; the previous controls
  backing measures below 4.5:1 over white.
- **ACC-008-S3**: The fixture table runs in under 10 seconds.
- **ACC-008-S4**: On D1, over the brightest presets, every control and badge text is readable
  (`{device}`, last stage).

## Assumptions

- The visualization keeps its full brightness; the fix is in the overlay backings only.
- An adaptive mode that reads the visual's brightness is not required (see the plan's research).
- The device check (S4) is done by the owner in the last stage.
