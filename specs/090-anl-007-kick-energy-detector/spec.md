# Feature Specification: ANL-007 Kick Energy Detector

**Feature Branch**: `feature/anl-007` (spec directory `090-anl-007-kick-energy-detector`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13

**Input**: User description: "Implement ANL-007 (Kick energy detector) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Identify low-frequency
transient events independently of overall level." Acceptance, verbatim: "Low-band pulse triggers
kick; high-band pulse does not." Dependencies: ANL-002 (integrated). Verification: unit tests with
synthetic PCM, plus the simulator. Design a reusable band-limited transient detector that ANL-008
(snare-like) and ANL-009 (high-frequency transient) can parameterize later; do not implement them.
Honor the repository constitution and owner rules 4, 7 and 8."

Identifiers carry the roadmap ID so they never collide with other features: requirements are
`ANL-007-R1…`, success criteria `ANL-007-S1…`, tasks `ANL-007-T01…`. Other features are cited by
their own IDs: ANL-001 (spectra), ANL-002 (log bands and their bin-weight rule), ANL-004 (spectral
flux onsets), ANL-005/ANL-006 (beat tracker, tempo confidence), ANL-016 (analysis event bus),
MOD-002 (audio feature modulation sources and bindings), SHD-009 (expression language that reads
audio sources), AUD-008/AUD-009 (trim and channel selection on the analysis copy).

## Baseline: what exists today (audit of 2026-11-13, commit `97bb762`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Spectra and bands | ANL-001 `SpectrumStream` (2,048-point Hann, hop 512, 44.1 kHz in the bus) gives linear magnitudes where a full-scale sine reads 1 at its peak bin. ANL-002 `BandLayout`/`BandReducer` sum bins into 16-128 log bands with fractional bin weights and a Hann ENBW scale; the band count is user-selectable and changes at run time. | No fixed frequency range independent of the visual's band count. |
| Onsets | ANL-004 `SpectralFluxOnsetDetector`: rectified mean increase of decibel-normalized bands, threshold δ + κ·mean of the preceding 100 ms, arm/disarm hysteresis, 50 ms minimum interval. Full-band: a hi-hat and a kick both fire it. | No band-limited detection; the flux depends on absolute level through the −70 dB normalization floor. |
| Bus | ANL-016 `AnalysisPipeline` runs, per frame: bands, onset detector, beat tracker; publishes `AnalysisFrame` (bands, `onsetFlux`, `bpm`, `beatConfidence`) then `AnalysisEvent`s (`.onset`, `.beat`, session markers). Input is the analysis tap after AUD-009 channel selection and AUD-008 trim. | No kick event or kick value. |
| Modulation | MOD-002 `AudioFeatureSource` = `band(i)`, `bandMean`, `onset`, `beatConfidence` (stable IDs `audio.*`, stored by scenes; SHD-009 expressions read them through opcodes 3-6). The app's native visual feeds bindings with bands only (`NativeSpectrumHost.applyModulation`). | No kick source. |
| Consumers of event kinds | `TempoEstimateTracker` (PerformanceControl) switches exhaustively over `AnalysisEventKind`. | Must handle a new kind. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the recommended, conservative option.

- Q: Which frequency range is "the kick"? → A: 40–150 Hz. A kick drum's fundamental sits at 45–100 Hz and its body below about 150 Hz; above 150 Hz the range would take in bass guitar harmonics, toms and the snare's body (ANL-008's range), below 40 Hz the 2,048-point spectrum (21.5 Hz bins) has little resolution and sub-bass rumble dominates. The edges use ANL-002's fractional bin weights, so the range is the same at every FFT size. Rejected: one of ANL-002's log bands (their edges move with the user's band count) (ANL-007-R1, R9).
- Q: How is "relative to its own baseline" measured, and with which threshold? → A: Band level L = 10·log10 of the band's power (a full-scale sine in band reads 0 dB), clamped at the absolute floor of −70 dB. Detection value (band log-energy flux) D = L − the minimum L of the preceding frames spanning one FFT window (4 frames at 2,048/512), so a rise is measured from the level just before the hit, outside the analysis window's overlap. Threshold = max(6 dB, median(D) + 4·MAD(D)) over the preceding 1.0 s of D (86 frames at hop 512; MAD = median absolute deviation). Fire when D exceeds it while armed, L is above the floor, and the band holds at least −20 dB (1 %) of the frame's total power. Why: decibel differences are unchanged by gain, so the rise is level-independent above the floor; the kick's own decay makes D slightly negative most of the time, so in kick-driven material the median and MAD stay small and the 6 dB minimum governs, while in noisy low-frequency material (single frames fluctuate by several dB) median + 4·MAD lifts the threshold; 6 dB (power ×4) is far above a sustained tone's ripple yet below a kick's 20+ dB rise; −70 dB matches ANL-004's floor and sits 40+ dB above 16-bit dither in this band; the −20 dB dominance rejects energy leaking into 40–150 Hz from an abrupt high or mid transient (estimated −35 dB or less for the test bursts) and stationary white noise (about −23 dB), while a kick under a pad of equal or 6 dB higher level keeps a share near −10 dB. Rejected: the median and MAD of the level itself (design review before coding, 2026-11-13: a decaying kick spans about 40 dB of level within each beat, so the level's MAD is about 10 dB and 4·MAD would suppress every kick), a ratio to a slow exponential envelope (a loud kick drags it up and masks the next one), mean + k·σ (spikes inflate it) (ANL-007-R2 to R5).
- Q: How long are the refractory period and the envelope? → A: Refractory 100 ms (allows up to 10 kicks per second, 150 BPM sixteenths; suppresses the second peak of a two-stage kick attack and frames of the same hit), plus re-arming only after the rise falls back to or below the threshold (a held bass note never retriggers). Envelope: set to 1 on each event (not scaled by loudness, so it is level-independent) and multiplied by exp(−hop / (0.1 s · rate)) per frame: a 100 ms time constant, down to 13 % after 200 ms, which reads as a punchy pulse on visuals at 60 fps (ANL-007-R6, R8).
- Q: How do kick events appear on the analysis bus? → A: As one new generic event kind `transient(band:, strength:, threshold:, level:)` with `band = .kick`, and a `kickEnvelope` value in every feature frame. ANL-008 and ANL-009 add a band case and their own configuration, not new event kinds or new detector types; the event's sample position is ANL-004's rule. Rejected: a kick-only event case (each later detector would add another case and another exhaustive-switch edit across packages) (ANL-007-R7, R9, R10).
- Implementation finding (T03-T04, 2026-11-13, before any commit of code): three changes from the answer above, each measured with debug runs (white noise at −6 and −40 dBFS, seeds 1, 2, 3, 0x5EED, 3 s each; 5 kHz, 1 kHz, 300 Hz, 200 Hz bursts; kicks at hop offsets 100, 300, 511 and 45, 80, 120 Hz). (1) The flux reference is the *highest* level of the preceding window-length frames, not the lowest: against the lowest, background noise's downward dips gave D up to 8 dB and a false kick in the pad fixture. (2) Dominance is the band's share of the frame's power *increase* over that reference frame, at −15 dB, not the share of total power at −20 dB: at a kick's first frame under a −6 dBFS pad its absolute share was −27 dB (missed), while its share of the increase was 0 to −6 dB; the 1 kHz burst's increase share is −23.4 dB (8.4 dB margin) and the 5 kHz burst's −37.9 dB; a falling total counts as not concentrated. (3) Minimum rise 9 dB, not 6: one seed of white noise reached D = 6.5 dB; at 9 dB every noise run stays ≥ 3.4 dB under the threshold, while kicks clear it by 7 to 36 dB on their first frame. Also fixed: the first frame after creation or reset now compares with silence (one floor level seeded), as ANL-004 does. Fixtures were shortened (4 pulses 255 ms apart) to keep the Linux-shape cost under 1 s.
- Q: Is there a modulation source or any UI? → A: A MOD-002 source "Kick" with the stable ID `audio.kick`, reading the frame's kick envelope; SHD-009 expressions get it through the unused permanent opcode value 9. The native visual feeds the envelope to its bindings (the onset and beat-confidence sources stay unfed in the app, as today, out of scope). No UI: bindings are created by scenes and the Debug path, and the app has no source picker today. Rejected: a Debug readout or a kick indicator view (no user need in this row) (ANL-007-R11, R12, R15).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Kicks fire, other drums do not (Priority: P1)

