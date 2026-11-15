# Feature Specification: OUT-009 Output Color Calibration

**Feature Branch**: `feature/out-009` (spec directory `268-out-009-output-color-calibration`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (OUT-009-T01-T13 verified on the Mac host and the iOS 27.2 simulator; T14 `{device}` open)

**Input**: User description: "Implement OUT-009 (Output color calibration) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Apply gamma and RGB trims per display." Acceptance, verbatim: "Calibration
changes output but leaves saved scene parameters untouched." P2, depends on OUT-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `OUT-009-R1…`, success criteria
`OUT-009-S1…`, tasks `OUT-009-T01…`. Other features are cited by their own IDs: OUT-001 (external display
scene), OUT-002 (recording hold), OUT-007 (corner pin and its calibration editor), OUT-010 (output blackout),
FX-003 (colour grade, a scene look), FX-019 (projectM's flash envelope pass), REC-001 (still capture),
REC-003 (recording), FILE-005 (library backup), FILE-011 (erase), ACC-005 (accessible parameters).

## Baseline: what exists today (audit of 2026-11-14, commit `1fe57ef3`)

| Area | Today | Gap for this row |
|---|---|---|
| External output (OUT-001) | The one visual view (projectM's ANGLE view, a native spectrum, or a Camera, Photo, Video or Text compositor host) moves into the external window's slot. Nothing is drawn twice. | No colour correction for the display. |
| Slot geometry (OUT-003, OUT-004, OUT-007) | Placement, drawable scale and the corner pin's `sublayerTransform` are applied by the external slot; any kind of layer content follows them because Core Animation composites them. | Core Animation offers no public colour transform for layer content on iOS: `CALayer.filters`, `compositingFilter` and `backgroundFilters` are documented as unsupported on iOS. |
| projectM (FX-019) | Every frame passes through one full-screen GL output pass (the flash envelope's gain, exact sRGB decode/encode) into the window surface. | A shared final pass exists that can apply a calibration. |
| Compositor visuals (CMP-001, FX-003) | Every frame passes through `cmp_output` (grade, tone map, flash gain) into the drawable; recordings and still captures re-run that pass into their own targets. | A shared final pass exists; recordings use a separate encode. |
| Native spectra (VIS-001 to VIS-004) | The generator (or the glow) draws straight into the drawable; there is no final pass. | No shared pass: not covered by this row. |
| Colour grade (FX-003) | A scene-level look saved with scenes; graded on compositor visuals only. | It is scene content, not display calibration. |
| Settings | Settings › External Display with OUT-007's "Corner pin…" full-screen editor; device-local `settings.externalDisplay.*` keys, left out of the backup and erased with Settings. | A calibration editor and its stored values. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which public iOS mechanism can colour-correct the external output? → A: Only the visuals' own final
  render passes. iOS documents `CALayer.filters`, `compositingFilter` and `backgroundFilters` as unsupported,
  an overlay layer can only multiply or add (no gamma, and no blend modes without those filters), SwiftUI's
  shader effects do not reach UIKit-hosted Metal or GL layers, and a `CAMetalLayer` colour space only tags
  content for the system's colour matching (it cannot express RGB trims reliably and its result cannot be
  verified). Snapshotting the slot every frame for a separate pass (`drawHierarchy`) is far too slow for
  live video. So calibration is applied in the two shared final passes that already exist: projectM's flash
  envelope output pass and the compositor's output pass (OUT-009-R2, R3).
- Q: Which visuals are covered? → A: projectM on ANGLE (the app's main visual) and every compositor visual
  (Camera, Photo, Video, Text, including their logo and other compositor layers). Not covered: the native
  spectra (circular, linear, oscilloscope, Lissajous), which draw straight into their drawables with no
  shared pass, the OpenGL ES fallback renderer (used only when ANGLE cannot start), and OUT-007's
  calibration test card. The editor says so; nothing claims coverage it does not have (OUT-009-R3, R8).
- Q: Does calibration reach the device, recordings, still captures or scenes? → A: No. It corrects one
  display's colour, so it applies only while the visual is on an external display. The device's own
  visualizer, recordings, still captures, thumbnails, scene documents, saved layer parameters and autosaves
  are unchanged: a recording is content, and calibration is a property of the display (OUT-009-R4, R5).

### Session 2026-11-14 (speckit-clarify)

- Q: Should calibration be stored per display (keyed by name or shape) or once for the app? → A: Once for
  the app, like OUT-007's corner pin. iOS gives no public, stable display name or identity (a scene session
  identifier changes per connection), and keying by shape would silently drop or swap a calibration when a
  projector reports another mode. "Per display" is honoured as "the external display, not the device"; Reset
  restores the defaults in one tap (OUT-009-R1, R9).
- Q: Is the transfer function applied to linear light or to the display-encoded signal? → A: To the
  display-encoded (sRGB) signal, as a display's own calibration curve works (and as projectM's pass already
  works in encoded values); the compositor pass encodes, applies and decodes so its sRGB target encodes it
  back. Gamma follows FX-003's convention (above 1 brightens mid-tones: exponent 1/gamma); the trims multiply
  after the gamma, then the result is clamped to 0…1 (OUT-009-R2).
- Q: Does calibration run before or after the flash safety envelope? → A: After it, as the last step of each
  final pass. The envelope (FR-072, FX-019) judges and limits the intended picture; calibration is a fixed,
  monotonic, per-channel curve that only compensates the display's response, so it never adds flashes or
  changes their timing. Measuring after calibration would make the envelope's gain depend on the display
  (OUT-009-R2, R3).
- Q: projectM's still capture reads the window surface after the final pass: is a capture calibrated? → A: No.
  When a capture is pending and calibration is not the identity, the output pass is drawn once uncalibrated
  for the read-back and then drawn again calibrated for the display, from the same envelope state (no second
  envelope update) (OUT-009-R5).
- Q: Should a lift/offset control be included? → A: No. The row asks for gamma and RGB trims; a lift raises
  black on a projector (it cannot lower it) and FX-003 already offers lift as a scene look (OUT-009-R1).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Match a projector's colour (Priority: P1)

A performer's projector shows the picture too green and with crushed shadows. With the display connected they
open Settings › External Display › Color calibration…, raise the gamma and lower the green trim until the
projected picture looks right. The device screen does not change.

**Why this priority**: It is the row's new behaviour.

**Independent Test**: Set a calibration and compare the external output's pixels with the prediction of the
transfer function; check the device output is unchanged.

**Acceptance Scenarios**:

1. **Given** the defaults (gamma 1, trims 1), **When** the visual is on the display, **Then** its pixels are
   exactly what they were without the feature.
2. **Given** gamma 1.5 and a red trim of 0.8, **When** a frame is shown on the display, **Then** each pixel
   equals the transfer function's prediction within one 8-bit step.
3. **Given** any calibration, **When** the same visual is on the device, **Then** the device shows it
   uncalibrated.

---

### User Story 2 - Calibration never edits the show (Priority: P1)

The performer saves scenes, records and autosaves while calibrated. The scenes and recordings carry the
intended colours, so the same show looks right on another display.

**Independent Test**: Save a scene document, its layer parameters and the autosave before and after
calibrating; they are byte-identical.

**Acceptance Scenarios**:

1. **Given** a saved scene and an autosave, **When** calibration is changed, **Then** both are byte-identical
   to before.
2. **Given** a running recording or a still capture on the display, **When** calibration is on, **Then** the
   recorded frames are uncalibrated.

---

### User Story 3 - Adjust accessibly, reset, keep (Priority: P2)

**Acceptance Scenarios**:

1. **Given** the editor, **When** VoiceOver users swipe on a slider, **Then** it moves one step and speaks
   the value.
2. **Given** any calibration, **When** Reset is chosen, **Then** every value returns to its default.
3. **Given** a calibration, **When** the app relaunches, **Then** it applies again; missing, malformed or
   out-of-range stored values read as the defaults (out-of-range values are clamped).

### Edge Cases

- No display connected: the editor still works; values apply when a display connects.
- A recording holds the placement (OUT-002): calibration changes no geometry, so it applies live.
- Blackout (OUT-010): the display stays fully black (the cover is above every visual).
- The visual changes (projectM ↔ a compositor visual ↔ a native spectrum) while on the display: the new
  visual takes the calibration (or, for a native spectrum, is shown uncalibrated, as the editor says).
- Values out of range are clamped; gain × signal is clamped to the displayable range.

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-009-R1**: The app MUST hold one colour calibration for the external output: gamma 0.5…2.5 (default 1)
  and red, green and blue trims 0.5…1.5 (default 1).
- **OUT-009-R2**: Per pixel and channel, on the display-encoded (sRGB) value e in 0…1 of the finished frame,
  the calibrated value MUST be clamp(trim × e^(1/gamma), 0, 1). At the defaults the frame MUST be unchanged
  bit for bit. Alpha is unchanged.
- **OUT-009-R3**: Calibration MUST be applied to the external output of projectM (ANGLE) and of every
  compositor visual, in each one's existing final pass (no extra rendering of the visual).
- **OUT-009-R4**: Calibration MUST apply only while the visual is shown on an external display; never on the
  device's visualizer.
- **OUT-009-R5**: Calibration MUST NOT change scene documents, saved layer or scene parameters, autosaves,
  recordings, still captures or thumbnails.
- **OUT-009-R6**: Calibration MUST apply live, inside the change, also while a recording holds the placement;
  it never moves the visual or touches the audio source.
- **OUT-009-R7**: The blackout (OUT-010) MUST keep the display fully black whatever the calibration.
- **OUT-009-R8**: Settings › External Display MUST offer "Color calibration…", a full-screen editor (OUT-007's
  pattern) with four sliders (Gamma, Red, Green, Blue) using ACC-005's accessible parameters, value readouts,
  Reset, and a note naming the visuals that are not calibrated.
- **OUT-009-R9**: The calibration MUST persist on the device as one device-local value (defaults are stored
  as absent; missing or malformed reads as the defaults). Like the other external display settings it is
  left out of the library backup, erased with Settings and removed by the UI-test reset.
- **OUT-009-R10**: A DEBUG probe MUST report the applied calibration and whether the held visual is
  calibrated (UI tests).

### Key Entities

- **Display calibration**: gamma and three trims; identity at the defaults; a stored text form.

## Success Criteria *(mandatory)*

- **OUT-009-S1**: At the defaults the external output is bit-identical to the uncalibrated output.
- **OUT-009-S2**: With a calibration, every tested output pixel matches the transfer function within one
  8-bit step.
- **OUT-009-S3**: A saved scene document, its layer parameters and the autosave are byte-identical before and
  after any calibration change.
- **OUT-009-S4**: The device visualizer and recordings are identical with and without calibration.
- **OUT-009-S5**: The calibration survives a relaunch in 100 % of runs.

## Assumptions

- One display at a time (OUT-001); one stored calibration (see Clarifications).
- Calibration is a display adjustment, not a scene look: FX-003's grade stays the scene's tool.
- Device evidence (a real display or projector) is a `{device}` task; simulator results are never device
  evidence.
