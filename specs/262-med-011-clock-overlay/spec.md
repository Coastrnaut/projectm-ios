# Feature Specification: MED-011 Clock Overlay

**Feature Branch**: `feature/med-011` (spec directory `262-med-011-clock-overlay`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MED-011 (Clock overlay) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Display locally computed time in
configurable format." Acceptance, verbatim: "Fixed injected clock renders deterministic time
string." Priority P2, size S, depends on MED-009 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `MED-011-R1…`, success criteria
`MED-011-S1…`, tasks `MED-011-T01…`. Other features are cited by their own IDs: MED-009 (text
overlay and its layer), MED-010 (logo overlay, the pattern for a layer on every compositor visual),
CMP-001/002 (compositor and layer stack), CMP-013 (render caching), UIX-013 (scene HUD), OUT-005
(safe-area guides), REC-001/REC-003 (capture and recording), OUT-001 (external display), FILE-005
(library backup), FILE-011 (local data erase), SHOW-007 (show transport).

## Baseline: what exists today (audit of 2026-11-14, commit `c63b5943`)

The row's gap status is "Gap candidate". The audit confirms the gap: nothing in the app draws the
time.

| Area | Behaviour today | What this row reuses or adds |
|---|---|---|
| Text layer (MED-009) | `TextLayerSource` draws a `TextOverlaySpec` (message, font, weight, size, colour, alignment, vertical position, outline, box) with CoreText off the frame loop, only when the spec or the picture size changes; per frame it clears and blits (no shader). It is still for CMP-013, so a static message renders once. `TextLayerKind` already notes that "MED-011 (clock) … feed the same layer changing strings". | The clock is a `TextLayerSource` fed a new message only when the time string changes. No new renderer. |
| Text visual (MED-009) | The "Text" visual (circular spectrum plus the saved message) with `TextOverlayStore` (`settings.text.overlay`) and an editor in Settings. | Unchanged; the clock is a separate overlay with its own setting, so it can show over the Text visual too. |
| Logo overlay (MED-010) | `LogoCoordinator.attach(to:)` adds a top layer to each compositor visual (Photo, Video, Camera, Text) when it is made; layers are held weakly. projectM and the native spectra have no compositor and show no logo. | Same pattern: a clock layer attached to each compositor visual's stack. |
| Scene HUD (UIX-013) | A SwiftUI overlay on the device showing scene information; not in captures or recordings. | Not used: the clock is content, not device chrome. |
| Safe-area guides (OUT-005) | Drawn on the device's editor only; never reach output. | Not used, for the same reason. |
| Show transport (SHOW-007) | A timeline transport with its own position. | Not used in this row (see Clarifications). |

## Clarifications

### Session 2026-11-14 (speckit-specify, speckit-clarify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Where does the time come from? → A: An injected clock source. The app's source reads the
  device's wall clock and its current time zone (the system's own setting); nothing asks the network
  for the time (MED-011-R2). Tests inject a fixed date, locale and time zone, so every string is
  deterministic.
- Q: Is there an elapsed-show-time mode from the SHOW-007 transport? → A: Not in this row. The
  transport's position is show state, not "locally computed time", and a countdown/elapsed overlay is
  MED-012's subject. The clock source is a protocol, so such a mode can be added later without
  changing the layer.
- Q: Which formats? → A: Two hour styles, 24-hour ("14:05") and 12-hour ("2:05 PM"), each with or
  without seconds ("14:05:09", "2:05:09 PM"). The patterns are fixed; the locale supplies the AM/PM
  symbols and digits. Default: 24-hour without seconds (unambiguous and short).
- Q: How often does it update? → A: At most once per second, aligned to the start of each second.
  The layer redraws only when the string changes, so a clock without seconds redraws once a minute
  and CMP-013's caching keeps every other frame free.