A visual author binds a visual parameter to the kick. When a low drum hits, the parameter jumps
and decays; hi-hats, snares and mid-range stabs leave it alone.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Package tests feed synthetic pulse trains (deterministic sample clock, fixed
seeds) through the detector and through the real analysis pipeline.

**Acceptance Scenarios**:

1. **Given** a train of low-frequency pulses (a 55 Hz decaying sine burst every 255 ms; tests use 3-4 pulses to stay within owner rule 7), **When** analysed, **Then** exactly one kick event is reported per pulse, within one analysis hop of the pulse start.
2. **Given** a train of high-frequency pulses (a 5 kHz decaying burst) or mid-range pulses (a 1 kHz burst), **When** analysed, **Then** no kick event is reported.
3. **Given** the low pulse train mixed under a loud sustained high-frequency layer (a pad or hi-hat-like noise louder than the kicks), **When** analysed, **Then** every pulse is still reported and nothing else.

---

### User Story 2 - Kicks fire the same in quiet and loud mixes (Priority: P1)

A performer plays the same track quietly and loudly (or the source's level changes); the kick
fires on the same hits.

**Why this priority**: It is the row's observable behavior ("independently of overall level").

**Independent Test**: The same pulse train at −30 dBFS and at −6 dBFS gives identical events.

**Acceptance Scenarios**:

1. **Given** the low pulse train at −30 dBFS and at −6 dBFS peak, **When** analysed, **Then** both give the same number of events at the same sample positions.

---

### User Story 3 - No false kicks (Priority: P1)

Sustained bass, silence, dither and noise never produce kicks, and one kick never produces two.

**Why this priority**: False triggers make a kick-driven visual flash at random.

**Independent Test**: Package tests with a held bass tone, silence, dither-level noise, loud
white noise, and two pulses closer together than the refractory period.

**Acceptance Scenarios**:

1. **Given** a sustained 60 Hz tone for several seconds, **When** analysed, **Then** at most one event is reported (at its start) and none afterwards.
2. **Given** digital silence, silence with dither-level noise, or loud white noise, **When** analysed, **Then** no event is reported.
3. **Given** two low pulses closer than the refractory period, **When** analysed, **Then** only the first is reported; two pulses farther apart than it are both reported.

---

### User Story 4 - Kick is a modulation source (Priority: P2)

A visual author can bind any modulatable parameter to "Kick", a value that jumps to 1 on each kick
and decays smoothly to 0, and write it in an expression.

**Why this priority**: The detector is only useful to visuals through MOD-002.

**Independent Test**: A ParameterGraph test (the source's ID round-trips, reads from a frame, and
binds), an expression test, and an app unit test that a kick binding on the native visual drives
its target.

**Acceptance Scenarios**:

1. **Given** the source list, **When** a binding is created from the ID `audio.kick`, **Then** it parses, binds to a modulatable parameter and follows the kick envelope (0…1).
2. **Given** the native visual with a binding from Kick, **When** frames carry a kick envelope, **Then** the bound parameter follows it.

### Edge Cases

- A session restart (capture restart, source switch): the baseline, refractory timer and envelope restart; the first kick after a restart is detected.
- Frames at another sample rate, with a wrong magnitude count, or not contiguous: ignored or used only to re-establish the baseline, as ANL-004 does; never an event.
- FFT size other than 2,048 (the detector serves any ANL-001 size): the band's bin weights exist for every size.
- Non-finite magnitudes: treated as silence for that frame; never an event, never a non-finite envelope.
- A kick under sustained bass of similar level: may or may not fire (the rise is small); not promised.
- A kick much quieter than the rest of the mix (more than the dominance limit below the full-band level): not reported (documented limitation).
- Very fast kicks (double-kick drums faster than the refractory period): only every other hit is reported.
- Abrupt low-mid bursts (200–300 Hz with a hard onset, such as a tom or a low snare body): their onset leakage dominates the rise in 40–150 Hz, so they fire (measured: increase share −6 and −12 dB). Not promised either way; ANL-008 covers that range.
- Unaligned hits: a hit that starts late in a hop may be reported one hop later at a low level than at a high level (the first frame holds too little of it); events stay within one hop of the hit.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-007-R1**: A band-limited transient detector MUST compute, per spectrum frame, the energy in one configurable frequency range (the kick: 40–150 Hz), using ANL-002's fractional bin-weight rule for the range's edges, for every ANL-001 FFT size.
- **ANL-007-R2**: The detector MUST decide on the band's level relative to its own recent history (an adaptive baseline of the preceding frames), never on absolute level alone, so the same material at different levels (above the floor) gives the same events.
- **ANL-007-R3**: The detection value MUST be the band level minus the highest level of the preceding frames spanning one FFT window, and the threshold max(9 dB, median + 4 × median absolute deviation of the detection values of the preceding 1.0 s), so stationary noise does not fire.
- **ANL-007-R4**: The detector MUST NOT report while the band's level is at or below the absolute floor (−70 dB re a full-scale sine), so silence and dither never fire.
- **ANL-007-R5**: The detector MUST report only when the band holds at least −15 dB (3 %) of the frame's power increase over the reference frame (dominance; a falling total counts as not concentrated), so energy leaking into the band from a loud transient elsewhere in the spectrum does not fire, while a kick under a loud sustained layer does.
- **ANL-007-R6**: After an event, the detector MUST report nothing for the refractory period (100 ms for the kick), and MUST re-arm only after the rise falls back to or below the threshold, so a sustained level never retriggers.
- **ANL-007-R7**: Each event MUST carry a sequence number, its sample position on the stream's clock (the first sample of the frame's newest hop, as ANL-004), the rise over the baseline, the threshold it crossed and the band level.
- **ANL-007-R8**: The detector MUST also provide an envelope (0…1): 1 on an event, decaying exponentially with a 100 ms time constant per frame, never non-finite.
- **ANL-007-R9**: The kick MUST be the detector configured for the low band; the configuration MUST be the only difference between it and later band detectors (ANL-008, ANL-009), and invalid configurations MUST be impossible to construct.
- **ANL-007-R10**: The ANL-016 pipeline MUST run the kick detector on every spectrum frame, publish each kick as a discrete event after the frame (in ID order with onsets and beats), and carry the kick envelope in every feature frame. Session starts MUST reset the detector.
- **ANL-007-R11**: MOD-002 MUST offer a "Kick" source with the stable ID `audio.kick` that reads the frame's kick envelope (missing or non-finite reads 0), usable in bindings, the modulation graph, scenes and SHD-009 expressions.
- **ANL-007-R12**: The app's native visual MUST feed the kick envelope to its bindings, so a Kick binding is live.
- **ANL-007-R13**: Processing a frame MUST NOT allocate, lock, log or do I/O (Constitution VII); everything is preallocated at creation.
- **ANL-007-R14**: The detector MUST build and pass its tests on Linux and in the package's Linux shape (`-DANALYSIS_NO_ACCELERATE`); it MUST read no clock.
- **ANL-007-R15**: Nothing computed here reaches projectM (Constitution VIII, ADR-0008 decision 5); no new setting, no stored data beyond a scene binding's source ID, no network, no UI.

