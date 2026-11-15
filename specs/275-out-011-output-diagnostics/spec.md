# Feature Specification: OUT-011 Output Connection Diagnostics

**Feature Branch**: `feature/out-011` (spec directory `275-out-011-output-diagnostics`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (OUT-011-T01-T11, T13 verified on the Mac host and the iOS 27.2 simulator; T12 `{device}` open)

**Input**: User description: "Implement OUT-011 (Output connection diagnostics) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Show resolution, refresh rate and supported color format where available."
Acceptance, verbatim: "Unplugged display reports disconnected rather than stale data." P2, S, depends on OUT-001
(integrated)."

Identifiers in this feature carry the roadmap ID: requirements `OUT-011-R1…`, success criteria `OUT-011-S1…`,
tasks `OUT-011-T01…`. Other features are cited by their own IDs: OUT-001 (external display scene), OUT-002
(hot-plug), OUT-003 (output resolution), OUT-004 (aspect correction, pixel aspect), OUT-006 (output mode),
OUT-012 (rehearsal), ACC-005 (accessible parameters).

## Baseline: what exists today (audit of 2026-11-14, commit `264f2065`)

| Area | Today | Gap for this row |
|---|---|---|
| Connection state (OUT-001, OUT-002) | `ExternalDisplayCoordinator` holds the routing's settled displays and each display's slot (weakly); `hasExternalDisplay` is observable and cleared inside the disconnect call. | No user-visible description of the connected display. |
| Geometry | The slot reports points and display scale (`ExternalDisplayGeometry`) to the routing. | Native pixels, refresh rate, gamut and EDR headroom are never read. |
| Drawable (OUT-003) | The external slot's `resolvedOutput` (scale, pixel size, clamped); the DEBUG probe `externalResolution`. | Only a hidden test probe shows it. |
| Pixel aspect (OUT-004) | The screen mode's pixel aspect, or a stand-in (OUT-012). | Not shown to the user. |
| Output mode (OUT-006) | `outputMode` and `outputModeSummary` (DEBUG probe). | Not shown as a diagnostic. |
| Settings | Settings › External Display: Output, Fit, Shape, Pixel aspect, Resolution, Rehearse, Corner pin, Color calibration. | No diagnostics. |
| DEBUG fake display | `UITestExternalDisplay`: an off-screen 1920 × 1080 window driven through `ExternalDisplayEventSink`. | One size only; it sits on the device's own screen, so its screen object reports the device. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where are the diagnostics shown? → A: A new "Output Diagnostics" section in Settings, directly after
  Settings › External Display. It is always present: without a display it shows "No external display
  connected". No new screen, badge or overlay on the external output (OUT-001-R1 keeps that window clean).
- Q: What is the single source of truth for "connected"? → A: The coordinator's settled connection (the routing's
  displays and their live slots), the same state that places the visual. A connection still settling (OUT-002) is
  not yet "connected" here, matching where the visual is.
- Q: How are stale values ruled out? → A: The diagnostics are a value snapshot built from the live screen object at
  read time, or `.disconnected`. Nothing is cached across reads or connections; a disconnect makes the next read
  `.disconnected` inside the disconnect call, and a reconnect reads the new screen.
- Q: What if iOS does not report a value? → A: The row says "Not available". Nothing is estimated or guessed.

### Session 2026-11-14 (speckit-clarify)

- Q: How are values formatted? → A: Fixed, unlocalised-number formats so tests and VoiceOver agree: native resolution
  "1920 × 1080 px"; points "1920 × 1080 pt @1x" (scale with up to two decimals, trailing zeros dropped); refresh
  "60 Hz"; gamut "sRGB" or "Display P3"; EDR "1.0× potential, 1.0× current" (one decimal); mirroring "Extended" or
  "Mirrored"; drawable "1920 × 1080 px"; overscan "Scale", "Inset bounds" or "None"; pixel aspect "1.00" (two
  decimals); output "Same scene" or "Clean output" (the OUT-006 picker titles).
