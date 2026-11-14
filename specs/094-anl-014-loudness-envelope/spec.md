# Feature Specification: ANL-014 Loudness Envelope

**Feature Branch**: `feature/anl-014` (spec directory `094-anl-014-loudness-envelope`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement ANL-014 (Loudness envelope) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Expose normalized short-term
perceived level for automation." Acceptance, verbatim: "Envelope remains bounded and follows step
amplitude with documented lag." Dependencies: ANL-001 (integrated). Marked "Extension (existing
level meter)". Verification: unit tests with synthetic PCM, plus the simulator. Follow ANL-007 and
ANL-010's pattern for a per-frame feature on the analysis bus and a MOD-002 modulation source.
Honor the repository constitution and owner rules 4, 7 and 8."

Identifiers carry the roadmap ID so they never collide with other features: requirements are
`ANL-014-R1…`, success criteria `ANL-014-S1…`, tasks `ANL-014-T01…`. Other features are cited by
their own IDs: ANL-001 (windowed magnitude spectra), ANL-003 (band smoothing and its attack/release
rule), ANL-007 (kick), ANL-010 (centroid, the pattern followed here), ANL-015 (section energy
change, a later row that depends on this one), ANL-016 (analysis event bus), AUD-008 (input trim),
AUD-009 (channel selection), AUD-011 (noise gate), AUD-012 (source switching), MOD-002 (audio
feature sources and bindings), SHD-009 (expressions that read audio sources).

## Baseline: what exists today (audit of 2026-11-14, commit `ab68d80`)

The row is marked "Extension (existing level meter)". The audit finds that the existing meter is
not reachable by automation and measures something different:

| Area | Today | Gap for this row |
|---|---|---|
| Level meter | AudioCore `LevelMeter.measure` gives peak and RMS in dBFS (floor −120) of each raw sink block. `AudioAnalyzer` feeds it to the audio-state classifier (silent / active), the capture manager's `levels`, the session peak/mean, the CaptureLab diagnostics and export, and the performance overlay's audio state. | Unweighted (a 50 Hz rumble counts as much as a 2 kHz voice), unsmoothed, per capture block, on the raw sink *before* channel selection, trim and gate, and on the capture side: nothing reaches the analysis bus or a binding. |
| Analysis copy | The analysis tap carries the normalized audio after AUD-009 channel selection, AUD-008 trim and AUD-011 gate (non-finite samples sanitized since AUD-012). ANL-016's `AnalysisPipeline` turns it into 2,048-point spectra at hop 512 (44.1 kHz) and publishes per frame `AnalysisFrame` (bands, onset flux, beat, `kickEnvelope`, `centroidHz`, `centroid`). | No level value on the bus. |
| Modulation | MOD-002 `AudioFeatureSource` = `band(i)`, `bandMean`, `onset`, `beatConfidence`, `kick`, `centroid` (SHD-009 opcodes 3-6, 9, 15). `bandMean` is the mean of the decibel-normalized bands: a spectral-shape average, not a level (a pure tone lights one band, so its mean is low however loud it is). The app's native visual feeds bands, kick and centroid to its bindings. | No perceived-level source. |

## Clarifications

### Session 2026-11-14

(Filled by speckit-clarify.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A parameter follows how loud the music sounds (Priority: P1)

A visual author binds a parameter (glow, scale) to the music's loudness: quiet passages read low,
loud passages read high, and the value moves smoothly enough to look good but fast enough to follow
the music.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Package tests feed synthetic tones and steps (deterministic sample clock) and
read the envelope frame by frame.

**Acceptance Scenarios**:

1. **Given** a tone that steps from −40 dBFS to −10 dBFS and back, **When** analysed, **Then** the envelope rises to the loud level and falls back to the quiet level, reaching 90 % of each step within the documented rise and fall times (to within one analysis frame).
2. **Given** the same tone at rising levels, **When** analysed, **Then** the settled envelope rises strictly with the level.
3. **Given** equal-amplitude tones at 100 Hz and 2 kHz, **When** analysed, **Then** the 2 kHz tone reads louder, as human hearing (and the chosen weighting) rates it.

---

### User Story 2 - The value never breaks (Priority: P1)

Whatever arrives, the value bound to a visual stays in range and calm.

**Why this priority**: A value outside 0…1, or not a number, would make bound visuals flash or
freeze.

**Independent Test**: Full-scale noise, clipping square waves, injected non-finite samples, and
silence.

**Acceptance Scenarios**:

1. **Given** full-scale noise, a clipping square wave, or input containing non-finite samples, **When** analysed, **Then** every value is finite and within 0…1.
2. **Given** silence (from the start, or after loud audio), **When** analysed, **Then** the value is 0 from the start, or decays to exactly 0 after loud audio, and is never non-finite.

---

### User Story 3 - Loudness is a modulation source (Priority: P2)

A visual author can bind any modulatable parameter to "Loudness" and use it in an expression.

**Why this priority**: The value is useful to visuals only through MOD-002.

**Independent Test**: A pipeline test, ParameterGraph tests (ID round trip, binding, expression)
and an app unit test that a Loudness binding on the native visual drives its target.

**Acceptance Scenarios**:

1. **Given** the real analysis pipeline fed a quiet tone then a loud tone, **When** frames are read, **Then** they carry the envelope and the loud tone's frames read higher.
2. **Given** the native visual with a binding from Loudness, **When** frames carry an envelope, **Then** the bound parameter follows it.

### Edge Cases

- Content below about 40 Hz is attenuated by the weighting (as in loudness standards); a 20 Hz tone reads quieter than a 1 kHz tone of the same amplitude.
- A level above the normalization ceiling (very loud, bright content) reads 1 (clamped); below the floor reads 0.
- Non-finite spectrum values: treated as 0 for that bin; never a non-finite result.
- Frames at another sample rate or FFT size than configured: ignored (the value is kept).
- A session restart (source switch, restart): the envelope restarts from 0 as at creation.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-014-R1**: The system MUST compute, for each analysis frame, a frequency-weighted short-term level of the analysis copy that approximates perceived loudness (weighting chosen in Clarifications).
- **ANL-014-R2**: The level MUST be mapped to a normalized value in 0…1 by a fixed, documented decibel range, clamped at both ends.
- **ANL-014-R3**: The normalized value MUST be smoothed over time with documented attack (rise) and release (fall) times, so that a level step reaches 90 % of its change in a documented, tested time.
- **ANL-014-R4**: For a step from −40 dBFS to −10 dBFS and back, the measured 90 % rise and 90 % fall times MUST match the documented values within one analysis frame.
- **ANL-014-R5**: Every published value MUST be finite and within 0…1 for any input, including full-scale noise, clipping, non-finite samples and silence; silence MUST read 0 from the start and decay to exactly 0 after sound.
- **ANL-014-R6**: The settled value MUST increase with input level, and equal-amplitude tones MUST read in the order of the chosen weighting (2 kHz above 100 Hz).
- **ANL-014-R7**: The ANL-016 pipeline MUST compute the envelope on every spectrum frame and carry it in every feature frame, together with the frame's unsmoothed level in decibels; session starts MUST reset it.
- **ANL-014-R8**: MOD-002 MUST offer a "Loudness" source with the stable ID `audio.loudness` that reads the normalized envelope (missing or non-finite reads 0), usable in bindings, the modulation graph, scenes and SHD-009 expressions (the next free permanent opcode).
- **ANL-014-R9**: The app's native visual MUST feed the envelope to its bindings, so a Loudness binding is live.
- **ANL-014-R10**: Processing a frame MUST NOT allocate, lock, log or do I/O (Constitution VII).
- **ANL-014-R11**: The feature MUST build and pass its tests in the package's Linux shape (`-DANALYSIS_NO_ACCELERATE`) and read no clock; time comes from the sample count.
- **ANL-014-R12**: Nothing computed here reaches projectM (Constitution VIII, ADR-0008 decision 5); the existing level meter, its consumers and the audio-state classifier are unchanged; no new setting, no stored data beyond a scene binding's source ID, no network, no UI.

### Key Entities

- **Loudness configuration**: sample rate, FFT size, decibel normalization range, attack and release times.
- **Loudness reading**: the frame's unsmoothed weighted level in decibels, and the smoothed normalized envelope.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-014-S1**: For the −40 → −10 → −40 dBFS step, the 90 % rise and fall times match the documented lag within one frame (the roadmap acceptance), and the envelope never leaves 0…1.
- **ANL-014-S2**: Full-scale noise, a clipping square wave, input with non-finite samples, and silence all keep every value finite and within 0…1; silence after sound reaches exactly 0.
- **ANL-014-S3**: Settled values rise strictly over at least four input levels; 2 kHz reads above 100 Hz at equal amplitude; a full-scale 997 Hz sine reads the loudness standard's reference level within 0.2 dB.
- **ANL-014-S4**: Through the real pipeline, a loud tone's frames read higher than a quiet tone's.
- **ANL-014-S5**: `audio.loudness` round-trips, binds, compiles in an expression and drives a bound parameter in the app.
- **ANL-014-S6**: The new package tests add at most a few hundred milliseconds to the AnalysisFeatures suite in the Linux shape, and every existing test (and every dependent package's) passes.

## Assumptions

- The bus keeps 2,048-point spectra at hop 512 and 44.1 kHz; the envelope is valid at every ANL-001 size and rate it is configured for.
- "Short-term perceived level" means a weighted, smoothed level for visuals, not a certified loudness meter: no gating, no integrated or long-term loudness, no true-peak.
- The envelope sees the analysis copy after AUD-009 channel selection, AUD-008 trim and AUD-011 gate, so it moves with those controls, as every other bus feature does.
- Simulator results are not device evidence; acceptance is synthetic PCM (unit tests).
