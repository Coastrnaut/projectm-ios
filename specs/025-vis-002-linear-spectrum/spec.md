# Feature Specification: VIS-002 Linear Spectrum

**Feature Branch**: `feature/vis-002` (spec directory `025-vis-002-linear-spectrum`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement VIS-002 (Linear spectrum) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Render vertical or horizontal FFT
bars with spacing and peak caps." Acceptance, verbatim: "Reference spectrum yields correct bar count
and bounded height." Dependencies: ANL-002 (integrated); reuses VIS-001 (ADR-0009), FX-001 glow
(ADR-0010) and the FX-019 flash envelope (ADR-0011). Honor the repository constitution and owner
rule 7."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `VIS-002-R1…`, success criteria `VIS-002-S1…`, tasks `VIS-002-T01…`. Requirements
of other features are cited by their own IDs: FR-065 (what the app may store), FR-070
(accessibility), FR-072 (Reduce flashing); VIS-001-R1, R8, R11 to R19 (the native visual contract,
the visual choice, band input, lifecycle and fallback); FX-001-R4, R10 to R13 (glow); FX-019-R4,
R9, R11 (the strobe safety envelope).

## Baseline: what exists today (audit of 2026-11-13, commit `6cfcbaa`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Native visuals | VIS-001 ships one native visual, the circular spectrum (`Packages/VisualGenerators`, ADR-0009): band vector in, one frame drawn into a caller's texture, CPU geometry, Metal pipeline compiled at runtime. | No bar visual with a straight baseline, no orientation, no peak caps. |
| Choosing a visual | Settings → Visual offers "projectM" and "Circular Spectrum" (`settings.visual`), plus Bars (16/32/64/128) and Glow controls shown only for the circular spectrum. | A third choice and its own options. |
| Bands | `LiveBandAnalyzer` feeds normalized ANL-002 bands to the native visual while it presents (VIS-001-R14). | Nothing new: reused as is. |
| Glow | FX-001's bloom runs after the circular spectrum; its luminance model lets Reduce flashing bound the composited frame (FX-001-R10). | Must apply to the new visual the same way. |
| Flash safety | FX-019's envelope bounds every native frame in 17 areas (16 tiles and the whole frame) from the circular spectrum's own area model. | The new visual needs an exact area model of its own and must go through the same envelope. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Watch a bar spectrum of the music (Priority: P1)

A user playing music opens Settings from the visualizer controls, chooses the visual "Linear
Spectrum", and sees a row of bars along the bottom of the screen, one bar per frequency band, low
frequencies on the left; a bar rises when its band is loud. A thin cap above each bar marks its
recent peak: it stays briefly at the highest point, then falls back at a steady speed. The user can
switch the bars to horizontal (they grow from the left edge, low frequencies at the top) and choose
how much space separates the bars. Choices are remembered on the next launch; projectM stays the
default.

**Why this priority**: It is the row's observable behavior ("Render vertical or horizontal FFT bars
with spacing and peak caps").

**Independent Test**: In the simulator, start the reference track, choose Linear Spectrum in
Settings, check that it is on screen and projectM's view is not; choose Horizontal; relaunch and
check that the visual and the orientation persisted.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses "Linear Spectrum" in Settings, **Then** the linear spectrum replaces the current visual without restarting the audio source, and preset navigation is hidden as for the circular spectrum.
2. **Given** Linear Spectrum chosen, **When** Settings is open, **Then** Bars, Orientation (Vertical, Horizontal), Spacing (None, Narrow, Wide) and the Glow controls are offered.
3. **Given** Orientation set to Horizontal, **When** the app is relaunched, **Then** the visualizer opens with the horizontal linear spectrum.

---

### User Story 2 - A reference spectrum gives the right bars at a bounded height (Priority: P1)

Whoever checks the visual (a developer, CI) feeds a reference band vector and sees exactly as many
bars as bands, each in its own slot, each as long as its value says and never longer than the
drawable area allows, whatever the input.

**Why this priority**: It is the roadmap acceptance ("Reference spectrum yields correct bar count and
bounded height").

**Independent Test**: For each bar count and each orientation, lay out a reference spectrum (a ramp
of values, with NaN, negative, above-1 and infinite entries mixed in) at a few output sizes: the
number of bar slots equals the band count, each bar's length equals its sanitized value × the
maximum length, every bar and cap lies inside the output, and spacing leaves the documented gap;
render a reference spectrum offscreen at a small size in each orientation and read the pixels back.

**Acceptance Scenarios**:

1. **Given** N bands (16, 32, 64, 128) in either orientation, **When** the reference spectrum is laid out, **Then** exactly N bar slots exist, slot k is the k-th equal division of the cross axis, and lit bars are exactly those with a value above 0.
2. **Given** any value (in range, out of range, NaN, ±infinity) and any output size, **When** laid out, **Then** each bar's length is between 0 and the maximum bar length, every coordinate is finite, and every bar and cap lies inside the output.
3. **Given** a spacing s, **When** laid out, **Then** each bar's width is (1 − s) of its slot and the bar is centred in its slot.
4. **Given** the reference spectrum rendered offscreen in each orientation, **When** pixels are read back, **Then** lit pixels appear only in the predicted bar and cap rectangles (within one pixel), the expected bars are lit along their length, and nothing is drawn beyond the bars' bounds.

---

### User Story 3 - Peak caps hold, then fall (Priority: P2)

A user sees each bar's recent peak as a cap that stays at the highest value for a short hold time
and then falls at a constant speed until it meets the bar again.

**Why this priority**: The "peak caps" part of the observable behavior.

**Independent Test**: Drive one bar with a value of 1 for a frame, then 0, with fixed frame times (an
injected clock, no wall time): the cap stays at 1 for the hold time, then falls at the fall rate,
and stops at the bar.

**Acceptance Scenarios**:

1. **Given** a bar that reaches value v, **When** following frames are lower, **Then** its cap stays at v for 0.5 s of frame time.
2. **Given** the hold time passed, **When** frames continue, **Then** the cap falls by 1.0 bar length per second of frame time and never below the current bar value.
3. **Given** a new value above the cap, **When** that frame is laid out, **Then** the cap jumps to it and the hold restarts.

---

### User Story 4 - Safe behavior: glow, Reduce flashing, rotation, failure (Priority: P2)

The linear spectrum behaves like the circular one: glow can be turned on, Reduce flashing and the
always-on strobe envelope limit flashing, turning the device keeps the bars on the screen's bottom
(or left) edge, leaving the app stops its work, and a device that cannot draw it falls back to
projectM with a notice.

**Why this priority**: Constitution safety rules and the existing native-visual guarantees apply to
every visual.

**Independent Test**: Run a fast full/empty strobe through the linear spectrum and the envelope and
count transitions; lay out portrait and landscape sizes; force the fallback in the app.

**Acceptance Scenarios**:

1. **Given** a strobe of full and empty bands at 60 Hz, **When** drawn with Reduce flashing on (and off), **Then** no area of the frame has more transitions per second than FX-019 allows (4 on, 6 off) and, with it on, no area rises faster than 0.25 per second.
2. **Given** a portrait or landscape output, **When** laid out, **Then** vertical bars still rise from the output's bottom edge across its full width (horizontal bars from its left edge across its full height).
3. **Given** the native visual cannot be created, **When** Linear Spectrum is chosen, **Then** projectM is shown with the notice "Linear Spectrum isn't available on this device. Showing projectM."

### Edge Cases

- Silence: no bar and no cap is drawn (caps exist only above 0); only the background shows.
- Band vector shorter or longer than the bar count: missing bands read 0, extra values are ignored.
- Bar count, orientation or spacing changed while running: effective from the next frame, no allocation; changing the bar count or orientation resets the peak caps.
- Out-of-range configuration (spacing, length scale, cap thickness, hold, fall rate): clamped; non-finite values take their defaults.
- Zero or tiny output size: zero draws nothing; tiny sizes give valid, in-bounds geometry.
- A very long frame (app paused, hitch): frame time is clamped to 0.1 s so caps never jump far.
- Pause keeps the last frame; resuming starts the caps from the current values.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-002-R1**: The linear spectrum MUST be a native visual under VIS-001's generator contract (VIS-001-R1, R19): band vector and frame context in, one frame drawn into a caller-provided texture, no dependency on the app, projectM or capture, no allocation, lock, log or I/O per frame, identical inputs giving identical geometry.
- **VIS-002-R2**: It MUST draw N bars, N = 16, 32, 64 or 128 (the ANL-002 band counts), bar k driven by band k's value sanitized as VIS-001-R8 (NaN and negative → 0, above 1 → 1, missing → 0, extras ignored).
- **VIS-002-R3**: Orientation: *vertical* (default) puts the cross axis along the output's width and the bars' length axis upward from the bottom edge, band 0 at the left; *horizontal* puts the cross axis along the height and the bars' length axis rightward from the left edge, band 0 at the top. Orientation is relative to the output (the screen as currently held), not the device.
- **VIS-002-R4**: Slots and spacing: the cross axis is divided into N equal slots of pitch C/N (C = cross-axis size in pixels); bar k occupies the centred fraction (1 − s) of slot k, s = spacing in 0…0.9 (default 0.2). The app offers None (0), Narrow (0.2, default) and Wide (0.5).
- **VIS-002-R5**: Bounded length: with L the length-axis size in pixels, a bar of value v is v × λ × L long, λ = length scale in 0…(1 − t) (default 0.9), t = cap thickness in 0…0.05 of L (default 0.015). Every bar and cap MUST lie inside the output; lengths are never negative and every coordinate is finite for any input.
- **VIS-002-R6**: Peak caps: each bar has a peak value p. When the bar's value v ≥ p, p = v and a hold of 0.5 s starts; while the hold lasts p stays; afterwards p falls by 1.0 per second of frame time but never below v. Frame time is the context's frame duration clamped to 0…0.1 s (no wall clock). The cap is a rectangle of the bar's width and thickness t × L starting at p × λ × L, drawn only when p > 0, in the bar's color. Caps are computed from the displayed values (after the Reduce-flashing slew). Hold, fall rate and thickness are configuration values (clamped; hold 0…5 s, fall 0.1…10 per second).
- **VIS-002-R7**: Colors use VIS-001's palettes (VIS-001-R6): bar k's color depends only on k, N and the palette (default Spectrum); a cap has its bar's color.
- **VIS-002-R8**: Geometry (per bar: slot, bar rectangle, cap rectangle, color) MUST be computable without a GPU so it can be tested on every CI host, including Linux.
- **VIS-002-R9**: Flash safety: every frame MUST pass through FX-019's envelope exactly as the circular spectrum's does (FX-019-R4, R9): Reduce flashing's bar slew (VIS-001-R10) and the envelope's single gain, computed from the frame's exact levels in the 16 tiles and the whole frame (bar and cap areas clipped to the tiles), after the glow when it runs (FX-001-R10); the envelope's history follows FX-019-R11.
- **VIS-002-R10**: Glow: the FX-001 glow and its settings (FX-001-R4, R11 to R13) apply to the linear spectrum exactly as to the circular spectrum; the glow settings are shared by both native visuals.
- **VIS-002-R11**: The app MUST offer "Linear Spectrum" as a third Visual choice (stored value `linearSpectrum` under `settings.visual`); while it is chosen, Settings offers Bars (shared with the circular spectrum, `settings.circularSpectrum.bars`), Orientation (Vertical, Horizontal; key `settings.linearSpectrum.orientation`, unknown → vertical) and Spacing (None, Narrow, Wide; key `settings.linearSpectrum.spacing`, any other value → Narrow), and the Glow controls. This amends FR-065 as VIS-001-R11 did: exactly these two new user-setting keys are added to what may be stored, and the device privacy check's allowed list gains them.
- **VIS-002-R12**: Switching between visuals or changing the linear spectrum's options MUST NOT restart the audio source (VIS-001-R12); the lifecycle (VIS-001-R15), controls (VIS-001-R13) and failure fallback (VIS-001-R16) apply unchanged, with the notice naming the chosen visual.
- **VIS-002-R13**: Accessibility (FR-070): the visual is one element labeled "Linear Spectrum visualization" whose value names the orientation and the glow state (for example "Vertical, Glow off"); each new control has a label equal to its meaning and a stable identifier.
- **VIS-002-R14**: The circular spectrum's behavior MUST NOT change: shared code is refactored only where VIS-001, FX-001 and FX-019 tests stay green unchanged.

### Key Entities

- **Linear spectrum configuration**: bar count, orientation, spacing, length scale, cap thickness, peak hold, peak fall rate, palette, background.
- **Linear bar geometry**: per bar: slot start and end on the cross axis, bar length, cap start and end on the length axis, color.
- **Peak cap state**: per bar: peak value and remaining hold time.
- **Linear spectrum settings**: orientation and spacing (user settings).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-002-S1**: For every bar count (4) × orientation (2) × output size checked (portrait, landscape, square), the reference spectrum yields exactly N bar slots, and every lit bar's length equals its sanitized value × λ × L within 0.001 pixel.
- **VIS-002-S2**: For in-range, out-of-range, NaN and infinite inputs, 100 % of bars and caps lie inside the output with finite coordinates and non-negative lengths.
- **VIS-002-S3**: Peak caps hold for 0.5 s and then fall 1.0 per second within 1e-6 under an injected clock, and never fall below the bar.
- **VIS-002-S4**: In small offscreen renders (one per orientation), 100 % of lit pixels lie inside the predicted bar and cap rectangles grown by one pixel, and the expected bars are lit; where no GPU exists the check is reported as skipped, never as passed or failed.
- **VIS-002-S5**: A 60 Hz full/empty strobe through the linear spectrum yields at most 4 transitions per 1 s window in every area with Reduce flashing on and at most 6 with it off.
- **VIS-002-S6**: Choosing Linear Spectrum and Horizontal, relaunching, and finding both restored works in one UI test of at most 30 s with the source started exactly once; the existing native-visual UI tests pass unchanged.
- **VIS-002-S7**: Every existing VisualGenerators test (VIS-001, FX-001, FX-019) passes unchanged.

## Assumptions

- The band input, its analysis and its lifecycle are VIS-001's (`LiveBandAnalyzer`); this row adds no analysis.
- The simulator renders with the host GPU; CI simulators may lack a usable GPU, so GPU checks may skip there. Real-device GPU checks are `{device}` tasks for the roadmap's final phase.
- No new stored data besides the two user-setting keys; no network; the privacy manifest does not change.
- projectM stays the default visual.
- Palette choice, length scale, cap thickness, hold and fall rate have no user controls in this row (parameter registry and UIX-011 later).
