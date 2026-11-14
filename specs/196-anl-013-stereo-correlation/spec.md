# Feature Specification: ANL-013 Stereo Correlation

**Feature Branch**: `feature/anl-013` (spec directory `196-anl-013-stereo-correlation`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row ANL-013 (docs/FEATURE_ROADMAP_AUTONOMOUS.md), verbatim: "Estimate channel
similarity and phase inversion warnings." Acceptance, verbatim: "Identical and inverted stereo
fixtures produce opposite correlation signs." P2, size M, depends on AUD-009. Verification:
"Accelerate/vDSP, deterministic sample clocks; unit with synthetic PCM + simulator". The brief adds:
r = Σ(L·R) / √(ΣL²·ΣR²) over each analysis block of time-domain samples, in −1…1, smoothed with a
short time constant on an injected clock or hop count; 0 at or below a silence floor with no NaN; a
phase-inversion warning after a sustained r < −0.5 for more than 1 s, shown in the diagnostics or
overlay and in the source status ("Stereo channels look phase-inverted"), announced through the
status-event router (throttled) and cleared with hysteresis; r = 1 by definition for mono and for
every AUD-009 channel selection other than Mix (the warning cannot fire then); a binding source
mapped to 0…1 as (r + 1)/2 with the inspector name "Correlation"; mirror ANL-011/012.

Identifiers carry the roadmap ID: requirements `ANL-013-R1…`, success criteria `ANL-013-S1…`,
tasks `ANL-013-T01…`. Other features are cited by their own IDs: AUD-009 (channel selection),
ANL-011/012 (rolloff and flatness, the pattern followed here), ANL-016 (analysis event bus),
VIS-003/004 (waveform tap and its stereo history), MOD-002 (audio feature sources and bindings),
SHD-009 (expressions that read audio sources), UIX-003 (parameter inspector names), ACC-004 and
ACC-011 (announcer and status-event router), FR-042 (source status indicator), FR-048 (performance
overlay).

## Baseline: what exists today (audit of 2026-11-14, commit `4157fa8f`, ANL-012 integrated)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap: no
stereo correlation or phase measure exists in `Packages/` or `Apps/` (the only "correlation" code is
the beat tracker's autocorrelation, a different thing).

| Area | Today | Gap for this row |
|---|---|---|
| Stereo PCM | The analysis tap delivers Float32 interleaved stereo at 44.1 kHz (a mono source arrives as L = R). The ANL-016 pipeline reads it in chunks of up to 2,048 frames through AUD-008's trim and VIS-003's `WaveformTap` (pass-through), then mixes to mono for the spectra. VIS-004 keeps a stereo history (`WaveformTap.stereoOutput`) for the Lissajous. | The pipeline sees both channels per chunk but measures nothing between them. |
| AUD-009 | Mix passes stereo through bit for bit; Left, Right, Mid and Side write one signal into both channels (L′ = R′ = s). | Correlation must state what it means under each mode. |
| Bus | `AnalysisFrame` carries bands, onset, beat, kick, centroid, loudness, transients, rolloff, flatness. | No correlation field, no warning flag. |
| Modulation | MOD-002 `AudioFeatureSource` up to `.flatness`; SHD-009 opcodes 1–33 are taken (33 = flatness); 34 is free in every worktree. | No correlation source. |
| Status | FR-042's source indicator ("In-App Playback · Active audio"), ACC-011's router (rows X1–X28), FR-048's performance overlay. | No stereo warning anywhere. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: decisions delegated, no
human interaction); each answer is the recommended, conservative option.

- Q: Where is the PCM measured? → A: In the ANL-016 pipeline, on each interleaved chunk it already reads from the analysis tap (after AUD-009's channel selection and AUD-008's trim, through VIS-003's pass-through `WaveformTap`), before the mono mix-down. No second reader of the tap (it has one consumer), no extra buffer, and the sample clock is the session's consumed-sample count (ANL-013-R1, R4).
- Q: Block and smoothing? → A: Blocks of 1,024 frames (23.2 ms at 44.1 kHz), counted across chunk boundaries. Each block's three sums Σ L·R, Σ L², Σ R² (Double) feed exponentially smoothed sums with time constant τ = 0.1 s, decay a = exp(−1,024 / (τ·rate)) ≈ 0.793 per block, and r = S_LR / √(S_LL·S_RR), clamped to −1…1. Smoothing the sums rather than r weights loud passages correctly and keeps r exactly ±1 for identical or inverted channels; τ = 0.1 s is short enough for a visual to follow and gives ~4,400 effective samples (independent noise reads |r| ≈ 0.015). The value changes once per block, on the sample clock: no wall clock, no hop dependence (ANL-013-R1, R4).
- Q: What is the silence floor? → A: Per channel, the smoothed mean square S_xx / W (W the smoothed sample weight) at or below −70 dB re a full-scale sine (mean square 0.5 · 10⁻⁷, ANL-011's −70 dB rule applied to time-domain power). If either channel is at or below it, r = 0 and the reading has no signal: silence, dither and a one-sided signal (one channel silent) all read 0, never ±1 or NaN. Non-finite samples count as 0 (ANL-013-R2).
- Q: Warning thresholds and holds? → A: Raise when r < −0.5 for 1.0 s of consecutive blocks (44 blocks, 1.02 s ≥ 1 s); clear when r > −0.3 for 1.0 s (44 blocks). Between −0.5 and −0.3 both counters restart, so the state holds. Silence reads r = 0 > −0.3 and so clears a warning after 1 s. A session start clears it. The values are configuration (code), not settings (ANL-013-R3).
- Q: Mono and AUD-009 modes? → A: AUD-009 Left, Right, Mid and Side write one signal into both channels and a mono source arrives as L = R, so r = 1 exactly (S_LR = S_LL = S_RR) above the floor and 0 below it; the warning cannot fire (it needs r < −0.5). Mix passes the stereo through, so only Mix can show an inversion. Documented in the source docs and contract (ANL-013-R9).
- Q: Binding source and opcode? → A: MOD-002 `audio.correlation`, value (r + 1)/2 clamped to 0…1, so identical channels read 1, unrelated or silent 0.5, inverted 0; a missing or non-finite feed reads 0 like every MOD-002 source. SHD-009 opcode 34 (33 = flatness; 34 is free in every worktree), permanent. Inspector name "Correlation". `AudioFeatureFrame.correlation` carries raw r (−1…1); the mapping lives in the source (ANL-013-R6).
- Q: How does the warning reach the user? → A: The pipeline carries `phaseInverted` in every frame; the native visual reports changes to the app on the main actor (`onPhaseWarningChange`). The app appends " · Stereo channels look phase-inverted" to FR-042's source status (visible and the VoiceOver label), adds a "stereo:" line to FR-048's performance overlay (r and the warning), and posts ACC-011 status events on the `source` lane: X3a "Stereo channels look phase-inverted" when raised, X3b "Stereo phase normal" (a transient caption) when it clears after an announced raise. Both are system rows (dropped while the app is inactive). Throttle: a raise is announced at most once per 30 s (`PhaseWarningAnnouncementThrottle`, injected clock); ACC-004's per-lane gate applies on top. IDs X3a/X3b sit next to the source rows and avoid the X29+ numbers other features may take (ANL-013-R7, R8).
- Q: When the native visual stops? → A: The warning clears (the app reports false) when the native visual is stopped or a new session starts; projectM does not run the analysis bus, so no warning shows there (spec Assumptions).
- Q: Backend? → A: A portable Double loop on both backends (three multiply-adds per frame, ≤ 2,048 frames per chunk); no vDSP: per-sample non-finite handling and bit-equal results across chunkings matter more than speed at this cost. It builds unchanged in the Linux shape (ANL-013-R4, R10, R11).
- Q (speckit-clarify pass): Stored data or settings? → A: None. A binding stores only `audio.correlation` (older builds orphan it, MOD-013); no scene version bump, no UserDefaults key, no Settings row (ANL-013-R12).
- Q (speckit-clarify pass): Test cost? → A: Fixtures of 1–3 s of audio (≤ 132,300 frames, three multiply-adds each); the new package tests together under 1 s on the host (owner rule 7) (ANL-013-S7).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Identical and inverted stereo read opposite signs (Priority: P1)

A visual author or a performer checking a feed needs a number that says how alike the two channels
are: near +1 when they carry the same signal, near −1 when one is the other upside down, near 0
when they are unrelated.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Package tests feed deterministic stereo PCM fixtures (sine and seeded noise).

**Acceptance Scenarios**:

1. **Given** identical channels (L = R) of a sine or of seeded noise, **When** measured, **Then** correlation > 0.99.
2. **Given** inverted channels (R = −L) of the same signals, **When** measured, **Then** correlation < −0.99, the opposite sign.
3. **Given** independent seeded noise on each channel, **When** measured, **Then** |correlation| < 0.1.

---

### User Story 2 - A sustained phase inversion raises a warning that clears calmly (Priority: P1)

A performer whose feed has one channel wired backwards gets "Stereo channels look phase-inverted"
in the source status and the performance overlay, announced once, and the warning goes away on its
own a little after the problem is fixed, without flickering.

**Why this priority**: It is the row's observable behaviour ("phase inversion warnings").

**Independent Test**: Package tests on a sample clock (no wall clock); an app unit test for the status text and the announcement.

**Acceptance Scenarios**:

1. **Given** an inverted fixture, **When** less than the hold has elapsed, **Then** no warning; **When** the hold has elapsed, **Then** the warning is raised.
2. **Given** a raised warning, **When** the signal returns to identical channels, **Then** the warning clears only after the clear hold, and a brief return above the clear threshold does not clear it.
3. **Given** a raised warning, **When** the app shows the source status, **Then** it reads "… · Stereo channels look phase-inverted" and VoiceOver hears it once through the status-event router.

---

### User Story 3 - Silence, mono and bad input are calm (Priority: P1)

**Acceptance Scenarios**:

1. **Given** digital silence or dither-level noise, **When** measured, **Then** correlation is 0 and no warning.
2. **Given** one silent channel, **Then** correlation is 0.
3. **Given** NaN or ±∞ samples, **Then** the value is finite and in −1…1.
4. **Given** a mono source or an AUD-009 mode other than Mix (L = R), **Then** correlation is 1 and the warning cannot fire.

---

### User Story 4 - The same input reads the same (Priority: P2)

1. **Given** the same PCM, **When** measured twice or in different chunk sizes, **Then** the results are bit-equal.

---

### User Story 5 - Correlation is a modulation source (Priority: P2)

1. **Given** the analysis pipeline fed identical then inverted stereo, **Then** frames carry the correlation and the warning flag.
2. **Given** the native visual with a Correlation binding on the glow, **Then** the glow follows (r + 1)/2, and the inspector names the source "Correlation".

### Edge Cases

- A session restart resets the correlation to 0 and clears the warning.
- Stopping the native visual (or switching to projectM) clears the warning in the app; the stop reports it as cleared, without the X3b announcement unless the raise was announced (covered by T10, T11).
- One loud channel and one silent channel: 0 (no shared signal), never ±1.
- Chunks of any size, including 1 frame: the same blocks and the same values.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-013-R1**: The system MUST compute the correlation of the two channels of the analysis tap's PCM in fixed blocks of samples, in −1…1, smoothed with a short time constant on the sample clock.
- **ANL-013-R2**: When either channel is at or below the silence floor, correlation MUST be 0; non-finite samples count as 0; every value MUST be finite.
- **ANL-013-R3**: A correlation below the raise threshold held for the raise hold MUST raise a phase-inversion warning; it MUST clear only after the correlation stays above a higher clear threshold for the clear hold.
- **ANL-013-R4**: Results MUST be deterministic and independent of how the PCM is split into chunks.
- **ANL-013-R5**: The ANL-016 pipeline MUST carry the correlation and the warning flag in every feature frame; a session start MUST reset both.
- **ANL-013-R6**: MOD-002 MUST offer `audio.correlation` with value (r + 1)/2 in 0…1 (missing or non-finite reads 0), usable in bindings and SHD-009 expressions through a permanent opcode; the inspector MUST name it "Correlation".
- **ANL-013-R7**: The native visual MUST feed the correlation to its bindings and report warning changes to the app.
- **ANL-013-R8**: While the warning is raised, the source status MUST end with "Stereo channels look phase-inverted" and the performance overlay MUST show it; raising it MUST be announced through the status-event router, throttled.
- **ANL-013-R9**: With identical channels (mono, or AUD-009 Left, Right, Mid, Side) the correlation is 1 and the warning MUST NOT fire.
- **ANL-013-R10**: Processing MUST NOT allocate, lock, log, do I/O or read a clock (Constitution VII).
- **ANL-013-R11**: The package code MUST build and pass its tests in the Linux shape (`-DANALYSIS_NO_ACCELERATE`).
- **ANL-013-R12**: Nothing here reaches projectM (Constitution VIII); no new setting, stored key or network.

### Key Entities

- **Correlation configuration**: sample rate, block length, time constant, silence floor, thresholds and holds.
- **Correlation reading**: correlation −1…1, whether both channels were above the floor, whether the warning is raised.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-013-S1**: Identical sine and noise fixtures read > 0.99; inverted ones < −0.99 (opposite signs); independent noise |r| < 0.1 (the roadmap acceptance).
- **ANL-013-S2**: On an inverted fixture the warning is off before the hold and on after it; it clears only after the clear hold, and a short return does not clear it.
- **ANL-013-S3**: Silence, dither, one silent channel and non-finite input read 0 or a finite value in −1…1.
- **ANL-013-S4**: Repeats and different chunkings are bit-equal.
- **ANL-013-S5**: Through the real pipeline, identical frames read > 0.99 and inverted frames < −0.99 and raise the flag.
- **ANL-013-S6**: `audio.correlation` round-trips, binds, compiles to its opcode and drives the glow in the app; the inspector reads "Correlation"; the source status and announcement carry the warning.
- **ANL-013-S7**: The new package tests add well under a second; every existing test passes.

## Assumptions

- The analysis tap stays 44.1 kHz interleaved stereo; the measure is valid at any rate.
- Acceptance is synthetic PCM (unit tests); simulator results are not device evidence. Real feeds (a miswired interface, a phase-flipped track) are device checks.
- The warning is visible only while a native visual (which runs the ANL-016 pipeline) is shown; projectM does not run the analysis bus.