- Q: Should the panel be shown while a connection is still settling (OUT-002's 0.3 s)? → A: No: it reports not
  connected until the connection settles, so the panel agrees with where the visual is and never shows a display
  the app does not use.
- Q: Is "Copy diagnostics" offered, and how? → A: Yes, only while connected, copying plain text to the general
  pasteboard with the local-only option (no Universal Clipboard), no expiry needed; nothing is stored or exported
  otherwise. It is the conservative, local-first way to hand numbers to a technician.
- Q: How does the DEBUG stand-in report screen values, since its window sits on the device's own screen? → A: The
  stand-in slot carries stand-in screen readings (like OUT-012's stand-in pixel aspect): native size = its window
  size at scale 1, 60 Hz, sRGB, EDR not reported, extended, overscan None. A second button connects a 1280 × 720
  stand-in. Real scenes always read their own screen; DEBUG only.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See what the connected display reports (Priority: P1)

A VJ connects a projector over HDMI and opens Settings to check that the output really runs at the projector's
native resolution and refresh rate before the show.

**Why this priority**: The roadmap row's observable behaviour.

**Independent Test**: Connect the external stand-in display, open Settings › Output Diagnostics, read the values.

**Acceptance Scenarios**:

1. **Given** a connected external display, **When** the user opens Output Diagnostics, **Then** it shows native
   resolution (pixels), size in points and scale, maximum refresh rate, colour gamut, EDR headroom (potential and
   current), mirrored or extended, the drawable size in use, overscan compensation, pixel aspect and the output
   mode.
2. **Given** a value iOS does not report, **When** the panel shows it, **Then** that row reads "Not available".

### User Story 2 - Unplugging never leaves stale numbers (Priority: P1)

The VJ unplugs the projector. The panel must not keep showing the projector's numbers.

**Why this priority**: The roadmap row's acceptance.

**Independent Test**: Connect, disconnect, and check that the panel and every probe show "No external display
connected" and none of the old values; reconnect a display of a different size and see the new values.

**Acceptance Scenarios**:

1. **Given** a connected display, **When** it disconnects, **Then** the panel shows only "No external display
   connected" and no value of the old display remains in the panel, its rows or the diagnostics probe.
2. **Given** a disconnect followed by a connection of a display with a different size, **When** the panel is read,
   **Then** it shows the new display's values, never the old ones.

### User Story 3 - Share the numbers with a technician (Priority: P3)

The VJ copies the diagnostics as text to paste into a message to the venue's technician.

**Independent Test**: Tap "Copy diagnostics"; the pasteboard holds the rows as text, marked local-only.

**Acceptance Scenarios**:

1. **Given** a connected display, **When** the user taps "Copy diagnostics", **Then** the rows are copied as plain
   text to this device's pasteboard only (not shared to other devices).
2. **Given** no display, **Then** the copy button is not offered.

### Edge Cases

- A connection still settling (OUT-002): shown as not connected until it settles.
- The visual is not on the display (visualizer not shown, a recording holds it on the device): the drawable row
  reads "Not available" rather than a size from earlier.
- Two displays: the first settled display (the one OUT-001 routes to) is described.
- A screen whose refresh rate or headroom reads 0 or a non-finite value: "Not available".
- The OUT-012 rehearsal is not a display and never shows as connected.

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-011-R1**: Settings MUST offer an "Output Diagnostics" section after External Display, always visible.
- **OUT-011-R2**: While an external display is connected (settled), the section MUST show, each as a labelled
  row: native resolution in pixels, size in points with scale, maximum refresh rate, colour gamut, EDR headroom
  (potential and current), mirrored or extended, drawable size in use (OUT-003), overscan compensation, pixel
  aspect (OUT-004) and output mode (OUT-006).
- **OUT-011-R3**: A value the system does not report, or reports as zero or non-finite, MUST read "Not available";
  values MUST NOT be estimated.
- **OUT-011-R4**: The diagnostics MUST be built at read time from the live connection; they MUST NOT be cached
  across reads or connections. After a disconnect the next read MUST be "disconnected", inside the disconnect.
- **OUT-011-R5**: Without a connected display the section MUST show exactly "No external display connected" and
  no value of any earlier display.
- **OUT-011-R6**: The section MUST update when a display connects or disconnects while it is open, and refresh
  changing values (EDR headroom) at least once a second while open.
- **OUT-011-R11**: Values MUST use the formats recorded in Clarifications (session speckit-clarify).
- **OUT-011-R7**: Each row MUST be one accessibility element whose label is the row's name and whose value is its
  value (VoiceOver).
- **OUT-011-R8**: "Copy diagnostics" (shown only while connected) MUST copy the rows as text to the local
  pasteboard only, marked not to sync to other devices. No other export, no storage, no network.
- **OUT-011-R9**: The feature MUST add no settings keys and change no output behaviour.
- **OUT-011-R10**: The DEBUG fake display MUST be able to stand in for a display of a second size and report
  stand-in screen values, so the disconnect and reconnect paths are tested in the app; Release builds contain none
  of it.

### Key Entities

- **Output diagnostics**: either "disconnected" or a snapshot of one connected display's readings (each reading
  optional). It formats to labelled rows and to one text block.
- **Screen readings**: native pixel size, native scale, point size, scale, maximum frames per second, gamut, EDR
  headroom (potential, current), mirrored, overscan compensation; plus the output's own drawable size, pixel aspect
  and output mode.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **OUT-011-S1**: With a display connected, all ten rows are shown, and every row has a value or "Not available".
- **OUT-011-S2**: After a disconnect, 0 rows and 0 probes show any value of the old display; the panel reads "No
  external display connected" within the same update.
- **OUT-011-S3**: After reconnecting a display of a different size, 100 % of size rows show the new display's sizes.
- **OUT-011-S4**: No new settings keys, no network symbols, compliance checks pass.

## Assumptions

- The external display is reached through OUT-001's scene; its screen object is the scene's screen.
- Simulator results are never device evidence; a real HDMI display on D1 is a `{device}` task.
- "Supported color format" maps to what public APIs expose: the display gamut (sRGB or Display P3) and EDR
  headroom. iOS has no public API for the link's bit depth or chroma format; those are not shown.
