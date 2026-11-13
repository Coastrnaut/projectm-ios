# Feature Specification: VIS-001 Circular Spectrum

**Feature Branch**: `feature/vis-001` (spec directory `019-vis-001-circular-spectrum`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement VIS-001 (Circular spectrum) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Render configurable radial bars
driven by frequency bands." Acceptance, verbatim: "Band impulse lights the correct angular segment
and survives rotation." Dependencies: ANL-002 (integrated). This is the first native (Metal) visual;
projectM stays the default and isolated. Honor the repository constitution, VIII and ADR-0008
decision 5."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `VIS-001-R1…`, success criteria `VIS-001-S1…`, tasks `VIS-001-T01…`. Requirements
of feature 001 that this row touches are cited by their own IDs: FR-065 (what the app may store),
FR-070 (accessibility), FR-072 (Reduce flashing), FR-041/FR-083 (orientation and full screen),
FR-046/FR-050 (pause and background). ANL-002's band contract (ANL-002-R1, R8, R13) and PERF-011's
presentation lifecycle (PERF-011-R2 to R4) stay in force.

## Baseline: what exists today (audit of 2026-11-13, commit `1d74d3d`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Visuals | The app draws only through projectM on ANGLE's Metal backend (`ANGLERenderer`, ADR-0003); GLESRenderer is the fallback. No native visual, no `Packages/VisualGenerators`, no Metal shader of the app's own. | Everything: a generator interface, the circular spectrum, a way to choose it, its lifecycle and its fallback. |
| Bands | ANL-002 (`Packages/AnalysisFeatures`: `SpectrumStream`, `BandReducer`, `BandMath`) turns normalized PCM into 16/32/64/128 log-frequency bands with 0…1 helpers. The app does not use the package yet. | Nothing feeds bands to a visual at frame rate. |
| Audio to analysis | `NormalizedPCMRing(analysisTapCapacityFrames:)` (ANL-001-R9) can add an analysis tap, off by default. The ring the app uses is created inside `AudioAnalyzer` without a tap; ANL-016 (event bus) does not exist yet. | No way for the app to turn the tap on. |
| Lifecycle | `PresentationResourceRegistry` (PERF-011) suspends registered frame loops and surfaces in the background and while locked; ANGLERenderer registers itself. | A second visual must register too. |
| Reduce flashing | FR-072: projectM frames pass through `CFlashLimiter` (mean luminance moves at most 0.3 per second). | The native visual needs its own bound. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option, recommended option
first.

- Q: Where does the user choose between projectM and the circular spectrum, and how is the choice kept? → A: In Settings (opened from the visualizer controls), a "Visual" section with a picker "projectM" / "Circular Spectrum", plus a "Bars" picker (16/32/64/128) shown only for Circular Spectrum. Both are stored in UserDefaults with the existing AppSettings pattern (`settings.visual`, `settings.circularSpectrum.bars`), which are user settings under FR-065; the device privacy check's allowed list gains the two keys. Rejected: a button in the controls overlay (the compact layout already holds seven icon buttons, and the visual is a setting, not a per-moment action). The other geometry parameters (radius, gap, rotation offset, start angle, direction, palette) are configurable through the generator's configuration; their user controls belong to the parameter registry and palette rows (PAR, UIX-011) (VIS-001-R4, R11).
- Q: Does "survives rotation" mean turning the device or the visual's own rotation offset? → A: Both, tested separately. Turning the device changes the output size; the ring is laid out relative to the current screen, so bar k keeps its angle relative to the screen (band 0 at the top in portrait and landscape), stays circular, centred and wholly visible, and the source is not restarted. The rotation offset turns the whole ring by its angle; every bar's angle moves by exactly that amount (VIS-001-R3, R5; User Story 3).
- Q: How do live bands reach the visual before the analysis event bus (ANL-016) exists? → A: The smallest correct path: `AudioAnalyzer` and `CaptureManager` gain an optional analysis-tap capacity (default 0, unchanged behavior) and `CaptureManager` exposes the tap reader; the app turns it on with the ring's default 0.5 s. A dedicated serial analysis queue runs a timer only while the circular spectrum is presenting, pulls the tap through `SpectrumStream` (2,048 points, hop 512, mid) and `BandReducer`, normalizes with `BandMath` (decibels, floor −80 dB) and publishes the newest band frame through a lock-free triple buffer that the frame loop reads without waiting. projectM's reader and the audio callback are untouched; while projectM is shown, nobody reads the tap and it drops its oldest audio (bounded, counted). ANL-016 later replaces the timer with its bus (VIS-001-R14).
- Q: What pixel format, alpha and color space does the generator write, and how are its shaders built? → A: `bgra8Unorm_srgb` (sRGB-encoded 8-bit, blending in linear light) by default, `rgba16Float` (linear, extended) also accepted; premultiplied alpha; palette colors are defined in sRGB and converted to linear once per configuration. Shader source is a constant inside the package, compiled by the system's Metal compiler when the pipeline is created, never read from a file or the network. Build-time compilation of `.metal` files was rejected after measurement: the build Mac's Xcode 27.2 has no Metal Toolchain installed (`metal` reports "missing Metal Toolchain"), so a `.metal` resource fails `swift build` and the app build, and CI images are not guaranteed to have it either; installing it is a download outside this feature's scope. ADR-0009 records the architecture and this choice (VIS-001-R1, R17).
- Q: What exactly does Reduce flashing bound for this visual, given that the full flash envelope is FX-019? → A: Two conservative bounds while the app's Reduce flashing setting is on: each bar's displayed value moves at most 4.0 per second toward its band value (softens both rises and falls), and the frame's mean relative luminance, computed from the bar areas and linear palette luminance, rises at most 0.25 per second of frame time (frame time clamped to 0…0.1 s), enforced by a uniform dimming gain. A 0.1 luminance step (WCAG's flash threshold) then takes at least 0.4 s to build, so no more than 2.5 such rises fit in a second. Falls are only slew-limited; the two-sided envelope across all effects is FX-019's (VIS-001-R10).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Watch a circular spectrum of the music (Priority: P1)

