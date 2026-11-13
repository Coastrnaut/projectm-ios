# Feature Specification: ANL-004 Spectral Flux Onset Detector

**Feature Branch**: `feature/anl-004` (spec directory `018-anl-004-spectral-flux-onset-detector`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement ANL-004 (Spectral flux onset detector) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Detect positive changes in
spectral energy." Acceptance, verbatim: "Impulse train produces onset events within one analysis
hop and no false silence events." Dependencies: ANL-001 (integrated); AUD-016 hand-off: identical
outputs on repeated runs. Honor the repository constitution, VIII and ADR-0008 decision 5."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `ANL-004-R1…`, success criteria `ANL-004-S1…`, tasks `ANL-004-T01…`. ANL-001's
requirements (`specs/014-anl-001-windowed-fft/spec.md`), ANL-002's
(`specs/016-anl-002-log-frequency-bands/spec.md`) and AUD-016's hand-off (AUD-016-R22: identical
outputs on repeated runs) stay in force; this feature cites them and adds to them.

## Baseline: what exists today (audit of 2026-11-13, commit `1d74d3d`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Spectrum | `Packages/AnalysisFeatures` (ANL-001) frames a stream into overlapping Hann-windowed magnitude spectra; each frame carries the index of its first sample on a deterministic sample clock. | A frame does not say how far it advanced from the previous one (its hop), and a stream's first window starts at the first input sample, so a sound at sample 0 sits under the window's silent edge and is never seen at full weight. |
| Bands | ANL-002 reduces a spectrum to 16, 32, 64 or 128 logarithmic bands with sine-equivalent amplitudes and a decibel normalization with a floor. | Nothing compares one frame with the next. |
| Onsets | No onset, transient or beat detection exists in `Packages/`. projectM detects beats internally and exposes nothing (ADR-0008 decision 5). | ANL-005 (beat tracker), ANL-006 (tempo confidence), ANL-008 (snare-like transients), VIS-008 (particle fountain) and MOD-006 (threshold trigger) need discrete, timestamped onset events. |
| Fixtures | AUD-016 publishes `pulse-120`, `pulse-120-accent` and `pulse-132` with exact onset frames at 44.1 and 48 kHz, plus sines, sweeps and silence; its hand-off asks for identical beat outputs on repeated runs. | Nothing checks an onset detector against them. |

## User Scenarios & Testing *(mandatory)*

The "users" of this row are the later analysis, modulation and visual features and the developers
and CI that check them. Nothing in the app changes visibly.

### User Story 1 - Every click of a pulse train becomes one onset at the right time (Priority: P1)

A developer building a beat tracker or a particle visual feeds the analysis a train of short
clicks. Every click produces exactly one onset event, each event says at which sample the click
happened to within one analysis hop, and no event appears where there is no click.

**Why this priority**: It is the roadmap row's acceptance ("Impulse train produces onset events
within one analysis hop").

**Independent Test**: Run the AUD-016 pulse fixtures (`pulse-120`, `pulse-120-accent`,
`pulse-132`) through the spectrum stream and the detector at every FFT size, several hops and both
catalog rates, and match the event sample indices against the catalog's onset frames.

**Acceptance Scenarios**:

1. **Given** any pulse fixture, any FFT size, a hop of one half, one quarter or one eighth of the size and either catalog rate, **When** one loop is analysed from the start of the stream, **Then** each catalog onset is matched by exactly one event whose sample index differs from the onset by at most one hop, and no event is left unmatched.
2. **Given** the accented fixture (beat 1 of 4 at full level, the others at half), **When** it is analysed the same way, **Then** no weak beat is missed.
3. **Given** a quieter pulse train (2 ms pulses at a peak of −20 dBFS) or a train of single-sample unit impulses at a spacing that is not a whole number of hops, **When** analysed with a hop of one half or one quarter of the size, **Then** every pulse is matched within one hop and nothing else is reported.

---

### User Story 2 - Silence and near-silence never produce onsets (Priority: P1)

