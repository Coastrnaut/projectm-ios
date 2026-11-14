# Feature Specification: ANL-009 High-Frequency Transient Detector

**Feature Branch**: `feature/anl-009` (spec directory `162-anl-009-high-transient`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement roadmap feature ANL-009, 'High-frequency transient detector'.
Observable behavior, verbatim: 'Track high-band bursts for sparkle and particle triggers.'
Acceptance, verbatim: 'Synthetic high-band clicks produce bounded event counts.' P2, M, depends on
ANL-002. Mirror ANL-008 exactly (a `TransientBand` case and a configuration of ANL-007's
`BandTransientDetector`), add an explicit maximum event rate, name it 'High transient' without
claiming a hi-hat, expose `audio.highTransient` with SHD-009 opcode 18, and name it in the
inspector."

Identifiers carry the roadmap ID: requirements `ANL-009-R1…`, success criteria `ANL-009-S1…`,
tasks `ANL-009-T01…`, research decisions `ANL-009-D1…`. Other features are cited by their own IDs:
ANL-001 (spectra), ANL-002 (bin weight rule), ANL-004 (event sample rule, `.silence` lead-in),
ANL-007 (kick: the band transient detector), ANL-008 (mid transient and the event confidence),
ANL-016 (analysis event bus), MOD-002 (audio feature sources and bindings), SHD-009 (expressions),
UIX-003 (parameter inspector names).

## Baseline: what exists today (audit of 2026-11-14, commit `0d19488e`)

| Area | Today | Gap for this row |
|---|---|---|
| Spectra | ANL-001 `SpectrumStream` (2,048-point Hann, hop 512, 44.1 kHz in the bus); one FFT per frame shared by every detector in `AnalysisPipeline.process`. | None: the new detector reads the same magnitudes. |
| Band transients | ANL-007 `BandTransientDetector`, configured as `.kick` (40–150 Hz) and, since ANL-008, `.midTransient` (1–4 kHz, 70 ms refractory, 80 ms envelope, confidence √(margin · breadth′)). Bus: `.transient(band:strength:threshold:level:confidence:)`, `AnalysisFrame.midTransientEnvelope/Confidence/midTransient`. | No high band; no limit on how many events a band may report per second. |
| Modulation | MOD-002 `AudioFeatureSource`: bands, bandMean, onset, beatConfidence, kick, centroid, loudness, midTransient (SHD-009 opcodes up to 17; 18 and 19 free on every branch). App: `NativeSpectrumHost.applyModulation(…midTransient:…)` fed from `LiveBandFrameInfo`; UIX-003 `AudioFeatureSource.inspectorName` (exhaustive switch). | No high transient source. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the
recommended, conservative option.

- Q: What is the user-facing name, and does the feature claim to find hi-hats? → A: "High transient" (code `highTransient`, source ID `audio.highTransient`, band `.highTransient`). It is **not** a hi-hat or cymbal classifier: it reports percussive energy rising in the high band, whatever made it (hats, shakers, tambourine, a sibilant, a vinyl crackle, a synth click). Rejected: "Hi-hat", "Sparkle" or "Cymbal" in any API or user-facing name (identity claims, or a visual term for an audio feature) (ANL-009-R1).
- Q: Which frequency range? → A: 6,000–16,000 Hz, ANL-002 fractional bin weights. Starting at 6 kHz leaves a 2 kHz gap above ANL-008's 4 kHz so a mid-band hit's upper tail rarely fires both; stopping at 16 kHz ignores the band many lossy encoders cut and keeps the band valid down to a 32 kHz stream. Rejected: 5 kHz to Nyquist (overlaps sibilance and the mid band's tail, and the top octave is often empty or encoder noise) (ANL-009-R2).
- Q: Which thresholds? → A: ANL-007's decision rule unchanged, configuration `.highTransient`: floor −70 dB, baseline 1.0 s, minimum rise 9 dB, k = 4, refractory **40 ms** (hats are fast; still suppresses frames of the same hit), envelope **50 ms** (a click is short), breadth weight 1 and margin 12 dB (ANL-008's confidence). **Dominance −6 dB** instead of −15 dB: the band must hold at least a quarter of the frame's power increase. Found while implementing: with −15 dB, ANL-008's mid-band noise bursts (whose one-pole spectrum still puts about −10 dB of their increase above 6 kHz) fired confidently; with −6 dB they do not, while high-pass clicks (band share about −2 dB) and broadband clicks (about −3.4 dB) still fire (ANL-009-R3).
- Q: How is the event count bounded? → A: An explicit **event-rate cap**, a new configuration field `maximumEventsPerSecond` (0 = no cap, at most 64): a frame that passes every other test fires only if fewer than N events lie in the preceding 1 s span (sample − rate, sample]; otherwise it is suppressed like a refractory frame (disarmed, no event, no envelope change) and counted in `rateLimitedEvents`. So no 1 s span ever holds more than N events. **N = 12** for the high transient (sixteenth notes up to 180 BPM pass untouched; a cymbal wash, noise or dense rolls cannot flood sparkle triggers); 0 for the kick and the mid transient, which stay unchanged. Rejected: a longer refractory period (83 ms would block fast fills that the cap still lets through in bursts), a token bucket (harder to state as a bound) (ANL-009-R4).
- Q: How is it exposed? → A: Exactly as ANL-008: `.transient(band: .highTransient, …, confidence:)` events published after the mid transient; `AnalysisFrame.highTransientEnvelope`, `highTransientConfidence` and their product `highTransient`; MOD-002 source "High transient", ID `audio.highTransient`, reading the product; SHD-009 opcode **18** (checked on every feature branch: none uses 18; MOD-007's LFO source added no opcode); `LiveBandFrameInfo.highTransient` feeds the native visual; UIX-003's inspector names it "High transient". No new UI, setting or overlay (ANL-009-R5 to R9).
- Q: What does it cost? → A: One more band sum per frame on the existing magnitudes (about 465 bins at N = 2,048) and the flatness only on event frames; no second FFT (ANL-009-R10).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - High-band clicks fire (Priority: P1)

A visual author binds sparkles or a particle burst to "High transient". Each crisp high click
triggers once, with a confidence, and decays.

**Why this priority**: It is the behaviour the row exists for.

**Independent Test**: Package tests feed synthetic high-pass filtered noise clicks at known,
hop-aligned times through the detector and through the analysis pipeline.

**Acceptance Scenarios**:

1. **Given** high-pass filtered noise clicks at known times, **When** analysed, **Then** exactly one high transient event is reported per click, within one hop of its start, with confidence at least 0.5, naming only the band.
2. **Given** the same clicks at −30 and −6 dBFS, **When** analysed, **Then** the event positions are identical.

---

### User Story 2 - Event counts stay bounded (Priority: P1)

**Why this priority**: It is the roadmap acceptance: dense high-band material must not flood the
triggers.

**Independent Test**: Dense clicks, fast clicks and continuous high-band noise.

**Acceptance Scenarios**:

1. **Given** clicks at 50 per second for 3 s, **When** analysed (bus geometry and the finest geometry), **Then** no 1 s span holds more than 12 events and the run holds at most 36.
2. **Given** clicks at 20 per second that an uncapped detector follows (more than 12 in a second), **When** analysed with the cap, **Then** some 1 s span holds exactly 12, none holds more, the suppressed events are counted, and every reported event is one the uncapped detector also reported.
3. **Given** 10 s of continuous high-band noise, **When** analysed, **Then** no 1 s span holds more than 12 events and the run holds at most 120 (the explicit bound).

---

### User Story 3 - Low and mid material does not fire; timing rules hold (Priority: P1)

**Acceptance Scenarios**:

1. **Given** 60 Hz kick bursts or ANL-008's 2 kHz mid-band noise bursts, **When** analysed, **Then** no high transient event with confidence ≥ 0.5 is reported.
2. **Given** silence or ±1 LSB dither, **Then** no event and a zero envelope.
3. **Given** two clicks 35 ms apart, **Then** one event (two when the refractory period is 0); clicks 93 ms apart give two.
4. **Given** the same input twice, **When** analysed by two fresh detectors, **Then** the events and envelopes are identical.

---

### User Story 4 - High transient is a modulation source (Priority: P2)

**Acceptance Scenarios**:

1. **Given** the ID `audio.highTransient`, **When** parsed, bound or used in an expression, **Then** it reads the frame's high transient value (0…1; missing or non-finite reads 0) and compiles to opcode 18.
2. **Given** the native visual with a High transient binding on the glow, **When** frames carry a high transient value, **Then** the glow follows it, and the inspector names the source "High transient".

### Edge Cases

- A broadband click fires (the band holds about −3.4 dB of a flat increase, above −6 dB): it is a high-band transient by this definition.
- At 2,048-point spectra and hop 512 the level reference spans four frames, so evenly spaced clicks closer than about 7 hops (≈ 81 ms) re-fire rarely; the cap matters most at finer geometries and for irregular dense material.
- A suppressed (rate-capped) frame disarms the detector exactly as a refractory frame does; it neither sets the envelope nor changes the held confidence.
- A session restart resets the detector, its rate window, its held confidence and its envelope.
- Non-finite magnitudes read as silence; the confidence is always finite and within 0…1.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-009-R1**: The feature MUST be named "High transient" wherever a user or scene sees it, and MUST NOT claim instrument identity in names, events or docs.
- **ANL-009-R2**: The detector MUST measure the 6,000–16,000 Hz band with ANL-002's fractional bin weights, for every ANL-001 FFT size.
- **ANL-009-R3**: It MUST be ANL-007's band transient detector with its own configuration (`.highTransient`: floor −70 dB, dominance −6 dB, threshold max(9 dB, median + 4·MAD over 1.0 s), refractory 40 ms, envelope 50 ms, ANL-008's confidence with breadth weight 1).
- **ANL-009-R4**: A configuration MUST be able to cap its event rate: with `maximumEventsPerSecond` N > 0, no span (sample − rate, sample] ever holds more than N events; suppressed frames are counted and otherwise behave like refractory frames. The high transient's N is 12; the kick's and the mid transient's is 0 (unchanged behaviour).
- **ANL-009-R5**: Its envelope MUST be 1 on an event and decay with a 50 ms time constant; every event carries ANL-008's confidence.
- **ANL-009-R6**: The ANL-016 pipeline MUST run the high transient detector on every spectrum frame after the mid transient, publish each event as `.transient(band: .highTransient, …)` in ID order after the mid transient's, carry `highTransientEnvelope` and `highTransientConfidence` in every feature frame, and reset them on a session start.
- **ANL-009-R7**: Events MUST carry timestamps on the stream's sample clock (ANL-004's rule) and no wall-clock reading.
- **ANL-009-R8**: MOD-002 MUST offer the source "High transient" with stable ID `audio.highTransient`, reading envelope × confidence (missing or non-finite reads 0), usable in bindings, scenes and SHD-009 expressions (opcode 18).
- **ANL-009-R9**: The app's native visual MUST feed the high transient value to its bindings, and the parameter inspector MUST name the source "High transient".
- **ANL-009-R10**: The detector MUST reuse the pipeline's existing spectrum (no second FFT) and MUST NOT allocate, lock, log or do I/O per frame (Constitution VII); the rate window is preallocated.
- **ANL-009-R11**: It MUST build and pass its tests in the package's Linux shape (`-DANALYSIS_NO_ACCELERATE`).
- **ANL-009-R12**: Nothing computed here reaches projectM (Constitution VIII); no new setting, no stored data beyond a scene binding's source ID, no network, no UI beyond the inspector's name.