A user playing music (any permitted source: In-App Playback, Microphone, System/App Capture where
available) opens Settings from the visualizer controls, chooses the visual "Circular Spectrum"
instead of "projectM", and sees a ring of bars around the centre of the screen. Each bar stands for
one frequency band, from low frequencies to high ones going clockwise from the top; a bar grows
outwards when its band is loud. The choice is remembered on the next launch. projectM stays the
default and is unchanged.

**Why this priority**: It is the row's observable behavior ("Render configurable radial bars driven
by frequency bands").

**Independent Test**: In the simulator, start the reference track, choose Circular Spectrum in
Settings, check that the native visual is on screen and projectM's view is not, relaunch and check
the choice persisted; choose projectM again and check that projectM's view returns.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** the visualizer starts, **Then** projectM is shown exactly as before (default "projectM").
2. **Given** the visualizer running, **When** the user chooses "Circular Spectrum" in Settings, **Then** the circular spectrum replaces projectM without restarting the audio source, and the controls no longer offer preset navigation (no preset is shown).
3. **Given** Circular Spectrum chosen, **When** the app is relaunched, **Then** the visualizer opens with Circular Spectrum.
4. **Given** Circular Spectrum shown, **When** the user chooses "projectM", **Then** projectM resumes with its current preset.

---

### User Story 2 - A band impulse lights the correct angular segment (Priority: P1)

Whoever checks the visual (a developer, CI) feeds energy into exactly one band and sees exactly one
bar lit, at the angle the configuration predicts, for every bar count.