### Key Entities

- **Transient band**: which detector produced an event (today only `kick`).
- **Transient detector configuration**: sample rate, frequency range, absolute floor, dominance limit, baseline window, minimum rise, variability multiplier, refractory period, envelope time constant.
- **Transient event**: band, sequence, sample position, rise, threshold, band level.
- **Kick envelope**: a 0…1 value per feature frame.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-007-S1**: A low pulse train fires once per pulse (no misses, no extras); high and mid pulse trains fire zero times (the roadmap acceptance).
- **ANL-007-S2**: The low pulse train at −30 dBFS and −6 dBFS gives identical event positions.
- **ANL-007-S3**: Pulses under a louder sustained high layer are all detected with no extras.
- **ANL-007-S4**: A sustained bass tone fires at most once; silence, dither and loud white noise fire zero times; a second pulse inside the refractory period is not reported.
- **ANL-007-S5**: Through the real analysis pipeline, the low pulse train yields one kick event per pulse in ID order and frames whose envelope is 1 at each kick and decays; the high pulse train yields none.
- **ANL-007-S6**: `audio.kick` round-trips, binds, compiles in an expression and drives a bound parameter in the app.
- **ANL-007-S7**: The new package tests add at most a few hundred milliseconds to the AnalysisFeatures suite in the Linux shape, and every existing test passes.

