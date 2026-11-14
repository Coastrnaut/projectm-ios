# Feature Specification: OUT-004 Aspect Correction

**Feature Branch**: `feature/out-004` (spec directory `172-out-004-aspect-correction`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement OUT-004 (Aspect correction) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Handle pillarbox, letterbox and
non-square output pixel ratios." Acceptance, verbatim: "Test grid circles stay circular under chosen
correction." P1, M, depends on OUT-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `OUT-004-R1…`, success criteria
`OUT-004-S1…`, tasks `OUT-004-T01…`. Other features are cited by their own IDs: OUT-001 (external
display scene), OUT-002 (hot-plug, recording hold), OUT-010 (output blackout), CMP-006 (layer fit
modes), FX-020 (effect chain tail), REC-003-R11 (a recording stops when its picture size changes).

## Baseline: what exists today (audit of 2026-11-14, commit `5aaeebe5`)

| Area | Today | Gap for this row |
|---|---|---|
| Placement | OUT-001 moves the one visual view (ANGLE renderer view, compositor, native visual, Camera, Photo, Video, Text host) into the external `VisualSlotView`; the slot sets the view's frame to its bounds. Every visual lays out its drawable from its view's bounds, so it renders at the external display's size in points × scale. | No choice of how the visual's shape meets the display's shape; nothing keeps the device's composition. |
| Pixel aspect ratio | Not read anywhere (`UIScreenMode.pixelAspectRatio` unused). | Composite and analog adapters report non-square pixels; circles are drawn as ellipses there. |
| CMP-006 | `LayerFit` (fill, fit, stretch, pixel-accurate with an anchor) fits a photo or video *inside* a compositor layer. | Applies to layer content, not to the whole output on an external screen. |
| Compositor / FX-020 tail | The output pass, tone map and flash guard run inside the visual's own drawable. | Untouched by this row: correction is placement, outside scene rendering. |
| projectM on ANGLE | The engine's viewport is the drawable size from the view's bounds; projectM corrects its own aspect for square pixels. | Non-square pixels are not known to it. |
| Blackout | OUT-010's black cover sits above the visual in every slot. | Bars must stay black and the cover must cover them. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: Which correction modes are offered? → A: Fit (default: the whole picture is shown, black bars pillarbox or letterbox it), Fill (the screen is covered, the overflow is cropped at the centre) and Stretch (no correction: the picture covers the screen's pixels exactly, as before this feature). Rejected: CMP-006's pixel-accurate mode (meaningless for a rendered visual) and an anchor (centre only; nothing in the output has a subject to keep) (OUT-004-R1).
- Q: What is the "source shape" that Fit and Fill fit? → A: A second choice, **Shape**: "Display" (default) lays the visual out in the display's true physical shape, so nothing is cropped and there are no bars; only the pixel aspect ratio is corrected. "Device" keeps the device's own visualizer shape (its current orientation), so the audience sees the same composition as the performer; Fit then pillarboxes or letterboxes and Fill crops. Default Display keeps today's full-screen picture for the common case (a phone on a TV must not shrink to a portrait strip by default). Rejected: defaulting to the device shape (a 9:19.5 phone would fill a quarter of a 16:9 screen) (OUT-004-R2).
- Q: Is the internal (device) display affected? → A: No. The correction applies only while the visual is on an external display; on the device the visual fills its slot exactly as today (OUT-004-R3).
- Q: How is the pixel aspect ratio found? → A: "Pixel aspect: Automatic" (default) reads the external screen's current mode `pixelAspectRatio` (public UIKit) at every layout and when the screen's mode changes; values that are not finite or outside 0.5…2 read as 1. A manual override offers 1.0 (square), 0.9 and 1.2 for adapters that report the wrong value. The picture is pre-scaled horizontally by 1/PAR so a circle in the picture is a circle on the glass. Stretch ignores the PAR (no correction at all) (OUT-004-R4).
- Q: Where is the correction applied? → A: In the final placement of the visual's view in the external slot (its bounds, centre and a horizontal scale transform), never inside scene rendering. It is the same for projectM on ANGLE, the compositor and every native visual, and adds no render pass. The slot's own background is true black (the bars), and OUT-010's black cover stays above the visual and the bars (OUT-004-R5, R6).
- Q: What happens to a correction change during a recording? → A: OUT-002 holds the visual's placement while a recording runs; a correction change made then is kept and applied when the recording ends, so the recording's picture size never changes (REC-003-R11 never triggers from this setting) (OUT-004-R7).
- Q: How are the choices stored? → A: Three device-local UserDefaults strings: `settings.externalDisplay.fit` (`fit`, `fill`, `stretch`), `settings.externalDisplay.shape` (`display`, `device`), `settings.externalDisplay.pixelAspect` (`auto`, `1.0`, `0.9`, `1.2`); absent or unknown reads the default and nothing is stored until changed. They describe the user's display hardware, so they are left out of the library backup (excluded keys), erased with the Settings category, listed in the device test allow-list, and removed by `-uitestResetNotice` (OUT-004-R8).
- Q: Where is the UI? → A: A new "External Display" section in Settings with three pickers (Fit, Shape, Pixel aspect) and a footer explaining that it changes only the external display. It is always shown (a display can be connected later) (OUT-004-R9).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Circles stay round on any external screen (Priority: P1)