### Key Entities

- **Transient band**: `kick`, `midTransient` or `highTransient`.
- **Transient detector configuration**: ANL-007/008's fields plus `maximumEventsPerSecond`.
- **High transient value**: envelope × held confidence, 0…1, per feature frame.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-009-S1**: High-band clicks fire once each within one hop with confidence ≥ 0.5, no extras; identical positions at −30, −12 and −6 dBFS.
- **ANL-009-S2** (roadmap acceptance): dense clicks at 50/s, fast clicks at 20/s and 10 s of continuous high-band noise never give more than 12 events in any 1 s span, and 10 s of noise gives at most 120 events.
- **ANL-009-S3**: The cap is exercised: on 20/s clicks the uncapped detector reports more than 12 in a second, the capped one exactly 12, and capped + suppressed = uncapped.
- **ANL-009-S4**: Kick and mid-band bursts give no event with confidence ≥ 0.5; silence and dither none; the refractory period suppresses a click 35 ms after another; two runs are identical.
- **ANL-009-S5**: Through the pipeline, clicks yield one `.highTransient` event each and frames whose high transient value jumps and decays; every existing kick and mid transient test passes unchanged.
- **ANL-009-S6**: `audio.highTransient` round-trips, binds, compiles to opcode 18, drives the glow in the app and is named "High transient" in the inspector.
- **ANL-009-S7**: The new package tests take under 5 s in the Linux shape; existing suites pass.

## Assumptions

- The bus keeps 2,048-point spectra, hop 512, 44.1 kHz; defaults are valid for every ANL-001 size.
- "High transient" means percussive energy rising in 6–16 kHz; no instrument identity is claimed.
- Simulator results are not device evidence; acceptance is synthetic PCM in unit tests, plus the app's unit test run on the simulator.