A visual driven by onsets must stay still when nothing plays, and must not twitch on hiss or
dither while the music is paused.

**Why this priority**: The second half of the roadmap acceptance ("no false silence events").

**Independent Test**: Run the AUD-016 silence fixture and seeded noise far below the silence
floor through every size, hop and rate and count events; also feed all-zero spectra directly.

**Acceptance Scenarios**:

1. **Given** digital silence, **When** analysed at any size, hop and rate, **Then** there are zero events and the detection value is exactly zero on every frame.
2. **Given** seeded noise whose energy stays below the silence floor in every band, **When** analysed, **Then** there are zero events and the detection value is exactly zero on every frame.
3. **Given** a click followed by silence, **When** the sound stops, **Then** the end of a sound produces no event (only increases count).

---

### User Story 3 - Steady and gliding tones are not onsets (Priority: P1)

A steady tone or a sweep changes its spectrum continuously but has no new attack. A particle
fountain fed by such a signal must not fire on every frame.

**Why this priority**: "Detect positive changes in spectral energy" must mean attacks, not any
change; a sweep is not an onset.

**Independent Test**: Run every AUD-016 sine and sweep fixture through every size, hop and rate and
count events.

**Acceptance Scenarios**:

1. **Given** a sine or sweep fixture that starts at sample 0 from silence, **When** one loop is analysed, **Then** exactly one event is reported, for the start of the sound, within one hop of sample 0, and none afterwards.
2. **Given** loud steady white noise, **When** analysed, **Then** the number of events is bounded as documented per FFT size (the start plus at most a stated number of spurious events).

---

### User Story 4 - Same events on every run and every CI path (Priority: P2)

CI runs on macOS, the iOS Simulator and Linux. Event lists repeat exactly, and the accelerated and
portable paths report the same events.

**Why this priority**: AUD-016's hand-off ("identical beat outputs on repeated runs") and the CI
history of this repository.

**Independent Test**: Analyse each fixture twice and compare the event lists exactly; analyse it
with each path and compare.

**Acceptance Scenarios**:

1. **Given** any fixture and configuration, **When** analysed twice with the same path, **Then** the two event lists are identical in every field.
2. **Given** the same input analysed by the accelerated and the portable path, **When** the event lists are compared, **Then** they have the same events at the same sample indices with the same sequence numbers, and strengths agree within a stated tolerance.

---

### User Story 5 - Events a later feature can consume (Priority: P2)

A beat tracker needs the continuous detection value as well as the events; a particle fountain
needs a strength; an event bus needs a number that never repeats, even after the stream restarts.

**Why this priority**: ANL-005, ANL-016, VIS-008 and MOD-006 depend on this row's output shape.

**Independent Test**: Process frames, reset, process again; inspect events and the per-frame
detection value and threshold.

**Acceptance Scenarios**:

1. **Given** a detector, **When** events are reported, **Then** each carries a sequence number greater than every earlier one from that detector (also across a reset), the sample index of the onset, the index of the frame that produced it, a strength and the threshold it crossed, and the frame's timestamp.
2. **Given** any processed frame, **When** the detector is inspected, **Then** the latest detection value and threshold are available whether or not an event fired.

### Edge Cases

