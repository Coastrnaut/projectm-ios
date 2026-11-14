# Feature Specification: ANL-008 Mid Transient Detector ("snare-like")

**Feature Branch**: `feature/anl-008` (spec directory `137-anl-008-snare-transient`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14

**Input**: User description: "Implement roadmap feature ANL-008, 'Snare-like transient detector'.
Observable behavior, verbatim: 'Estimate mid-band percussive transients with uncertainty.'
Acceptance, verbatim: 'Mid-band impulse triggers event without asserting instrument identity.'
Dependencies: ANL-004 (integrated). Verification: Accelerate/vDSP, deterministic sample clocks;
unit tests with synthetic PCM, plus the simulator. Reuse ANL-004's STFT frames (no second FFT),
mirror the ANL-007 kick detector, expose a MOD-002 binding source, name it without asserting
instrument identity."

Identifiers carry the roadmap ID: requirements `ANL-008-R1…`, success criteria `ANL-008-S1…`,
tasks `ANL-008-T01…`. Other features are cited by their own IDs: ANL-001 (spectra), ANL-002 (bin
weight rule), ANL-004 (spectral flux onsets, `.silence` lead-in, event sample rule), ANL-007 (kick:
the band transient detector this row parameterizes), ANL-016 (analysis event bus), MOD-002 (audio
feature sources and bindings), SHD-009 (expressions that read audio sources).

## Baseline: what exists today (audit of 2026-11-14, commit `e8dde5c0`)

| Area | Today | Gap for this row |
|---|---|---|
| Spectra | ANL-001 `SpectrumStream` (2,048-point Hann, hop 512, 44.1 kHz in the bus); one FFT per frame shared by every detector in `AnalysisPipeline.process`. | None: the new detector reads the same magnitudes. |
| Onsets | ANL-004 `SpectralFluxOnsetDetector`: full-band flux; fires on any drum. | No mid-band decision. |
| Kick | ANL-007 `BandTransientDetector` with `TransientDetectorConfiguration.kick` (40–150 Hz, level flux over the one-window peak, threshold max(9 dB, median + 4·MAD over 1 s), −70 dB floor, −15 dB dominance of the power increase, 100 ms refractory, 100 ms envelope). Its header says ANL-008 adds a `TransientBand` case and a configuration. Bus: `.transient(band:strength:threshold:level:)` events and `AnalysisFrame.kickEnvelope`. | No mid band; events carry no confidence. |
| Modulation | MOD-002 `AudioFeatureSource`: bands, bandMean, onset, beatConfidence, kick, centroid, loudness (SHD-009 opcodes up to 16). App: `NativeSpectrumHost.applyModulation(bands:kick:centroid:loudness:)`, fed from `LiveBandFrameInfo`. | No mid transient source. |
| UI | No source picker exists; bindings come from scenes and the Debug path. | None needed. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the
recommended, conservative option.

- Q: What is the user-facing name, and does the feature claim to find snares? → A: "Mid transient" (code `midTransient`, source ID `audio.midTransient`, band `.midTransient`). It is **not** a snare classifier: it reports percussive energy rising in the mid band, whatever made it (snare, clap, rimshot, a guitar strum, a consonant). Names, docs and comments never call an event a snare. Rejected: "Snare" or "Snare-like" in any user-facing or API name (asserts identity; the roadmap acceptance forbids it) (ANL-008-R1, R10).
- Q: Which frequency range? → A: One band, 1,000–4,000 Hz, with ANL-002's fractional bin weights. That is where a snare's crack, claps and rimshots put most of their attack energy, above the kick (40–150 Hz) and the bass's main harmonics, and below the hi-hat and cymbal range that ANL-009 will cover. Rejected: adding a second "body" band around 150–250 Hz (it overlaps tom, bass and kick harmonics, and would make the decision depend on a snare's body, i.e. on instrument identity; kept simple as the brief asks) (ANL-008-R2).
- Q: Which detector and thresholds? → A: The ANL-007 `BandTransientDetector` unchanged in its decision rule, with a new configuration `.midTransient`: floor −70 dB, dominance −15 dB, baseline 1.0 s, minimum rise 9 dB, k = 4 (median + 4·MAD), refractory 70 ms (allows about 14 hits per second, sixteenth notes at 200 BPM, and suppresses a flam's second stroke and frames of the same hit), envelope time constant 80 ms (a crack is shorter than a kick). Same reasons as ANL-007's: decibel differences are gain-independent; the dominance test rejects a kick or a hi-hat whose leakage raises the mid band a little and the total a lot. Rejected: a new detector type (the kick's design was made to be parameterized) (ANL-008-R3, R4, R5).
- Q: How is uncertainty expressed? → A: Every transient event carries a confidence 0…1 = √(margin · breadth′). Margin = clamp((rise − threshold) / 12 dB, 0, 1): how far above the threshold the event was. Breadth = the band's spectral flatness on the event frame (geometric over arithmetic mean of the in-band bin powers) divided by 0.5 and clamped to 1: noise-like (percussive) attacks read near 1, a tone that starts in the band reads near 0. breadth′ = 1 − w + w · breadth with a per-configuration weight w: 1 for the mid transient, 0 for the kick (so the kick's confidence is only its margin and its behaviour is unchanged). Computed only on event frames, from the band's existing squared magnitudes (no allocation). Rejected: a probability of "snare" (asserts identity), a confidence from the band level (level-dependent) (ANL-008-R6).
- Q: How is it exposed? → A: The bus publishes mid transients as the existing `.transient` event kind with `band: .midTransient`, and the kind gains a `confidence` value for every band. Every feature frame carries `midTransientEnvelope` (1 on an event, decaying with 80 ms) and `midTransientConfidence` (the last event's confidence, held until the next event, 0 after a session start); their product is `AnalysisFrame.midTransient`. MOD-002 gets the source "Mid transient", ID `audio.midTransient`, which reads that product (so an uncertain event drives a binding weakly); SHD-009 gets opcode 17. The native visual feeds it to its bindings like the kick. Rejected: a separate confidence source (one more opcode and source for no user need in this row), a status or diagnostics overlay entry (optional in the brief; no overlay lists analysis features today) (ANL-008-R7 to R9).
- Q: What does it cost? → A: No new FFT: the detector reads the magnitudes the pipeline already computed, like the kick, the centroid and the loudness (ANL-008-R11).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Mid-band hits fire, with a confidence (Priority: P1)

A visual author binds a parameter to "Mid transient". When a crack-like hit sounds in the mid band,
the parameter jumps by the hit's confidence and decays.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Package tests feed synthetic bursts (deterministic sample clock, fixed seeds)
through the detector and the analysis pipeline.

**Acceptance Scenarios**:

1. **Given** mid-band noise bursts centred near 2 kHz at known, hop-aligned times, **When** analysed, **Then** exactly one mid transient event is reported per burst, within one hop of its start, each with confidence at least 0.5, and the event names only the band (never an instrument).
2. **Given** the same bursts at −30 and −6 dBFS, **When** analysed, **Then** the event positions are identical.

---

### User Story 2 - Kicks, tones and silence do not fire (Priority: P1)

**Why this priority**: False mid transients make a visual flash on the wrong material.

**Independent Test**: Low-only kick bursts, steady tones, silence and two bursts inside the
refractory period.

**Acceptance Scenarios**:

1. **Given** a low-only kick (60 Hz decaying sine bursts), **When** analysed, **Then** no mid transient event is reported, or any event has confidence below 0.5.
2. **Given** a steady 2 kHz tone (after its onset), digital silence or dither, **When** analysed, **Then** no event is reported (at most one at a tone's onset, never afterwards).
3. **Given** two bursts closer than 70 ms, **When** analysed, **Then** only the first is reported; bursts farther apart are both reported.
4. **Given** the same input twice, **When** analysed by two fresh detectors, **Then** the events are identical.

---

### User Story 3 - Mid transient is a modulation source (Priority: P2)

**Independent Test**: ParameterGraph tests (ID round-trip, value, binding, expression) and an app
unit test in which a Mid transient binding on the native visual drives its target.

**Acceptance Scenarios**:

1. **Given** the ID `audio.midTransient`, **When** parsed, bound or used in an expression, **Then** it reads the frame's mid transient value (0…1; missing or non-finite reads 0).
2. **Given** the native visual with a Mid transient binding on the glow, **When** frames carry a mid transient value, **Then** the glow follows it.

### Edge Cases

- A tonal attack in the band (a 2 kHz sine burst) may fire, with a low confidence (breadth near 0); it is not promised either way.
- A broadband click (energy across the whole spectrum) fires: the band holds about −9 dB of a flat increase, above the −15 dB dominance limit. It is a mid-band transient by this definition.
- A session restart resets the detector, its held confidence and its envelope.
- Frames at another rate, with a wrong magnitude count or not contiguous are ignored or only re-establish the baseline (ANL-007's rules).
- Non-finite magnitudes read as silence; confidence is always finite and within 0…1.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-008-R1**: The feature MUST be named "Mid transient" everywhere a user or scene sees it, and MUST NOT claim instrument identity in names, events or docs.
- **ANL-008-R2**: The detector MUST measure the 1,000–4,000 Hz band with ANL-002's fractional bin weights, for every ANL-001 FFT size.
- **ANL-008-R3**: It MUST be ANL-007's band transient detector with its own configuration (`.midTransient`), so its decisions are level-independent above the −70 dB floor, use an adaptive threshold max(9 dB, median + 4·MAD of the preceding 1.0 s), and require the −15 dB dominance of the frame's power increase.
- **ANL-008-R4**: After an event it MUST report nothing for 70 ms and MUST re-arm only after the rise falls to or below the threshold.
- **ANL-008-R5**: Its envelope MUST be 1 on an event and decay with an 80 ms time constant.
- **ANL-008-R6**: Every transient event MUST carry a finite confidence in 0…1 = √(margin · breadth′) as defined in Clarifications; the kick's confidence weight for breadth is 0, so its events, positions and envelope are unchanged.
- **ANL-008-R7**: The ANL-016 pipeline MUST run the mid transient detector on every spectrum frame after the kick, publish each event as `.transient(band: .midTransient, …, confidence:)` in ID order after the kick, carry `midTransientEnvelope` and `midTransientConfidence` in every feature frame, and reset both on a session start.
- **ANL-008-R8**: MOD-002 MUST offer the source "Mid transient" with stable ID `audio.midTransient`, reading the frame's envelope × confidence (missing or non-finite reads 0), usable in bindings, scenes and SHD-009 expressions (opcode 17).
- **ANL-008-R9**: The app's native visual MUST feed the mid transient value to its bindings.
- **ANL-008-R10**: Events MUST carry timestamps on the stream's sample clock (ANL-004's rule: the first sample of the frame's newest hop) and no wall-clock reading.
- **ANL-008-R11**: The detector MUST reuse the pipeline's existing spectrum (no second FFT) and MUST NOT allocate, lock, log or do I/O per frame (Constitution VII).
- **ANL-008-R12**: It MUST build and pass its tests in the package's Linux shape (`-DANALYSIS_NO_ACCELERATE`).
- **ANL-008-R13**: Nothing computed here reaches projectM (Constitution VIII); no new setting, no stored data beyond a scene binding's source ID, no network, no UI.

### Key Entities

- **Transient band**: `kick` or `midTransient`.
- **Transient detector configuration**: ANL-007's fields plus the confidence's breadth weight.
- **Transient event**: ANL-007's fields plus confidence.
- **Mid transient value**: envelope × held confidence, 0…1, per feature frame.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-008-S1**: Mid-band bursts fire once each, within one hop of the burst start, with confidence ≥ 0.5; no extras (the roadmap acceptance).
- **ANL-008-S2**: The same bursts at −30 and −6 dBFS give identical positions.
- **ANL-008-S3**: Low-only kick bursts give no event with confidence ≥ 0.5; steady tones fire at most once at onset; silence and dither fire zero times; a burst inside 70 ms of the previous one is not reported.
- **ANL-008-S4**: Two runs on the same input give identical events.
- **ANL-008-S5**: Through the pipeline, mid bursts yield one `.midTransient` event each with confidence, and frames whose mid transient value jumps on each event and decays; every existing kick test still passes unchanged.
- **ANL-008-S6**: `audio.midTransient` round-trips, binds, compiles to opcode 17 and drives a bound parameter in the app.
- **ANL-008-S7**: The new package tests take under 2 s in the Linux shape; existing suites pass.

## Implementation results (2026-11-14)

Fixture table (`MidTransientDetectorTests`, 2,048-point spectra, hop 512, 44.1 kHz, `.midTransient`
defaults; identical on the host and in the Linux shape):

| Input | Bursts | Events | Hits (±1 hop) | Extras | Confidences |
|---|---|---|---|---|---|
| Mid-band noise bursts (≈ 1–3 kHz), −12 dBFS | 4 | 4 | 4 | 0 | 1.00, 1.00, 1.00, 0.97 |
| Same, −6 dBFS (same positions) | 4 | 4 | 4 | 0 | 1.00, 1.00, 1.00, 0.97 |
| Same, −30 dBFS (same positions) | 4 | 4 | 4 | 0 | 0.74, 0.84, 0.79, 0.83 |
| 60 Hz kick bursts, −6 dBFS | 4 | 0 | — | 0 | — |
| 2 kHz steady tone, −12 dBFS | 1 onset | 1 (at the onset) | 1 | 0 | 0.37 (below 0.5) |
| Silence / ±1 LSB dither | 0 | 0 / 0 | — | 0 | — |
| Two bursts 46 ms / 128 ms apart | 2 / 2 | 1 / 2 | — | 0 | — |
| Through `AnalysisPipeline`, −12 dBFS | 3 | 3 `.transient(band: .midTransient)` | 3 (exact starts) | 0 | ≥ 0.5 |

Event positions are level-independent; the confidence is not entirely: at −30 dBFS it is lower
(0.74–0.84) than at −12 dBFS, still above the 0.5 acceptance threshold. Kick events are unchanged
(every ANL-007 test passes; the kick's confidence is its margin alone).

Test cost (owner rule 7): MidTransientDetectorTests (6 tests) take 0.27 s on the host and 0.75 s in
the Linux shape; the AnalysisFeatures host suite has 150 tests (42.1 s). App: the new binding test
takes 0.02 s on the simulator. No UI, status or diagnostics overlay entry was added (Clarifications).

## Assumptions

- The bus keeps 2,048-point spectra, hop 512, 44.1 kHz; defaults are valid for every ANL-001 size.
- "Mid transient" means percussive energy rising in 1–4 kHz; no instrument identity is claimed.
- Simulator results are not device evidence; acceptance is synthetic PCM in unit tests, plus the app's unit test run on the simulator.