**Why this priority**: The first half of the roadmap acceptance ("Band impulse lights the correct
angular segment").

**Independent Test**: For each bar count (16, 32, 64, 128) and each band k, a band vector that is 0
everywhere except 1 at k produces bar geometry with exactly one bar of non-zero length, centred at
the angle computed in the test from the documented formula; an offscreen render of the same input,
read back pixel by pixel, has its lit pixels inside that angular sector only; a reference sine fed
through the real spectrum and band analysis lights the band that contains its frequency.

**Acceptance Scenarios**:

1. **Given** any bar count N and band k, **When** the band vector is the impulse at k, **Then** exactly one bar has non-zero length and its centre angle equals the predicted angle within 0.01°.
2. **Given** the same impulse rendered offscreen, **When** pixels are sampled along rays from the centre, **Then** every lit pixel lies within the predicted bar's sector widened by 1.5 pixels at its radius (at most 2°; rasterization tolerance), pixels along the predicted centre ray between the inner and outer radius are lit, and the neighbouring bars' centre rays are dark.
3. **Given** a steady sine from the AUD-016 reference tones, **When** it goes through the spectrum stream, the band reducer and the visual's input, **Then** the largest bar is the one whose band contains the sine's frequency.

---

### User Story 3 - The picture survives rotation (Priority: P1)

A user turns the phone or iPad between portrait and landscape. The ring stays a circle, stays
centred and fully on screen, and bar k stays at the same angle relative to the screen (the first
band stays at the top). A user who sets a rotation offset turns the whole ring by that angle.

**Why this priority**: The second half of the roadmap acceptance ("survives rotation").

**Independent Test**: Lay out the same impulse for portrait, landscape and iPad sizes and for
several rotation offsets: the lit bar's angle is the predicted one in every case, all geometry fits
the screen, and radii are equal in both axes; render offscreen at a portrait and a landscape size
and check the lit sector; rotate the simulator in a UI test and check the visual is still shown and
the audio source was not restarted.

**Acceptance Scenarios**:

1. **Given** an impulse at band k, **When** the output size changes between portrait (for example 1179 × 2556), landscape (2556 × 1179) and iPad sizes (2064 × 2752, 2752 × 2064, 1640 × 2360), **Then** the lit bar's centre angle relative to the screen is unchanged and every vertex lies inside the output.
2. **Given** any output size, **When** geometry is laid out, **Then** one unit of radius is the same number of pixels horizontally and vertically (circles stay circular).
3. **Given** a rotation offset of φ, **When** the impulse at band k is laid out, **Then** the lit bar's angle is the zero-offset angle plus φ (mod 360°), for φ in {−90°, 0°, 37.5°, 90°, 180°, 450°}.
4. **Given** the simulator rotated between portrait and landscape while Circular Spectrum runs, **When** the rotation completes, **Then** the visual is still shown and the source was started only once.

---

### User Story 4 - Safe behavior: Reduce flashing, background, failure (Priority: P2)

A photosensitive user with Reduce flashing on gets a gentler circular spectrum. Leaving the app or
locking the device stops the visual's work. If the device cannot draw the native visual, the user
gets projectM and a clear notice instead of a black screen or a crash.

**Why this priority**: Constitution safety rules (FR-072, PERF-011, failure boundary) apply to every
visual.

**Independent Test**: Unit-test the luminance limiter with alternating full and empty band vectors;
unit-test that the visual registers with the presentation registry and stops its frame loop and
analysis while suspended; force a pipeline failure in the app and check the fallback notice.

**Acceptance Scenarios**:

1. **Given** Reduce flashing on, **When** the bands alternate between all-zero and all-one every frame, **Then** the frame's mean relative luminance never rises by more than 0.25 per second of frame time (at most 0.025 for a frame time of 0.1 s or more), and each bar's length changes by at most 4 bar lengths per second.
2. **Given** Reduce flashing off, **When** the same input is drawn, **Then** bars follow the bands with no limit.
3. **Given** the visual running, **When** presentation is lost (background, lock), **Then** its frame loop and its analysis timer stop before the suspend call returns, and they resume on return unless the user paused.
4. **Given** the native visual cannot be created (no Metal device, or its pipeline fails), **When** the user has chosen Circular Spectrum, **Then** projectM is shown, a notice "Circular Spectrum isn't available on this device. Showing projectM." is visible and announced, and Settings says the visual is unavailable.

### Edge Cases

- Silence: every bar has zero length; only the background shows (no flicker on digital silence, ANL-002's zero-stays-zero).
- Band vector shorter or longer than the bar count, or containing NaN, infinity or values outside 0…1: values are clamped to 0…1 (NaN → 0); missing bands read 0; extra values are ignored.
- Bar count changed while running: takes effect at the next frame, without allocation.
- Configuration out of range (inner radius, length scale, gap): clamped to the documented ranges so the ring always fits the screen.
- Very small output (1 × 1 up to a few pixels) or zero size: zero size draws nothing and does not crash; tiny sizes produce valid geometry.
- Pause (FR-046): the last frame stays, as for projectM.
- The audio source stops or changes: bands decay to whatever the analysis reads (zero when nothing arrives); the visual never shows a stale source label (it shows none).
- projectM keeps receiving the same normalized PCM as before; nothing from the band analysis reaches it.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-001-R1**: The system MUST provide a native visual generator interface, separate from the projectM renderer, that takes a band vector, a monotonic time and an output size and draws one frame into a caller-provided texture of a declared pixel format (`bgra8Unorm_srgb` default, or `rgba16Float`), with premultiplied alpha and colors blended in linear light; drawing a frame MUST NOT allocate, lock, log or do I/O after setup, and identical inputs MUST give identical geometry.
- **VIS-001-R2**: The circular spectrum MUST draw N radial bars, N = 16, 32, 64 or 128 (the ANL-002 band counts), bar k driven by band k's normalized value v in 0…1: the bar runs from the inner radius outward by v × length scale (zero length at v = 0).
- **VIS-001-R3**: Bar k's centre angle MUST be θ(k) = start angle + d × (k + 0.5) × 360°/N + rotation offset, measured clockwise from the top of the output (12 o'clock), d = +1 (clockwise, default) or −1 (counter-clockwise); each bar spans (1 − gap) × 360°/N of arc.
- **VIS-001-R4**: The configuration MUST offer bar count, inner radius (0.05…0.9 of the radius unit, default 0.3), length scale (0…1 − inner radius, default 0.65), gap (0…0.9 of a bar's angular pitch, default 0.2), rotation offset (degrees, any value, default 0), start angle (degrees, default 0), direction (default clockwise) and palette; out-of-range values are clamped.
- **VIS-001-R5**: The radius unit MUST be half the output's shorter side, in pixels, the same in both axes, and the ring MUST be centred; so circles stay circular and the whole ring fits inside the output at any aspect ratio.
- **VIS-001-R6**: A minimal palette set MUST be offered and documented: "Spectrum" (hue from red at band 0 through the rainbow to violet, default), "Ice" (two-color gradient) and "Mono" (white). Bar colors depend only on bar index and palette, never on the band value, so loudness changes geometry, not color. Full palette editing is UIX-011.
- **VIS-001-R7**: The geometry (one record per bar: centre angle, angular half-width, inner and outer radius, color) MUST be computable without a GPU, so its correctness can be tested on every CI host including Linux.
- **VIS-001-R8**: Input band values MUST be sanitized: NaN and negative values read 0, values above 1 read 1, missing bands read 0, extra values are ignored.
- **VIS-001-R9**: No smoothing MUST be applied beyond the Reduce flashing limits (ANL-003 owns smoothing).
- **VIS-001-R10**: With Reduce flashing on (FR-072, the same app setting as projectM's), each bar's displayed value MUST move toward its band value by at most 4.0 per second of frame time, and the frame's mean relative luminance (computed from the bar areas and colors) MUST NOT rise by more than 0.25 per second of frame time, frame time clamped to 0…0.1 s; colors are dimmed uniformly when needed. The full two-sided flash envelope is FX-019's.
- **VIS-001-R11**: The app MUST offer a "Visual" choice in Settings between "projectM" (default) and "Circular Spectrum", stored under the user-settings key `settings.visual`; a stored value that is unknown reads as projectM. While Circular Spectrum is chosen, a "Bars" choice (16, 32, 64, 128; default 64) is offered and stored under `settings.circularSpectrum.bars`. This amends FR-065, whose user settings list FR-048 and FR-072 (as feature 002's FR-123 did for the preset scope): persistence additionally includes these two visual settings; nothing else is stored, and the device privacy check's allowed list gains exactly these keys.
- **VIS-001-R12**: Switching the visual MUST NOT restart or change the audio source, its label or the capture; projectM keeps its current preset and is paused (no frame loop) while the native visual is shown, and resumes when chosen again.
- **VIS-001-R13**: While the native visual is shown, the controls MUST NOT offer preset navigation (Previous, Next, Random, Presets, Duplicate) and the title area MUST name the visual; Stop, Pause/Resume, Settings and the transport stay.
- **VIS-001-R14**: Bands MUST reach the visual from the normalized ring's analysis tap through the ANL-001/ANL-002 analysis (2,048-point spectrum, hop 512, mid channel, decibel normalization with ANL-002's default floor) on a dedicated analysis queue, never on the audio callback and never on the main thread; projectM's reader MUST stay unchanged (Constitution VIII, ADR-0008 decision 5: nothing from this analysis goes to projectM). The tap MUST be enabled only by the app's capture manager configuration; other users of the analyzer keep the default (no tap).
- **VIS-001-R15**: The native visual's frame loop and its analysis timer MUST be presentation-bound resources (PERF-011-R2 to R4): registered with the app's registry, stopped while the app cannot present, resumed when it can unless the user paused; user Pause (FR-046) stops the frame loop and the analysis timer and keeps the last frame; stopping returns only after the timer is cancelled on its queue.
- **VIS-001-R16**: If no GPU device exists or the visual's pipeline cannot be built, the app MUST fall back to projectM and show a visible, accessible notice; the stored choice is kept, and Settings states the visual is unavailable. A rendering failure MUST never crash the app.
- **VIS-001-R17**: Shader source MUST be a constant inside the package, compiled by the system Metal compiler when the pipeline is created; no shader source is ever read from a file or the network. No private API, no networking, no new entitlement, no new third-party dependency.
- **VIS-001-R18**: Every new control MUST have an accessibility label equal to its meaning and a stable identifier (FR-070); the visual itself is one accessibility element labeled "Circular Spectrum visualization".
- **VIS-001-R19**: The generator interface MUST be adoptable later by CMP-001 (layer protocol) and reused by VIS-002, VIS-003, VIS-006 and VIS-020: it MUST NOT depend on the app, projectM, capture or the app's settings.

### Key Entities

- **Visual choice**: projectM (default) or Circular Spectrum; a user setting.
- **Circular spectrum configuration**: bar count, inner radius, length scale, gap, rotation offset, start angle, direction, palette.
- **Bar geometry**: per bar: centre angle, half-width, inner and outer radius, color.
- **Band frame**: N normalized band values and the time they were computed.
- **Luminance limiter state**: previous displayed bar values and previous mean luminance.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-001-S1**: For 100 % of impulse cases (every band of every bar count, 240 cases) × 5 output sizes × 6 rotation offsets, exactly one bar is lit and its centre angle matches the independently computed angle within 0.01°.
- **VIS-001-S2**: For every output size checked, 100 % of geometry lies inside the output and the radius unit is equal in both axes.
- **VIS-001-S3**: In offscreen renders at one portrait and one landscape size, for impulses at several bands of every bar count, 100 % of lit pixels found along sampled rays lie inside the predicted sector widened by 1.5 pixels at their radius (at most 2°), and the predicted centre ray is lit between the radii; where the environment has no usable GPU the render check is reported as skipped, never as passed or failed.
- **VIS-001-S4**: A steady reference sine lights its own band as the largest bar for each of the AUD-016 sine frequencies (100, 440, 1,000, 1,500 Hz) at every bar count.
- **VIS-001-S5**: With Reduce flashing on, 0 frames exceed the luminance rise bound and 0 bars exceed the slew bound over an alternating full/empty input of 600 frames at frame times from 1/120 s to 0.2 s.
- **VIS-001-S6**: Choosing the visual, relaunching, rotating and switching back work in UI tests with the source started exactly once; existing visualizer, settings and status UI tests pass unchanged.
- **VIS-001-S7**: 0 changes to what projectM receives: existing AudioCore, CaptureKit and rendering tests pass unchanged, and the tap is off unless the app enables it.

## Assumptions

- The normalized stream is 44.1 kHz stereo; the visual analyses its mid channel.
- The simulator renders with the host GPU; CI's simulators may have no usable GPU, so GPU checks there may skip. Real-device GPU checks are `{device}` tasks for the final phase.
- No new stored data besides the two user-setting keys; no network; the privacy manifest does not change.
- projectM stays the default visual; the native visual is opt-in.
- One native visual exists in this row; the composition of several layers is CMP-001's.
