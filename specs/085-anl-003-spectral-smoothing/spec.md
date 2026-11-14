# Feature Specification: ANL-003 Spectral Smoothing

**Feature Branch**: `feature/anl-003` (spec directory `085-anl-003-spectral-smoothing`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement ANL-003 (Spectral smoothing) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Apply independent attack and
release smoothing to spectrum values." Acceptance, verbatim: "Step input reaches 90 percent by
attack setting and decays by release setting." Dependencies: ANL-002 (integrated). Verification:
unit tests with synthetic PCM, plus the simulator. Honor the repository constitution and owner
rules 4, 7 and 8."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `ANL-003-R1…`, success criteria `ANL-003-S1…`, tasks `ANL-003-T01…`. Requirements
of other features are cited by their own IDs: FR-065 (what the app may store), FR-070
(accessibility), FR-072 (Reduce flashing); ANL-002-R8 (band scale); ANL-004 (onset detection);
ANL-016-R16 (the live analyzer on the analysis bus); VIS-001-R9, R10 (no smoothing beyond Reduce
flashing; the Reduce-flashing slew); VIS-002-R6 (peak caps); FX-019 (the strobe envelope); MOD-002
(audio feature bindings).

## Baseline: what exists today (audit of 2026-11-13, commit `9f6839e`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Band extraction | ANL-001 spectra (2,048 points, hop 512, Hann, mid channel) → ANL-002 log bands (`BandReducer`) → decibel normalization 0…1 (floor −80 dB), inside the ANL-016 `AnalysisPipeline`; the newest band vector is published on the analysis bus. `SpectrumBandFeed` is the synchronous reference path with the same settings and says "no smoothing (ANL-003 owns it, VIS-001-R9)". | No attack/release smoothing of band values anywhere in `Packages/` or the app. |
| Live consumer | `NativeSpectrumHost` (circular and linear spectra, oscilloscope) reads the newest bands each display frame through `LiveBandAnalyzer.output.readLatest` (latest wins; between analysis frames it keeps the last vector) and hands them to the generator and to MOD-002's modulator. Camera, Photo, Video and Text hosts read the same way for their circular-spectrum layer. | The drawn bands jump to each new analysis frame. |
| Onset, tempo | ANL-004's spectral-flux onset detector and ANL-005's beat tracker run inside the pipeline on raw spectra; SHOW-011's tap tempo reads bus events. | Must not change (onset needs raw flux). |
| Existing time-based motion | VIS-001-R10: with Reduce flashing on, each bar moves at most 4.0 per second (a safety slew in the generator). VIS-002-R6: the linear spectrum's peak caps hold and fall (a separate visual element). FX-019: the always-on strobe envelope (a gain on the frame's light). | None of these is attack/release smoothing; they stay as they are (see Clarifications). |
| Settings | Settings → Visual offers Bars (spectra), Line/Window (oscilloscope), Orientation/Spacing (linear) and Glow. | No smoothing control. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option, recommended option
first.