## Implementation results (2026-11-13)

Fixture table (`KickDetectorTests`, 2,048-point spectra, hop 512, 44.1 kHz, `.kick` defaults; the
same on the host and in the Linux shape):

| Input | Pulses | Kick events | Hits (±1 hop) | Misses | Extras |
|---|---|---|---|---|---|
| 55 Hz bursts, −6 dBFS | 4 | 4 | 4 | 0 | 0 |
| 55 Hz bursts, −30 dBFS (same positions as −6) | 4 | 4 | 4 | 0 | 0 |
| 5 kHz and 1 kHz bursts, −6 dBFS | 4 | 0 | — | — | 0 |
| 55 Hz −12 dBFS under 2 + 3.3 kHz pad (−6 dBFS each) + white noise −30 dBFS | 4 | 4 | 4 | 0 | 0 |
| 60 Hz sustained, −12 dBFS, 1.2 s | 1 onset | 1 (at the onset) | 1 | 0 | 0 |
| Digital silence / ±1 LSB dither / white noise −6 dBFS | 0 | 0 / 0 / 0 | — | — | 0 |
| Two pulses 60 ms apart / 150 ms apart | 2 / 2 | 1 / 2 | — | — | 0 |
| Through `AnalysisPipeline`: 55 Hz bursts, −12 dBFS | 3 | 3 `.transient(band: .kick)` | 3 | 0 | 0 |
| Through `AnalysisPipeline`: 5 kHz bursts, −6 dBFS | 3 | 0 (onsets still reported) | — | — | 0 |