A performer connects an old composite adapter whose pixels are not square, or a 21:9 monitor. The
visual's circles stay circles; with Fit the whole picture is visible inside true black bars, with
Fill the screen is covered.

**Why this priority**: It is the row's observable behaviour and acceptance.

**Independent Test**: A pure geometry test computes the placement for 16:9, 4:3 and 21:9 screens, a
9:19.5 portrait source and PAR 1.0, 0.9 and 1.2, and checks a unit circle's physical radii.

**Acceptance Scenarios**:

1. **Given** Fit and any screen shape and PAR, **When** the visual is placed, **Then** a circle in the picture is a circle on the glass (radii within 0.5 %) and the whole picture is visible.
2. **Given** Fill, **When** the visual is placed, **Then** circles stay circles and the screen is covered.
3. **Given** Stretch and a source shape different from the screen, **When** the visual is placed, **Then** circles become ellipses (the documented "no correction" result).

### User Story 2 - Same composition as on the device (Priority: P2)

A VJ wants the projector to show exactly what the iPhone shows. They choose Shape "Device": the
projector shows the device's picture with black bars at the sides.

**Acceptance Scenarios**:

1. **Given** Shape Device and Fit on a 16:9 display with a portrait device, **When** the visual is placed, **Then** it is pillarboxed with black bars and its shape matches the device's.
2. **Given** the device rotates, **When** layout runs, **Then** the external placement follows the new device shape.

### User Story 3 - Settings and blackout (Priority: P2)

The performer changes the correction in Settings › External Display; it applies at once (or after
the recording ends). Blackout still turns the whole external screen, bars included, black.

**Acceptance Scenarios**:

1. **Given** the visual on an external display, **When** the user changes Fit, Shape or Pixel aspect, **Then** the placement changes inside the call, and the choice is restored after relaunch.
2. **Given** blackout, **When** any correction is active, **Then** the external screen shows only black.

### Edge Cases

- A display with a zero size, or a device shape not known yet: the visual fills the slot (no correction).
- Shape Display with Fit or Fill: identical (no bars, nothing cropped), only the PAR correction.
- Shape Display, PAR 1, Fit: exactly today's placement.
- PAR not finite or outside 0.5…2 (a bad adapter): read as 1.
- The visual moves back to the device: the correction is removed (identity transform, fills the slot).
- A correction change while a recording holds the placement: applied when the recording ends.

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-004-R1**: The external output MUST offer Fit (default), Fill and Stretch, centred.
- **OUT-004-R2**: The source shape MUST be selectable: Display (default; the display's physical shape) or Device (the device visualizer's current shape).
- **OUT-004-R3**: The device's own display MUST be unaffected.
- **OUT-004-R4**: The pixel aspect ratio MUST come from the external screen's current mode (Automatic) or a manual override (1.0, 0.9, 1.2); invalid values read 1. Fit and Fill MUST pre-scale horizontally by 1/PAR; Stretch MUST NOT correct.
- **OUT-004-R5**: Correction MUST be applied as the placement of the visual's view in the external slot, for every visual kind, with no change inside scene rendering and no extra render pass.
- **OUT-004-R6**: Bars MUST be true black, and OUT-010's blackout MUST cover the whole external screen, bars included.
- **OUT-004-R7**: While a recording holds the placement (OUT-002-R4), a correction change MUST be deferred until the hold ends.
- **OUT-004-R8**: The three choices MUST persist in device-local UserDefaults keys listed in the device test allow-list, the backup policy (excluded) and the UI-test reset.
- **OUT-004-R9**: Settings MUST show an External Display section with the three choices, accessible to VoiceOver and Dynamic Type.
- **OUT-004-R10**: Public APIs only (Constitution I); builds for iOS 26 and 27; the geometry is pure Swift tested on the host and Linux.

### Key Entities

- **Output correction**: fit mode, source shape, pixel aspect choice.
- **Output placement**: the view's layout size, its horizontal scale and its centre in the slot, computed from the slot size, PAR, source shape and fit mode.

## Success Criteria *(mandatory)*

- **OUT-004-S1**: For every combination of screen 16:9, 4:3, 21:9; source 9:19.5 portrait and the display's own shape; PAR 1.0, 0.9, 1.2; Fit and Fill keep a unit circle's physical x and y radii equal within 0.5 %; Fit shows the whole source; Fill covers the screen; Stretch differs (ellipse) whenever the source shape differs from the screen.
- **OUT-004-S2**: A grid of circles drawn by a visual view and rendered through the external slot measures an axis ratio within 2 % of 1 (PAR taken into account) for Fit and Fill, with black bars where expected.
- **OUT-004-S3**: The DEBUG fake external display UI test changes the setting and reads the bars probe in under 30 s.
- **OUT-004-S4**: The existing OUT-001, OUT-002 and OUT-010 tests still pass.

## Assumptions

- The simulator cannot present a non-square-pixel screen; the manual PAR override and pure tests stand in. A composite or analog adapter on a device is a `{device}` task.
- Rendering at a larger layout width when PAR > 1 costs a few percent more pixels; accepted.