- Q: Where does smoothing sit in the signal path? → A: After band extraction and normalization, per band, on the display side: the native spectrum host smooths the newest band vector once per display frame, using the real frame interval, before handing it to the generator. The analysis pipeline, the bus, the onset detector (which needs raw spectral flux), the beat tracker, the tap tempo and every other bus subscriber are unchanged. Rejected: smoothing inside the pipeline at the analysis hop (would change what every bus subscriber and future detector, such as ANL-007's kick, receives; and display frames between analysis frames would still step) (ANL-003-R1, R2).
- Q: Does it replace any existing smoothing? → A: No. Nothing in the code smooths bands today (VIS-001-R9 deferred it here). The Reduce-flashing slew (VIS-001-R10) is a safety bound and stays after smoothing; the peak caps (VIS-002-R6) follow the drawn (smoothed) bars as before; FX-019's envelope bounds the final light. VIS-001-R9 is amended: smoothing is the user's ANL-003 setting, applied before the Reduce-flashing limits (ANL-003-R8).
- Q: What do "attack" and "release" mean precisely? → A: Per band, a one-pole follower: y ← y + a·(x − y), with a = 1 − exp(ln(0.1)·Δt / τ), τ the attack time when x > y and the release time when x < y, Δt the frame interval in seconds. A step from y₀ to x therefore covers 90 % of the distance exactly at t = τ, at any frame rate and with irregular intervals (the product of the per-frame factors is exp(ln(0.1)·Σ Δt/τ)). τ = 0 means instant (a = 1) (ANL-003-R3, R4).
- Q: What are the defaults, and do they change today's look? → A: Attack and release both default to 0 ms (instant): the drawn bands are bit-identical to today's. Users opt in (ANL-003-R6).
- Q: Is it exposed to the user, and how? → A: Yes, minimally: two segmented rows under Settings → Visual, shown with Bars (circular and linear spectrum only): Attack (Instant, 25 ms, 50 ms, 100 ms) and Release (Instant, 100 ms, 250 ms, 500 ms), stored as Int milliseconds under `settings.spectrum.attack` and `settings.spectrum.release` (anything else → 0). This amends FR-065: exactly these two user-setting keys are added, and the device privacy check's allowed list gains them. Not in the parameter catalog, scenes or show cues in this row (ANL-003-R6, R7).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bars rise and fall at the speed I choose (Priority: P1)

A user watching the circular or linear spectrum finds the bars jittery. In Settings → Visual they
choose Attack 25 ms and Release 250 ms: bars now rise quickly with the music but fall back
smoothly. Choosing Instant for both gives exactly today's picture. The choice is remembered.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: In the simulator, choose Circular Spectrum, set Attack 50 ms and Release
500 ms, relaunch, and check both rows show the stored choices.

**Acceptance Scenarios**:

1. **Given** a native spectrum is chosen, **When** Settings is open, **Then** Attack and Release rows are offered next to Bars, each defaulting to Instant.
2. **Given** Attack 50 ms and Release 500 ms chosen, **When** the app is relaunched, **Then** both are restored and applied without restarting the audio source.
3. **Given** the oscilloscope (or projectM, Camera, Photo, Video, Text) is chosen, **When** Settings is open, **Then** no Attack or Release row is shown.

---

### User Story 2 - A step reaches 90 % by the attack time and decays by the release time (Priority: P1)

Whoever checks the smoothing (a developer, CI) feeds a band step up and a step down at a few
settings and frame rates and sees the value cross 90 % of the step at the attack (or release) time,
to within one frame.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Drive the smoother with synthetic band steps at 60 fps, 120 fps and a jittery
interval; drive the real band pipeline with a synthetic tone switched on and off.

**Acceptance Scenarios**:

1. **Given** attack τa ∈ {25, 100} ms and a step 0 → 1, **When** frames advance at 60 fps, 120 fps or a jittery interval (8–25 ms), **Then** the first frame whose value is ≥ 0.9 is at time t with τa ≤ t < τa + one frame interval.
2. **Given** release τr ∈ {100, 500} ms and a step 1 → 0, **When** frames advance the same way, **Then** the first frame with value ≤ 0.1 is at τr ≤ t < τr + one frame interval.
3. **Given** two bands stepping in opposite directions, **When** smoothed, **Then** one follows the attack time and the other the release time, independently.
4. **Given** attack and release 0, **When** any input is smoothed, **Then** the output equals the input every frame.
5. **Given** a synthetic 1 kHz tone switched on for 1 s then off, through the real band pipeline at 60 fps, **When** smoothed with attack 100 ms and release 500 ms, **Then** the tone's band reaches 90 % of its steady value no earlier than 100 ms and within 100 ms plus the analysis window fill and one frame; it falls to 10 % no earlier than 500 ms and within 500 ms plus the window and one frame.

### Edge Cases

- First frame, or the first frame of a new capture session (generation): the output takes the input directly; no ramp from zero or from the old session.
- Band count changes (Bars changed): the state takes the new vector directly.
- Pause/resume and presentation suspension: the next frame takes the input directly (no ramp from a stale picture), like the Reduce-flashing limiter.
- NaN or ±∞ input for a band: that band holds its previous value (0 on a first frame); outputs are always finite.
- Frame interval zero, negative or non-finite: no progress this frame (except instant times, which still follow the input).
- Times outside 0…2 s or NaN in the library: clamped (NaN → 0).
- Settings changed while running: effective from the next frame, no allocation.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-003-R1**: Smoothing MUST act on normalized band values (0…1, after ANL-002 and the decibel mapping), per band, with state for up to 128 bands, allocated once; a frame update MUST allocate, lock, log and wait for nothing.
- **ANL-003-R2**: The analysis pipeline, the bus frames, onset detection (ANL-004), beat tracking, the tap tempo and MOD-002's binding inputs MUST be unchanged; smoothing affects only the bands the native spectrum generators draw.
- **ANL-003-R3**: Update rule: for each band, with input x and state y, if x > y then a = A(τa) else a = A(τr), where A(τ) = 1 for τ = 0 and 1 − exp(ln(0.1)·Δt/τ) otherwise; y ← y + a·(x − y). The coefficients are computed once per frame from the frame interval Δt.
- **ANL-003-R4**: A step input MUST reach 90 % of the step by the attack time and decay by 90 % by the release time, independent of frame rate, within one frame interval (the roadmap acceptance).
- **ANL-003-R5**: Resets: the first frame after creation or `reset`, a change of the band count, or a change of the capture-session generation MUST set the state to the input directly; non-finite inputs follow the edge-case rule; non-positive or non-finite Δt gives no progress for non-zero times.
- **ANL-003-R6**: Settings: Attack (0, 25, 50, 100 ms) and Release (0, 100, 250, 500 ms), shown only for the circular and linear spectra, labeled "Instant" for 0, default 0, keys `settings.spectrum.attack` and `settings.spectrum.release` (Int ms; any other stored value → 0). FR-065 amended accordingly. Changing them MUST NOT restart the audio source.
- **ANL-003-R7**: Library bounds: times 0…2 s; values outside are clamped and NaN reads 0.
- **ANL-003-R8**: Order with existing motion: smoothing → the generator's Reduce-flashing slew (VIS-001-R10) → peak caps (VIS-002-R6, on the drawn bars) → glow → FX-019's envelope. VIS-001-R9 now reads "no smoothing beyond ANL-003's setting and the Reduce flashing limits".
- **ANL-003-R9**: Accessibility (FR-070): each row has a label equal to its meaning ("Attack", "Release") and a stable identifier.
- **ANL-003-R10**: The smoother MUST build on Linux and in the package's Linux shape (`-DANALYSIS_NO_ACCELERATE`).

### Key Entities

- **Smoothing times**: attack and release, seconds, 0…2.
- **Band smoother**: per-band state for up to 128 bands, the band count and generation of the last frame, and whether it has been primed.
- **Smoothing settings**: attack and release milliseconds (user settings).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-003-S1**: For attack 25 ms and 100 ms and release 100 ms and 500 ms, at 60 fps, 120 fps and a jittery 8–25 ms interval, the 90 % crossing lies within one frame after the set time in every case.
- **ANL-003-S2**: With both times 0 the output equals the input exactly for every frame of a random sequence.
- **ANL-003-S3**: Opposite steps on two bands follow their own time constants; a generation change, a band-count change and `reset` each take the input directly.
- **ANL-003-S4**: The tone on/off fixture through the real band pipeline meets User Story 2 scenario 5.
- **ANL-003-S5**: Choosing Attack and Release, relaunching and finding them restored works in one UI test of at most 30 s; the existing native-visual UI tests pass unchanged.
- **ANL-003-S6**: Every existing AnalysisFeatures and VisualGenerators test passes unchanged, on the host and in the Linux shape.

## Assumptions

- Display frames come from the host's `CADisplayLink`; tests inject frame intervals (no wall clock).
- Camera, Photo, Video and Text visuals keep raw bands in this row (their settings show no Bars either); extending smoothing to them is a follow-up.
- No new stored data besides the two user-setting keys; no network; the privacy manifest does not change.
- Simulator results are not performance evidence; device checks are not needed for this row's acceptance (pure arithmetic, verified by unit tests).