- Q: Where and how is it drawn? → A: With the text overlay's own placement and style model
  (MED-009's `TextOverlaySpec` fields), stored separately from the Text visual's message. Defaults:
  top, trailing, size 6 % of the picture height, white bold Menlo with the default black outline. Settings
  offers position (top, middle, bottom) and alignment (leading, centre, trailing); the other style
  fields keep their defaults in this row.
- Q: Is the clock content or device chrome? → A: Content: it is a layer of the compositor visuals'
  stacks (like MED-010's logo), so it appears in REC-001 captures, REC-003 recordings and the
  OUT-001 external display, and the composite flash guard measures it. projectM and the native
  spectra have no compositor and show no clock in this row; Settings says so (same scope as the
  logo).
- Q: Is it on by default? → A: Off. It is shown only after the user turns on Show Clock.
- Q: Is the clock part of scenes? → A: No. It is a device preference (backed up with FILE-005,
  erased with Settings by FILE-011), not scene content; a later row can add a scene field.
- Q: How do VoiceOver users read the time? → A: The drawn clock adds no accessibility element (the
  system status bar already speaks the time); the Settings controls are standard labelled toggles and
  pickers, so VoiceOver reads each one's state (on/off, the chosen format and placement).

- Q: Should the clock's digits keep a fixed width so it does not shift sideways as the time changes? → A: Yes, by
  default: the clock's default font is Menlo (fixed-width digits, a system font already offered by
  MED-009), so a trailing or centred clock does not jiggle each minute. No renderer change (a
  digit-width feature for the system font was rejected: it would change MED-009's shared rasterizer).
- Q: Where are the clock's controls? → A: A "Clock" section in Settings' media sections, after the
  Logo section (both are overlays on the compositor visuals).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Show the time over the visual (Priority: P1)

A performer turns on Show Clock in Settings and sees the current local time over the Photo, Video,
Camera or Text visual, updated as the time changes, and in their recordings.

**Why this priority**: it is the row's observable behaviour.

**Independent Test**: with a fixed injected clock, the drawn clock's pixels are identical across
renders and change when the clock moves one minute.

**Acceptance Scenarios**:

1. **Given** Show Clock is off (the default), **When** a compositor visual is shown, **Then** no clock is drawn.
2. **Given** Show Clock is on and the clock reads 14:05:09 in the device's time zone, **When** the format is 24-hour without seconds, **Then** "14:05" is drawn.
3. **Given** the same fixed clock, **When** the visual renders twice, **Then** the clock's pixels are identical; **When** the clock moves one minute, **Then** they change.
4. **Given** a format without seconds, **When** seconds pass within one minute, **Then** the clock is not redrawn.

### User Story 2 - Choose the format and position (Priority: P2)

The performer picks 12-hour or 24-hour, with or without seconds, and where the clock sits.

**Independent Test**: each setting change is saved, survives a relaunch and changes the drawn string or placement.

**Acceptance Scenarios**:

1. **Given** 12-hour with seconds, **When** the time is 14:05:09, **Then** "2:05:09 PM" is drawn.
2. **Given** any change, **When** the app relaunches, **Then** the same settings are in effect.

### Edge Cases

- Midnight: 23:59 → 00:00 (24-hour), 11:59 PM → 12:00 AM (12-hour).
- Daylight saving: at a spring-forward the clock goes from 01:59 to 03:00; at a fall-back from 01:59 back to 01:00; the string always follows the time zone's rules.
- The device's time zone or clock changes while shown: the next update (within a second) uses the new time.
- A damaged or newer stored value reads as the defaults (off); a damaged value is removed.
- The app is in the background or the visual is paused: no frames are drawn; the next frame shows the current time.
- projectM or a native spectrum is shown: no clock (no compositor); Settings notes it.

## Requirements *(mandatory)*

### Functional Requirements

- **MED-011-R1**: The app MUST offer a clock overlay that draws the current local time as text over the compositor visuals (Photo, Video, Camera, Text), off by default.
- **MED-011-R2**: The time MUST come from an injected clock source; the app's source uses the device's wall clock and current time zone. No network time is used.
- **MED-011-R3**: Formats: 24-hour or 12-hour, each with or without seconds (patterns `HH:mm`, `HH:mm:ss`, `h:mm a`, `h:mm:ss a`) with an injected locale and time zone.
- **MED-011-R4**: The clock MUST be drawn by the MED-009 text layer with a `TextOverlaySpec` style (no new renderer, no new shader).
- **MED-011-R5**: Updates happen at most once per second, aligned to second boundaries; the layer redraws only when the string changes.
- **MED-011-R6**: The clock is a layer of the compositor stack, so it appears in captures, recordings and the external display, and the composite flash guard applies.
- **MED-011-R7**: Settings: Show Clock, Format (24-hour, 12-hour), Seconds, Position (top, middle, bottom), Alignment (leading, centre, trailing), with a note that projectM and the native spectra show no clock.
- **MED-011-R8**: The settings are one versioned value in the app's settings (`settings.clock.overlay`); missing → defaults; damaged → defaults and removed; newer → defaults, left untouched.
- **MED-011-R9**: The value is a backed-up preference (FILE-005) and is erased with Settings (FILE-011); it is removed by the UI-test reset.
- **MED-011-R10**: Nothing leaves the device; no new permission.

### Key Entities

- **Clock settings**: shown or not, hour style, seconds, and the text style (placement and look).
- **Clock source**: gives the current date and the time zone to show it in.
- **Clock text**: the formatted string for a date; changes at most once per second.

## Success Criteria *(mandatory)*

- **MED-011-S1**: A fixed injected date, locale `en_US_POSIX` and a fixed time zone give exactly "14:05", "14:05:09", "2:05 PM" and "2:05:09 PM" (roadmap acceptance).
- **MED-011-S2**: With a fixed injected clock, two renders of the clock layer give identical pixels; one minute later they differ.
- **MED-011-S3**: Over 60 one-second updates in one minute without seconds, the layer rasterizes once and renders once.
- **MED-011-S4**: Midnight and both daylight-saving transitions give the expected strings.
- **MED-011-S5**: Settings survive a relaunch; a short UI test turns the clock on and sees it drawn.

## Assumptions

- The device's time zone and clock are trusted as set by the user or the system.
- A device check (readability on D1/D3, a recording that includes the clock) is a `{device}` task.
