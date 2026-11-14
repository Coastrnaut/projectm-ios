# Feature Specification: ACC-003 Color-blind Friendly Controls

**Feature Branch**: `feature/acc-003` (spec directory `110-acc-003-color-blind-friendly-controls`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (ACC-003-T01-T16 verified on the Mac and an own iOS 27.2 simulator; T17 `{device}` open)

**Input**: User description: "Implement ACC-003 (Color-blind friendly controls) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Offer high-contrast palettes and
non-color status indicators." Acceptance, verbatim: "Critical statuses remain distinguishable in grayscale
snapshots." P1, effort M, depends on UIX-001 (integrated). Verification: accessibility unit and UI tests,
then the device in the last stage (D1 with Color Filters (grayscale) and Increase Contrast)."

Identifiers in this feature carry the roadmap ID: requirements `ACC-003-R1…`, success criteria
`ACC-003-S1…`, tasks `ACC-003-T01…`. Other features are cited by their own IDs: FR-042 (source-and-state
indicator), FR-070 (accessibility), REC-003 (recording indicator), CAM-012 (camera badge), OSC-007
(listener badge), OUT-010 (blackout badge), AUD-007 (route indicator), ANL-006 (tempo confidence),
FILE-013 (permission notices), SCN-012 (repair report), FILE-003 (import dry run), MIDI-001 (MIDI
endpoints), ACC-002 (flash warnings), ACC-004 (accessibility audit), ACC-001 (motion policy), ACC-006
(large text), ACC-011 (status events), VIS-001/002/003 (native spectra and their palettes).

## Baseline: the audit (2026-11-14, commit `b4f2abf9`)

Each critical status the app shows, and whether it is told apart by something other than colour.
"Grayscale" means: with iOS's grayscale colour filter, can the user still tell the states apart?

| Status (feature) | States that must be told apart | Colour used today | Non-colour cue today | Grayscale |
|---|---|---|---|---|
| Source-and-state indicator (FR-042) | active, silent, no audio, waiting, paused, interrupted, stopped, ended, switching | none on the indicator; the banner draws "Active audio" in green | words only ("In-App Playback · Active audio") | yes by words; no shape to glance at |
| Status banner state (FR-015) | same | green for Active | words | yes by words |
| Recording indicator (REC-003) | recording, finishing | red dot vs grey dot (same circle) | "REC 0:05" vs "Finishing…" | yes by words; the dot is colour-only |
| Camera badge (CAM-012) | starting, live | green camera symbol in both | none visible ("Camera on" in both; VoiceOver value only) | **no** |
| OSC listener badge (OSC-007) | listening vs absent | none | symbol and words | yes |
| Output blackout badge (OUT-010) | blacked out, restoring | none | words; same `eye.slash` symbol in both | yes by words; same shape |
| Route indicator (AUD-007) | each route | none | symbol per route and words | yes |
| Tempo confidence (ANL-006) | stable, uncertain, searching | secondary grey word | "≈" and state words | yes |
| Permission notices (FILE-013) | each permission | none | symbol and catalog text | yes |
| Repair report (SCN-012) | cannot open, repairs only, opens as is; group severities | none | status text and group headings | yes |
| Import plan (FILE-003) | new, conflict, no licence, refused, identical | none | section headings and row text | yes |
| MIDI endpoints (MIDI-001) | online, offline | none | "Offline" word | yes |
| Flash warnings (ACC-002) | may flash vs not | none | "May flash" with a triangle | yes |
| Favourite star | favourite vs not | yellow vs grey | filled vs outline star | yes |
| Settings errors (photo, video, OSC port) | error vs none | red text | the message itself | yes (the message appears or not) |

Contrast: ACC-004's audit filters the show editor's "Add Current Scene" because the system accent
(systemBlue, about 4.0:1 on white) "nearly passed" contrast; it left an app-wide accent to ACC-003.

Findings: (1) the camera badge's starting and live states differ only in VoiceOver's value; (2) the
recording dot and the blackout badge use one shape for two states; (3) the source states have words but
no shape; (4) the system accent misses 4.5:1 on white; (5) nothing reacts to Increase Contrast or
Differentiate Without Colour beyond what iOS does on its own; (6) Smart Invert would invert the
visualization (pictures, camera, photos and video).

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative option.

- Q: Does "high-contrast palettes" mean the app's interface colours, the visualization's colours, or
  both? → A: Both, with different weight. The interface palette (accent and status colours) is required
  and follows iOS's Increase Contrast. The visualization's colours are content, not status: nothing
  critical is shown by them, so the existing palettes stay unchanged, and one colour-blind-safe ramp is
  offered as an opt-in Settings choice for the native spectra (P3). Applied to ACC-003-R6 to R9, R13.
- Q: Are the non-colour cues always shown, or only with Differentiate Without Colour? → A: Always. iOS's
  grayscale and colour filters do not turn on Differentiate Without Colour, so cues that only appear
  with it would miss the roadmap's acceptance. Differentiate Without Colour adds words where a status
  would otherwise be told apart by shape alone (the camera badge's "Starting"/"Live"). Applied to
  ACC-003-R1, R4.
- Q: Which statuses are "critical"? → A: The audit's table: every status that tells the user what the
  app is doing with audio, the camera, the network, recording or the output, or whether something
  failed. Decorative selection states (a highlighted card) are out of scope. Applied to ACC-003-R1.

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: What counts as "distinguishable" in a grayscale snapshot? → A: Two states are distinguishable when,
  after converting both renderings to grayscale (relative luminance), at least 1% of the pixels differ
  by at least 20% of full brightness, in light and in dark appearance; in addition the two states'
  symbols must differ in shape (name), unless their words differ. A negative control (one symbol in two
  colours of equal luminance) must measure as not distinguishable, proving the measure ignores hue.
  Applied to ACC-003-S1, R15.
- Q: Which badges switch to an opaque, bordered background with Increase Contrast? → A: The app's own
  status badges over the visualization: the source-and-state indicator (when shown without the
  controls), the recording indicator, the camera badge, the OSC listener badge and the blackout badge.
  The controls overlay already has an opaque dark backing (ACC-004); system sheets and lists follow
  iOS. Applied to ACC-003-R9.
- Q: Which visuals does the colour-blind-safe palette change? → A: Every visual drawn by the native
  spectra: Circular, Linear, Oscilloscope, and the spectrum over Camera, Photo, Video and Text. projectM
  presets are third-party content and are never recoloured. Applied to ACC-003-R13.
- Q: Should the status banner keep drawing "Active audio" in green? → A: No. The words use the primary
  text colour (green text on a light material was about 2:1); colour moves to the new symbol, a graphic
  that only needs 3:1 and is backed by its shape. Applied to ACC-003-R2, R8.
- Q: Where does Differentiate Without Colour add words? → A: Only where states would otherwise differ by
  shape alone: the camera badge ("Starting" / "Live"). Every other critical status already has different
  words. Applied to ACC-003-R4.

### Session 2026-11-14 (implementation decision)

- Q: Does the colour-blind-safe palette also recolour the spectrum drawn over Camera, Photo, Video and
  Text? → A: Not in this feature (revises the clarify answer above). Those four visuals build their own
  circular spectrum in four separate hosts that CMP-011 is changing in parallel; the palette applies to
  the three native spectra (Circular, Linear, Oscilloscope), where the bars are the whole picture. The
  composites keep VIS-001's default; extending it is a follow-up (UIX-011's palette editing). Applied to
  ACC-003-R13.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I can tell every status apart without colour (Priority: P1)

A user with a colour vision deficiency (or with iOS's grayscale filter on) glances at the visualizer and
can tell whether audio is active, silent or missing, whether recording runs or is finishing, whether the
camera is starting or live, and whether the output is blacked out or restoring, from a shape and words,
never from colour alone.

**Why this priority**: the roadmap's acceptance ("critical statuses remain distinguishable in grayscale
snapshots").

**Independent Test**: render each status in each of its states, convert the pictures to grayscale, and
compare each pair of states that must be told apart.

**Acceptance Scenarios**:

1. **Given** In-App Playback is active, **When** the audio turns silent, **Then** the indicator's symbol
   changes shape as well as its words.
2. **Given** a recording runs, **When** the user stops it, **Then** the indicator's symbol changes from
   the record symbol to a different shape while "Finishing…" shows.
3. **Given** the camera is starting, **When** it starts delivering pictures, **Then** the badge's symbol
   changes shape; with Differentiate Without Colour on, the badge also says "Starting" or "Live".
4. **Given** the output is blacked out, **When** the user restores it, **Then** the badge's symbol
   changes shape while "Restoring output" shows.

### User Story 2 - The interface follows Increase Contrast (Priority: P1)

A user with low vision turns on Increase Contrast. Buttons and links in the app's accent colour and the
status colours become darker on light backgrounds and lighter on dark ones, and the status badges get a
solid background with a visible edge instead of a see-through material.

**Why this priority**: the roadmap's "high-contrast palettes"; ACC-004 left the accent's contrast open.

**Independent Test**: resolve every interface colour in light and dark, with standard and increased
contrast, and compute its contrast against the backgrounds it is drawn on.

**Acceptance Scenarios**:

1. **Given** standard contrast in light mode, **When** a list button uses the accent (the show editor's
   "Add Current Scene"), **Then** its text has at least 4.5:1 contrast and the accessibility audit
   reports nothing for it.
2. **Given** Increase Contrast, **When** any status badge is shown over the visualization, **Then** it
   has an opaque background and a visible border.

### User Story 3 - A colour-blind-safe spectrum (Priority: P3)

A user who finds the rainbow spectrum hard to read turns on "Color-blind-safe colors" for the native
spectra. The bars then use a blue-to-yellow ramp whose brightness rises with each bar.

**Why this priority**: optional comfort; the spectrum carries no status.

**Independent Test**: switch the setting and read the colours the spectrum uses.

**Acceptance Scenarios**:

1. **Given** a native spectrum, **When** the setting is on, **Then** its bars use the colour-blind-safe
   ramp, and each bar is brighter than the one before.
2. **Given** the setting is off (the default), **Then** the spectra look exactly as before.

### Edge Cases

- A status that is not shown at all (OSC off, no recording) is "absent", and absent versus shown is
  always distinguishable.
- Smart Invert is on: the visualization (projectM, native spectra, camera, photo, video) is not
  inverted; the controls are inverted by iOS as usual.
- Increase Contrast changes while the app is open: the colours follow at once (iOS redraws).
- Large text (ACC-006): the symbols scale with the text; nothing new is truncated.
- VoiceOver: symbols are decorative and hidden; what VoiceOver reads does not change.
- External display (OUT-001): status badges stay on the device; the external picture is unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **ACC-003-R1**: Every critical status in the audit MUST be told apart from its other states by a
  non-colour cue, always shown: a different symbol shape, different words, or both.
- **ACC-003-R2**: The source-and-state indicator and the status banner MUST show a symbol whose shape
  differs for each audio state (and for "Switching source…"), next to the unchanged words; the banner's
  state words use the primary text colour.
- **ACC-003-R3**: The recording indicator MUST use different symbols for recording and finishing; the
  blackout badge MUST use different symbols for blacked out and restoring.
- **ACC-003-R4**: The camera badge MUST use different symbols for starting and live; with Differentiate
  Without Colour on, it MUST also show "Starting" or "Live" next to its label.
- **ACC-003-R5**: Symbols added by this feature MUST be hidden from VoiceOver; labels, values,
  identifiers and contract texts of existing elements MUST NOT change.
- **ACC-003-R6**: The app's accent MUST have at least 4.5:1 contrast against white and the grouped
  background in light mode, and against black and the grouped background in dark mode.
- **ACC-003-R7**: With Increase Contrast, the accent and status colours MUST have at least 7:1 against
  the page background (white, black) and 6:1 against the grouped background.
- **ACC-003-R8**: Status colours (positive, caution, critical) MUST meet R6 and R7 the same way; colour
  stays supplementary to R1's cues.
- **ACC-003-R9**: With Increase Contrast, the visualizer's status badges (source-and-state indicator
  without the controls, recording, camera, OSC listener, blackout) MUST use an opaque background and a
  visible border instead of a translucent material.
- **ACC-003-R10**: The visualization MUST NOT be inverted by Smart Invert.
- **ACC-003-R11**: ACC-004's audit filter for "Add Current Scene" MUST be removed once R6 makes it pass,
  and ACC-004's contract updated.
- **ACC-003-R12**: In DEBUG builds, UI tests MUST be able to force Increase Contrast and Differentiate
  Without Colour by launch argument; Release builds never read them.
- **ACC-003-R13**: The native spectra (Circular, Linear, Oscilloscope; implementation decision above)
  MUST offer an opt-in colour-blind-safe palette whose relative luminance rises
  strictly from the first bar to the last, with the first bar at least 3:1 against black; off by
  default, stored on the device only, listed in the privacy review's allowed keys. projectM presets are
  never recoloured.
- **ACC-003-R14**: No new animation (ACC-001) and no new announcement (ACC-011).
- **ACC-003-R15**: An automated test MUST render every status group's states, convert them to grayscale
  and check each pair by the Clarifications' measure, with the negative control.

### Key Entities

- **Status cue**: for one state of one status: a symbol, its words and a supplementary colour role.
- **Status group**: one status with the states that must be told apart.
- **Interface palette**: the accent and status colours, each in light, dark, light with increased
  contrast and dark with increased contrast.
- **Status appearance**: whether Increase Contrast and Differentiate Without Colour are on.

## Privacy review *(Constitution, Privacy)*

One new on-device key holds the palette choice (yes or no); no personal data, nothing sent. No new
permission.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ACC-003-S1**: In grayscale renderings, 100% of the state pairs that must be told apart differ in at
  least 1% of their pixels by at least 20% brightness, in light and dark appearance, and a colour-only
  pair of equal brightness measures as indistinguishable.
- **ACC-003-S2**: 100% of interface colours meet R6 and R7's contrast ratios.
- **ACC-003-S3**: The accessibility audit of the show editor passes with zero contrast filters for "Add
  Current Scene".
- **ACC-003-S4**: With the palette setting off, the spectra's colours are identical to before.

## Assumptions

- The simulator cannot turn on iOS's colour filters; grayscale is computed from renderings, and the real
  filters plus Increase Contrast are checked on D1 in the last stage (`{device}`).
- iOS's Increase Contrast reaches the app through the trait collection; UI tests force it with a DEBUG
  trait override.