- The first frame after creation or reset is compared with silence, so a sound that is already playing when analysis starts produces one onset (the start of the sound).
- A gap or restart in the frame sequence (a frame whose index is not the previous index plus the previous hop), or a change of FFT size: that frame only re-establishes the reference; it produces no event and no detection value.
- A frame at a sample rate other than the detector's, or with a magnitude count that does not match its size: ignored and counted; the next accepted frame re-establishes the reference.
- Non-finite or negative magnitudes: treated as zero (inherited from ANL-002-R7); the detection value is always finite and in 0…1.
- Several onsets closer together than the minimum inter-onset interval: only the first is reported.
- A long rising sound whose detection value stays above the threshold for several frames: one event, at its first frame; the detector re-arms only after the value falls back to the threshold or below.
- Very loud input: the detection value is bounded (0…1) whatever the level.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-004-R1**: The system MUST compute, for every accepted spectrum frame, a detection value: the half-wave-rectified spectral flux, i.e. the mean over the bands of the positive part of each band's increase since the previous frame, on band values that are logarithmically compressed and floored as defined in ANL-004-R2. Decreases MUST contribute nothing.
- **ANL-004-R2**: The flux MUST be computed on ANL-002 log-frequency bands (default 64), each mapped to 0…1 by ANL-002's decibel normalization with the detector's silence floor (default −70 dBFS): a band at or below the floor reads exactly 0, a full-scale sine reads 1. The detection value is therefore in 0…1.
- **ANL-004-R3**: The silence floor MUST be absolute: any frame whose bands are all at or below the floor has a detection value of exactly 0 and cannot produce an event, whatever happened before.
- **ANL-004-R4**: The threshold for a frame MUST be `offset + multiplier × mean of the detection values of the preceding frames within the threshold window`, with defaults offset 0.06, multiplier 1.5 and window 0.1 s (converted to frames with the current hop, at least 1 and at most 128 frames). With no preceding frames the mean is 0.
- **ANL-004-R5**: An event MUST be reported for a frame when its detection value exceeds its threshold, the detector is armed, and at least the minimum inter-onset interval (default 0.05 s) has passed since the previous event's sample index. Any frame above its threshold disarms the detector; a frame at or below its threshold re-arms it. At most one event is reported per frame.
- **ANL-004-R6**: An event's sample index MUST be the first sample of the frame's newest hop: `frame index + FFT size − hop`. With the lead-in of ANL-004-R7, a sound that first appears in a frame lies within that frame's newest hop, and one that first exceeds the threshold one frame later lies within the hop before; either way the index is within one hop of the true onset.
- **ANL-004-R7**: The spectrum stream MUST offer an opt-in lead-in that starts the stream (at creation and after reset) as if preceded by `FFT size − hop` samples of silence, so that every input sample, including sample 0, is seen in the same number of windows as any other; frame indices then start at `−(FFT size − hop)`. Without the opt-in, the stream behaves exactly as before.
- **ANL-004-R8**: Every spectrum frame MUST carry its hop (the number of samples between its first sample and the next frame's), so a consumer can locate a frame's newest samples and detect gaps without knowing the stream's configuration. Existing frame construction keeps working with a default hop of half the size.
- **ANL-004-R9**: Each event MUST carry: a sequence number that starts at 1 and increases by 1 with every event of the detector's lifetime (never reused, not restarted by a reset), the onset sample index, the producing frame's index, the strength (the frame's detection value), the threshold it crossed, the sample rate and the frame's timestamp.
- **ANL-004-R10**: The detector MUST expose a pull interface only: processing one frame returns at most one event; the latest detection value and threshold, and counts of processed and ignored frames, are readable. No subscription, queue or event bus is part of this row (ANL-016's).
- **ANL-004-R11**: Reset MUST restore the initial state (reference = silence, empty threshold history, armed, no previous event) while keeping the sequence counter.
- **ANL-004-R12**: A frame that does not follow its predecessor (index ≠ previous index + previous hop) or changes the FFT size MUST only re-establish the reference (no detection value, no event, not added to the threshold history). A frame at another sample rate or with a wrong magnitude count MUST be ignored and counted, and the next accepted frame re-establishes the reference.
- **ANL-004-R13**: The configuration (sample rate, band count, floor, offset, multiplier, window, minimum inter-onset interval) MUST be validated at creation; invalid values MUST be rejected with an error naming the field.
- **ANL-004-R14**: Processing a frame MUST NOT allocate, lock, log or do I/O after creation (Constitution VII); all buffers and band tables are created with the detector. The detector is confined to the one worker that owns it, like the analyser (ANL-001-R14).
- **ANL-004-R15**: Processing the same frames with the same configuration and path MUST give identical event lists and detection values on repeated runs (AUD-016-R22). The detector MUST work without the platform's accelerated math library through a portable path with the same interface; both paths MUST report identical event lists (count, sample indices, frame indices, sequence numbers) on every acceptance input, with strengths within 1e-4.
- **ANL-004-R16**: Nothing computed here MAY be passed to projectM (Constitution VIII, ADR-0008 decision 5); no UI is added by this row.
- **ANL-004-R17**: The acceptance tests MUST cover the three AUD-016 pulse fixtures × the five FFT sizes × hops of N/2, N/4 and N/8 × both catalog rates on every available path, match events to the catalog's onset frames with a tolerance of one hop, and print the acceptance matrix (fixture, size, hop, rate: onsets, events, misses, false events, largest timing error).

### Key Entities

- **Onset detector configuration**: sample rate, band count, silence floor, threshold offset, multiplier and window, minimum inter-onset interval.
- **Onset detector**: the band reducer of its sample rate, the previous frame's normalized bands, the threshold history, arming state, last event, sequence counter, latest detection value and threshold.
- **Onset event**: sequence number, onset sample index, frame index, strength, threshold, sample rate, timestamp.
- **Spectrum frame** (extended): first-sample index (may be negative during a lead-in), hop, size, sample rate, timestamp.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-004-S1**: In 100 % of the 90 pulse combinations (3 fixtures × 5 sizes × 3 hops × 2 rates), on every available path, every catalog onset is matched by one event within one hop, with 0 misses and 0 unmatched events.
- **ANL-004-S2**: 0 events and a detection value of exactly 0 on every frame for silence and for the below-floor noise, in every size, hop and rate tested.
- **ANL-004-S3**: Every sine and sweep fixture produces exactly 1 event (the start, within one hop of sample 0) per loop in every size, hop and rate tested; loud steady noise stays within the documented per-size bound.
- **ANL-004-S4**: The −20 dBFS pulse train and the unit single-sample impulse train are matched 100 % within one hop with 0 unmatched events at hops N/2 and N/4, every size and both rates.
- **ANL-004-S5**: Repeated runs give identical event lists (0 differing fields); the two paths give identical event lists on every acceptance input and strengths within 1e-4.
- **ANL-004-S6**: 0 heap allocations while processing frames after setup, checked by reading the per-frame code; the host per-frame cost is reported (never asserted).
- **ANL-004-S7**: Existing behavior unchanged: every existing AnalysisFeatures and AudioCore test passes unchanged; a stream without the lead-in produces the same frames as before.

## Hand-off to ANL-005, ANL-006, ANL-008, ANL-016, VIS-008 and MOD-006

- ANL-005 (beat tracker) and ANL-006 (tempo confidence) read the per-frame detection value as their onset-strength signal and the events' sample indices as onset times; intervals between sample indices are exact on the sample clock.
- ANL-008 (snare-like transients) can build a band-limited detector from the same configuration (band count and floor) or reuse the event timing rule (ANL-004-R6).
- ANL-016 (event bus) wraps `process` on its worker, stamps events on its monotonic clock and keeps IDs unique across source restarts; the detector's sequence never repeats within its lifetime.
- VIS-008 (particle fountain) spawns from events and scales by strength (0…1).
- MOD-006 (threshold trigger) may reuse the arming rule (ANL-004-R5) for its own debounced triggers.
- Every later row keeps ANL-004-R16: nothing goes into projectM.

## Assumptions

- Input spectra come from ANL-001 (`SpectrumStream`) with its normalization and periodic Hann window; band values come from ANL-002 at the detector's sample rate.
- The normalized stream is 44.1 kHz; fixtures are also checked at 48 kHz. One detector serves one sample rate.
- The catalog's "impulse train" is the AUD-016 pulse trains (2 ms rectangular pulses), which are the fixtures it hands to ANL-004; a single-sample unit impulse train is checked as well.
- No new third-party dependencies, no stored data, no network use, no entitlement: the privacy policy and manifest do not change.
- Device measurements are not needed for this row's acceptance.