Pulses after the first are reported one hop after their start (pipeline and offline alike): at the
fixtures' 255 ms spacing the previous burst's tail is still inside the one-window reference, so the
first frame of the next hit rises only ≈ 4 dB and the second frame fires. Debug runs gave identical
positions at −6, −12, −18, −24, −30 and −40 dBFS.

Test cost (owner rule 7): KickDetectorTests (8 tests) take 0.44 s on the host and 0.95 s in the
Linux shape run alone; the whole AnalysisFeatures suite went from 116 to 124 tests, 67.7 s → 67.4 s
in the Linux shape (inside run-to-run noise). The new tests stay under 1 s in the Linux shape, not the "few hundred ms" first
aimed for: the portable FFT costs ≈ 70 ms per second of audio there, and the eight tests need
≈ 13 s of audio after trimming.

No UI was added (Clarifications). The onset and beat-confidence sources stay unfed in the app as
before; only Kick is fed.

## Assumptions

- The bus keeps 2,048-point spectra at hop 512 and 44.1 kHz (11.6 ms frames); defaults are chosen for it but valid for every ANL-001 size and rate.
- "Kick" means low-frequency transient energy; no instrument identity is claimed.
- The detector sees the analysis copy after AUD-009 channel selection and AUD-008 trim (and AUD-011's gate when it lands); trim changes level, which by R2 does not change events above the floor.
- Simulator results are not device evidence; acceptance is synthetic PCM (unit tests).
