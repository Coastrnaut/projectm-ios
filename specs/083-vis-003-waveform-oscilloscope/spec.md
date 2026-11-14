# Feature Specification: VIS-003 Waveform Oscilloscope

**Feature Branch**: `feature/vis-003` (spec directory `083-vis-003-waveform-oscilloscope`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (device task VIS-003-T17 open)

**Input**: User description: "Implement VIS-003 (Waveform oscilloscope) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Draw time-domain signal with
trigger stabilization." Acceptance, verbatim: "Sine fixture displays stable periodic cycles without
allocation spikes." Dependencies: ANL-002 (integrated); reuses VIS-001/VIS-002 (ADR-0009), FX-001
glow (ADR-0010) and the FX-019 flash envelope (ADR-0011). Keep the projectM backend isolated. Honor
the repository constitution and owner rule 7."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `VIS-003-R1…`, success criteria `VIS-003-S1…`, tasks `VIS-003-T01…`. Requirements
of other features are cited by their own IDs: FR-065 (what the app may store), FR-070
(accessibility), FR-072 (Reduce flashing); VIS-001-R1, R11 to R19 (the native visual contract, the
visual choice, lifecycle and fallback); VIS-002-R9 to R14 (shared pass, shared area model, glow);
FX-001-R4, R10 to R13 (glow); FX-019-R4, R9, R11 (the strobe safety envelope); QA-002 (golden
images, ADR-0030).

## Baseline: what exists today (audit of 2026-11-13, commit `01c0388`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Native visuals | VIS-001 (circular) and VIS-002 (linear) spectra in `Packages/VisualGenerators` (ADR-0009): a band vector in, one frame drawn into a caller's texture by the shared flat-triangle pass (`FlatShapePass`), CPU geometry, Metal shader compiled at runtime. | No visual draws the time-domain signal. |
| Time-domain samples | The normalized ring's analysis tap (stereo, 44.1 kHz) is read only by `LiveBandAnalyzer`'s ANL-016 pipeline, which turns it into spectra and bands. Visuals receive bands only (`TextureGenerator.encode(bands:)`); no path hands samples to a visual. | The smallest path that gives the frame loop the newest samples without a second reader of the single-consumer tap. |
| Trigger | None. | A stabilizer that keeps a periodic signal stationary on screen. |
| Choosing a visual | Settings → Visual lists one row per `VisualChoice`; native spectra show Bars, linear options and Glow. | A new choice and its own options. |
| Glow, flash safety | FX-001 bloom after the native visual; FX-019 envelope from the visual's 17-area level model (`FlashRegionLayout`, `SpectrumFlashAreas`). | The oscilloscope must provide an area model of its own and pass through both the same way. |
| Golden images | QA-002 compares SCN-001 scenes rendered through the compositor (`Packages/RenderGoldens`, macOS and iOS Simulator classes). | A golden image of the oscilloscope drawing a sine fixture. |
| Scenes, show cues | Scene documents record the visual as compositor layer kinds (`spectrum.circular`, `spectrum.linear`, …). | Out of scope (see Clarifications). |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option, recommended option
first.

- Q: How do time-domain samples reach the visual without a second reader of the single-consumer analysis tap? → A: A pass-through tap: the analysis pipeline keeps reading the tap through a small wrapper that forwards every read unchanged (and the tap's capture-session generation) and, on the same analysis worker, folds the frames into a fixed mono history (mid = (L + R)/2, 4,096 samples ≈ 93 ms) published through a wait-free triple buffer; the frame loop copies the newest history without waiting. The ANL-016 pipeline, its bands and every other consumer are unchanged. Rejected: a second tap reader (the tap has one consumer by contract); adding samples to the analysis bus frame (changes ANL-016's shared types and every subscriber's copy cost) (VIS-003-R2).
- Q: What trigger keeps the picture still? → A: A rising crossing of the midpoint between the history's minimum and maximum (so a DC offset does not move it; implementation finding 2026-11-13: the mean of a span holding a non-whole number of periods shifts with the window position and moved a 110 Hz sine's or a sawtooth's crossing by up to 0.03 cycle, the midpoint does not) with hysteresis (the signal must first fall 5 % of its peak-to-peak range below the level), located to a fraction of a sample by linear interpolation, searched in the history before the newest displayable window. When several crossings qualify, the one whose following window best matches the previous frame's picture (sum of squared differences over 64 points) wins, the newest among equals, so successive frames keep the same phase. Silence (peak-to-peak below 0.002) and aperiodic signals (no crossing, or no grouping of 1 to 4 consecutive crossing intervals whose spread stays within 10 % of its mean; a periodic wave with k crossings per period passes at grouping k) free-run: the newest window is shown and the match reference is cleared. Rejected: autocorrelation over the whole history (O(n²) per frame); a fixed zero level (a DC offset would stop triggering) (VIS-003-R3 to R6).
- Q: What does the user choose? → A: Two options, like the linear spectrum: Line (Thin, Medium, Thick: 0.4 %, 0.8 %, 1.6 % of the output's shorter side; default Medium) and Window (10, 20, 40 ms; default 20 ms), keys `settings.oscilloscope.line` and `settings.oscilloscope.window`. Glow is shared with the spectra (existing keys); Bars does not apply and is hidden. Palette, amplitude scale and trigger thresholds have no user control in this row (VIS-003-R9, R10).
- Q: How is the line drawn and colored? → A: As a polyline of up to 1,024 points spanning the output's width, centred vertically, a full-scale sample (±1) reaching 90 % of the half height (samples clamped to ±1), each segment a flat rectangle of the chosen thickness with a bevel triangle filling the outer side of each turn so joints have no gaps (implementation finding 2026-11-13: square-capped segments extended by half the thickness overlap at every joint, which made the flash area model count a thick line's light up to about 8 times over on flat stretches; bevel joins overlap only on a turn's inner side), colored by VIS-001's Spectrum palette from left to right (color depends on position, never on the sample value). Rejected: a GPU line primitive (1 px wide only on Apple GPUs, no thickness); per-sample color from amplitude (loudness would change color and light) (VIS-003-R7, R8).
- Q: Does the oscilloscope become a scene layer and get a scene-based golden image? → A: No, not in this row. A scene layer needs the compositor's audio context to carry samples and a new SCN-001 layer kind (SceneFormat, SceneArchive, the fuzz corpus, the golden scene catalog), which is a separate row's work. Scene capture (autosave, show looks) records the oscilloscope like projectM: no native layer, so restoring such a scene shows projectM; the Visual setting itself persists independently. The golden image uses QA-002's comparison rule, image format, manifest, record policy and integrity check on a generator-level fixture (the oscilloscope fed a fixed sine, no scene) in a folder of its own beside the scene goldens (VIS-003-R12, R14).

- Q (clarify pass): Does the band analysis keep running while the oscilloscope is shown? → A: Yes. The oscilloscope is one more style of the same native host: the analyzer still runs (it is the tap's only reader and feeds MOD-002 bindings and SHOW-011's tap tempo), the host just hands the generator the sample history instead of the bands. One frame loop, one glow chain, one capture and recording path for all three native visuals. Rejected: a separate host for the oscilloscope (duplicates the lifecycle, capture and recording code) (VIS-003-R1, R2, R11).
- Q (clarify pass): Where does the generator-level golden live and how is it recorded? → A: `Packages/RenderGoldens/GeneratorGoldens/<class>/` with its own `manifest.json`, file name `waveform-oscilloscope-sine-<w>x<h>-f1.png` at both QA-002 resolutions (128 × 96, 256 × 192), recorded with `GOLDEN_RECORD=1` exactly as the scene goldens; its integrity test applies `GoldenIntegrity.check` to that folder with the generator catalog. The scene catalog and the scene golden folders are untouched (VIS-003-R14).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See a steady waveform of the music (Priority: P1)

A user playing music opens Settings from the visualizer controls, chooses the visual
"Oscilloscope", and sees the audio's waveform as a bright line across the middle of the screen. A
steady tone shows as still, repeating cycles instead of a sideways crawl. The user can choose a
thinner or thicker line and a shorter or longer time window. Choices are remembered on the next
launch; projectM stays the default.

**Why this priority**: It is the row's observable behavior ("Draw time-domain signal with trigger
stabilization").

**Independent Test**: In the simulator, choose Oscilloscope in Settings and check that it is on
screen and projectM's view is not; choose Thick and 40 ms; relaunch and check that the visual and
both options persisted.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses "Oscilloscope" in Settings, **Then** the oscilloscope replaces the current visual without restarting the audio source, and preset navigation is hidden as for the spectra.
2. **Given** Oscilloscope chosen, **When** Settings is open, **Then** Line (Thin, Medium, Thick), Window (10 ms, 20 ms, 40 ms) and the Glow controls are offered, and Bars is not.
3. **Given** Line Thick and Window 40 ms chosen, **When** the app is relaunched, **Then** the visualizer opens with the oscilloscope and both options restored.

---

### User Story 2 - A sine fixture shows stable cycles without allocation spikes (Priority: P1)

Whoever checks the visual (a developer, CI) feeds a sine fixture in irregular chunks, as the capture
delivers audio, and sees the same picture every frame: the displayed window starts at the same
phase of the cycle, and drawing a frame never allocates memory.

**Why this priority**: It is the roadmap acceptance ("Sine fixture displays stable periodic cycles
without allocation spikes").

**Independent Test**: Advance a sine (a few frequencies and sample rates) by realistic, varying
sample counts per frame and run the trigger each frame: the phase at the window's start varies by
less than 1 % of a cycle across frames. Run the trigger and the layout over many frames with
fixed-capacity storage whose capacity and addresses never change. Render the sine fixture offscreen
and compare it with the golden image.

**Acceptance Scenarios**:

1. **Given** a sine of 110 Hz, 440 Hz or 1 kHz at 44.1 kHz (and one at 48 kHz), **When** 60 frames are triggered with 700 to 770 new samples between frames, **Then** the start phase of every triggered frame is within 0.01 cycle of the first one.
2. **Given** square and sawtooth fixtures, **When** triggered the same way, **Then** they are as stable.
3. **Given** a sine with a DC offset of +0.3, **When** triggered, **Then** it still triggers and is as stable.
4. **Given** silence or white noise, **When** triggered, **Then** the stabilizer reports free-run and shows the newest samples.
5. **Given** 1,000 frames of the trigger and 300 of trigger, layout, tessellation and area levels, **When** run, **Then** no storage is created after setup (fixed capacities and buffer addresses are unchanged).
6. **Given** the sine fixture rendered offscreen at the golden resolutions, **When** compared with the committed golden for this platform class, **Then** it passes QA-002's rule.

---

### User Story 3 - Safe behavior: glow, Reduce flashing, rotation, failure (Priority: P2)

The oscilloscope behaves like the spectra: glow can be turned on, Reduce flashing and the always-on
strobe envelope limit flashing, turning the device keeps the line across the screen's width,
leaving the app stops its work, and a device that cannot draw it falls back to projectM with a
notice.

**Why this priority**: Constitution safety rules and the existing native-visual guarantees apply to
every visual.

**Independent Test**: Alternate a full-scale and a silent input at 60 Hz through the oscilloscope and
the envelope and count transitions; lay out portrait and landscape sizes; force the fallback in the
app.

**Acceptance Scenarios**:

1. **Given** frames alternating between a loud waveform and silence at 60 Hz, **When** drawn with Reduce flashing on (and off), **Then** no area of the frame has more transitions per second than FX-019 allows (4 on, 6 off).
2. **Given** a portrait or landscape output, **When** laid out, **Then** the line spans the output's full width and stays inside its height.
3. **Given** the native visual cannot be created, **When** Oscilloscope is chosen, **Then** projectM is shown with the notice naming "Oscilloscope".

### Edge Cases

- Silence: a flat line at the centre (free-run); never a blank or jumping picture.
- Fewer samples than the window (just after start): the missing older samples read 0.
- NaN or infinite samples: treated as 0; out-of-range samples are clamped to ±1.
- Period longer than about a third of the search span (low bass with the 40 ms window): with fewer than three crossings periodicity cannot be judged, so the newest crossing that fits is used; with none the picture free-runs.
- A sudden change of signal: the match reference adapts at once, because the best-matching crossing is always one of the current signal's crossings.
- Window or line changed while running: effective from the next frame, no allocation.
- Zero or tiny output size: zero draws nothing; tiny sizes give valid, in-bounds geometry.
- Pause keeps the last frame; resuming starts the trigger reference afresh.
- A capture restart: the history keeps flowing from the new session; the trigger re-acquires within a frame.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-003-R1**: The oscilloscope MUST be a native visual under VIS-001's generator contract (VIS-001-R1, R19) and the host contract the spectra share (VIS-002's `SpectrumTextureGenerator`): an input vector (here mono samples, −1…1) and a frame context in, one frame drawn into a caller-provided texture, no dependency on the app, projectM or capture, no allocation, lock, log or I/O per frame, identical inputs giving identical geometry.
- **VIS-003-R2**: Samples MUST reach the frame loop without a second reader of the analysis tap and without changing the ANL-016 pipeline: a pass-through wrapper forwards each read and the session generation unchanged and keeps a 4,096-sample mono history (mid of the first two channels), published through a wait-free hand-off with fixed storage. Nothing reaches projectM (Constitution VIII).
- **VIS-003-R3**: Trigger level and hysteresis: the level is the midpoint (min + max)/2 of the history; a rising crossing counts only after the signal fell below level − h, h = 5 % of the span's peak-to-peak range; its position is interpolated linearly between the two samples around the level.
- **VIS-003-R4**: Phase continuity: among qualifying crossings whose window fits in the history, the stabilizer MUST choose the one whose following window (sampled at 64 points) has the smallest sum of squared differences from the previous frame's displayed window, preferring the newest crossing among candidates within 5 % (plus a small absolute tolerance) of the best score; with no previous window, the newest crossing.
- **VIS-003-R5**: Free-run: silence (peak-to-peak < 0.002), no qualifying crossing, or an aperiodic signal (with at least k + 2 crossings for a grouping k of 1 to 4 consecutive intervals, no k whose grouped intervals' standard deviation is within 10 % of their mean; the period estimate is the mean grouped interval of the smallest passing k) MUST show the newest window and clear the match reference.
- **VIS-003-R6**: Displayed window: W = window length × 44,100 samples (441, 882 or 1,764), starting at the trigger position, drawn as P = min(W, 1,024) points spanning the output's width, samples resampled linearly at fractional positions.
- **VIS-003-R7**: Geometry: x from 0 to the output width; y = H/2 − s × 0.9 × H/2 for a sample s (sanitized: NaN/±∞ → 0, clamped to ±1); each of the P − 1 segments is a flat rectangle of thickness T (fraction of the output's shorter side, clamped to 0.001…0.05, at least 1 px) centred on the segment with butt ends, and each turn between two segments gets a bevel triangle on its outer side; every coordinate is finite and every sample point lies inside the output (a thick line's corners may reach up to T/2 past the left and right edges; the GPU and the area model's tile clipping drop that part alike).
- **VIS-003-R8**: Colors use VIS-001's palettes (default Spectrum): segment k's color depends only on k, the segment count and the palette; premultiplied, linear; background opaque black by default.
- **VIS-003-R9**: Flash safety: every frame MUST pass through FX-019's envelope exactly as the spectra's do (FX-019-R4, R9; VIS-002-R9): one gain on the line's colors computed from the frame's levels in the 16 tiles and the whole frame, each segment's rectangle and each bevel triangle being one region (where regions overlap on a turn's inner side the light is counted twice, which only overestimates it), after the glow when it runs (FX-001-R10); the envelope's history follows FX-019-R11. Reduce flashing has no per-value slew for samples (a waveform has no level to slew); the envelope bounds the light.
- **VIS-003-R10**: The app MUST offer "Oscilloscope" as a Visual choice (stored value `oscilloscope` under `settings.visual`); while chosen, Settings offers Line (Thin, Medium, Thick; key `settings.oscilloscope.line`, values `thin`/`medium`/`thick`, anything else → medium), Window (10, 20, 40 ms; key `settings.oscilloscope.window`, an Int of milliseconds, anything else → 20) and the Glow controls (shared keys), not Bars. This amends FR-065 as VIS-001-R11 and VIS-002-R11 did: exactly these two new user-setting keys are added to what may be stored, and the device privacy check's allowed list gains them.
- **VIS-003-R11**: Switching visuals or options MUST NOT restart the audio source (VIS-001-R12); the lifecycle (VIS-001-R15), controls (VIS-001-R13) and fallback (VIS-001-R16) apply unchanged, with the notice naming the chosen visual.
- **VIS-003-R12**: Scene capture records the oscilloscope as no native layer (as projectM); no SCN-001 kind is added in this row.
- **VIS-003-R13**: Accessibility (FR-070): the visual is one element labeled "Oscilloscope visualization" whose value names the window and the glow state (for example "20 ms, Glow off"); each new control has a label equal to its meaning and a stable identifier.
- **VIS-003-R14**: A golden image of the sine fixture (440 Hz at 44.1 kHz, Medium line, 20 ms, glow off) MUST be compared under QA-002's rule, per platform class (macOS host, iOS Simulator), with QA-002's record policy, CI guard and integrity check; physical devices report "pending".
- **VIS-003-R15**: The spectra's behavior MUST NOT change: their tests stay green unchanged, and the pass-through tap leaves the bands bit-identical.

### Key Entities

- **Oscilloscope configuration**: window length, line thickness, amplitude scale, palette, background.
- **Waveform history**: the newest 4,096 mono samples and a running count of samples written.
- **Trigger result**: start position (fractional sample index in the history), mode (triggered or free-run), crossing count and period estimate.
- **Oscilloscope settings**: line and window (user settings).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-003-S1**: For sines at 110 Hz, 440 Hz and 1 kHz (44.1 kHz) and 440 Hz at 48 kHz, square and sawtooth at 220 Hz and a sine with +0.3 offset, 60 frames with varying advances give a start-phase spread below 0.01 cycle.
- **VIS-003-S2**: Silence and white noise free-run in 100 % of frames; the free-run window is the newest one.
- **VIS-003-S3**: Over 1,000 frames (the stabilizer) and 300 frames (the whole layout with its area levels) the storage capacities and addresses never change, and the hand-off delivers complete histories (no torn frame) under a concurrent writer.
- **VIS-003-S4**: The sine fixture passes QA-002's golden comparison on the macOS host and the iOS Simulator; where no GPU exists the check is reported as skipped.
- **VIS-003-S5**: A 60 Hz loud/silent alternation yields at most 4 transitions per 1 s window in every area with Reduce flashing on and at most 6 with it off.
- **VIS-003-S6**: Choosing Oscilloscope, Thick and 40 ms, relaunching, and finding the visual and its window restored works in one UI test of at most 30 s (the line's persistence is a unit test) with the source started exactly once; the existing native-visual and glow UI tests pass unchanged.
- **VIS-003-S7**: Every existing VisualGenerators and RenderGoldens test passes unchanged.

## Assumptions

- The audio is the normalized ring's 44.1 kHz stereo analysis tap; the 48 kHz case exercises the stabilizer only (it is rate-independent).
- The simulator renders with the host GPU; real-device frame time and allocations under Instruments are `{device}` work for the roadmap's final phase.
- No new stored data besides the two user-setting keys; no network; the privacy manifest does not change.
- projectM stays the default visual.
