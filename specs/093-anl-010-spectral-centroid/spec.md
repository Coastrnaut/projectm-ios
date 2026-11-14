# Feature Specification: ANL-010 Spectral Centroid

**Feature Branch**: `feature/anl-010` (spec directory `093-anl-010-spectral-centroid`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement ANL-010 (Spectral centroid) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Expose brightness estimate in
Hz normalized for mappings." Acceptance, verbatim: "Increasing tone frequency increases centroid
monotonically." Dependencies: ANL-001 (integrated). Verification: unit tests with synthetic PCM,
plus the simulator. Follow ANL-007's pattern for a per-frame feature on the analysis bus and a
MOD-002 modulation source. Read ANL-011 (rolloff) and ANL-012 (flatness) for shared code; do not
implement them. Honor the repository constitution and owner rules 4, 7 and 8."

Identifiers carry the roadmap ID so they never collide with other features: requirements are
`ANL-010-R1…`, success criteria `ANL-010-S1…`, tasks `ANL-010-T01…`. Other features are cited by
their own IDs: ANL-001 (windowed magnitude spectra), ANL-002 (log bands), ANL-003 (band smoothing),
ANL-007 (kick detector, the pattern followed here), ANL-011/ANL-012 (rolloff, flatness: later rows
that analyse the same frequency range), ANL-016 (analysis event bus), MOD-002 (audio feature
sources and bindings), SHD-009 (expressions that read audio sources).

## Baseline: what exists today (audit of 2026-11-13, commit `02dec1a`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap: no
source file in `Packages/` or `Apps/` computes a centroid, rolloff or flatness.

| Area | Today | Gap for this row |
|---|---|---|
| Spectra | ANL-001 `SpectrumStream`/`SpectrumAnalyzer`: periodic Hann, sizes 512-8,192, linear magnitudes where a bin-centred full-scale sine reads 1 (neighbours 0.5); `FFTSize.frequency(ofBin:sampleRate:)` gives k·R/N. The bus runs 2,048 points, hop 512, 44.1 kHz. | No spectral-shape descriptor. |
| Bus | ANL-016 `AnalysisPipeline` publishes per frame `AnalysisFrame` (bands, `onsetFlux`, `bpm`, `beatConfidence`, `kickEnvelope` since ANL-007) and then events. | No brightness value. |
| Modulation | MOD-002 `AudioFeatureSource` = `band(i)`, `bandMean`, `onset`, `beatConfidence`, `kick` (IDs `audio.*`; SHD-009 opcodes 3-6 and 9). Bindings have their own attack/release envelope. The app's native visual (`NativeSpectrumHost`) feeds bindings the bands and the kick envelope; onset and beat confidence read 0 in the app. | No brightness source. |
| ANL-011, ANL-012 | Not built. Rolloff (energy-percentile frequency) and flatness (tonal vs noise) will analyse the same bins of the same spectra. | The frequency-range-to-bins rule should be shared, not repeated. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the recommended, conservative option.

<!-- filled by speckit-clarify -->

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Brighter sound reads higher (Priority: P1)

A visual author wants a parameter (a colour, a glow) to follow how bright the music sounds: dull,
bass-heavy passages read low; cymbals and bright synths read high.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Package tests feed single sine tones at rising frequencies (synthetic PCM,
deterministic sample clock) and compare the estimates.

**Acceptance Scenarios**:

1. **Given** sine tones at 100, 200, 400, 800, 1,600, 3,200 and 6,400 Hz, **When** analysed, **Then** the estimate in Hz rises strictly with the tone frequency and lies within a small tolerance of each tone's frequency, and the normalized value rises too and stays within 0…1.
2. **Given** two equal tones, or two tones at different levels, **When** analysed, **Then** the estimate lies between them, closer to the louder one.
3. **Given** white noise, **When** analysed, **Then** the estimate lies near the middle of the analysed frequency range.

---

### User Story 2 - The same sound reads the same everywhere (Priority: P1)

The estimate in Hz does not depend on how the analysis is configured or how loud the sound is.

**Why this priority**: A brightness that moved with the FFT size, the sample rate or the volume
would make mappings unpredictable.

**Independent Test**: The same tone analysed at every FFT size and at two sample rates, and at two
levels.

**Acceptance Scenarios**:

1. **Given** a tone, **When** analysed at FFT sizes 512 to 8,192 and at 44.1 and 48 kHz, **Then** the estimates agree within tolerance.
2. **Given** a tone at −6 dBFS and −40 dBFS, **When** analysed, **Then** the estimates agree.

---

### User Story 3 - Silence is calm (Priority: P1)

When the music stops, the brightness value neither breaks nor jumps.

**Why this priority**: A value that turned into "not a number" or snapped to an extreme on every
pause would make bound visuals flash.

**Independent Test**: Silence, dither-level noise and silence after a tone.

**Acceptance Scenarios**:

1. **Given** digital silence or dither-level noise from the start, **When** analysed, **Then** every value is finite and follows the documented silence rule.
2. **Given** a tone followed by silence, **When** analysed, **Then** the value follows the documented silence rule (no jump, never non-finite).

---

### User Story 4 - Brightness is a modulation source (Priority: P2)

A visual author can bind any modulatable parameter to the brightness (0…1) and use it in an
expression; the analysis bus also carries the value in Hz for readouts and later features.

**Why this priority**: The estimate is useful to visuals only through MOD-002.

**Independent Test**: A pipeline test, ParameterGraph tests (ID round-trip, binding, expression) and
an app unit test that a brightness binding on the native visual drives its target.

**Acceptance Scenarios**:

1. **Given** the real analysis pipeline fed a low tone then a high tone, **When** frames are read, **Then** they carry both values and the high tone's are higher.
2. **Given** the native visual with a binding from the brightness source, **When** frames carry a brightness value, **Then** the bound parameter follows it.

### Edge Cases

- A tone below the analysed range's lower edge (for example 10 Hz): only its leakage above the edge counts; the estimate is low but not promised to be accurate.
- A tone above the normalization range's upper edge: the normalized value is 1 (clamped); the value in Hz is still reported.
- Low tones at small FFT sizes (100 Hz at 512 points, 86 Hz bins): the window's main lobe is a few bins wide, so the estimate is biased by up to about a bin; tolerance is stated per size.
- Non-finite magnitudes: treated as 0 for that bin; never a non-finite result.
- Frames at another sample rate or with a wrong magnitude count: ignored (the last value is kept).
- A session restart: the state restarts as at creation.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-010-R1**: The system MUST compute, for each spectrum frame, a spectral centroid: the weighted mean frequency of the frame's spectrum over a fixed analysed range that excludes DC, using the frame's own FFT size and sample rate.
- **ANL-010-R2**: The centroid MUST be reported in Hz and as a normalized 0…1 value derived from it by a documented, perceptually even mapping, clamped to 0…1.
- **ANL-010-R3**: For single sine tones the centroid MUST increase strictly with the tone frequency across 100 Hz to 6.4 kHz and lie within a documented tolerance of the tone frequency.
- **ANL-010-R4**: The centroid in Hz MUST NOT depend on the input level above the silence floor, and MUST agree across every ANL-001 FFT size and across sample rates within the documented tolerance.
- **ANL-010-R5**: When the analysed range holds less energy than a documented silence floor, the values MUST follow a documented rule that never produces a non-finite value or a jump; every value published MUST be finite.
- **ANL-010-R6**: The range-to-bins rule MUST be shared code that ANL-011 and ANL-012 can reuse.
- **ANL-010-R7**: The ANL-016 pipeline MUST compute the centroid on every spectrum frame and carry both values in every feature frame; session starts MUST reset it.
- **ANL-010-R8**: MOD-002 MUST offer a brightness source with a stable ID that reads the normalized value (missing or non-finite reads 0), usable in bindings, the modulation graph, scenes and SHD-009 expressions (a new permanent opcode).
- **ANL-010-R9**: The app's native visual MUST feed the normalized value to its bindings, so a brightness binding is live.
- **ANL-010-R10**: Processing a frame MUST NOT allocate, lock, log or do I/O (Constitution VII).
- **ANL-010-R11**: The feature MUST build and pass its tests on Linux and in the package's Linux shape (`-DANALYSIS_NO_ACCELERATE`); it MUST read no clock.
- **ANL-010-R12**: Nothing computed here reaches projectM (Constitution VIII, ADR-0008 decision 5); no new setting, no stored data beyond a scene binding's source ID, no network, no UI.

### Key Entities

- **Centroid configuration**: sample rate, analysed frequency range, silence floor, normalization range.
- **Centroid reading**: value in Hz, normalized value, whether the frame was above the floor.
- **Frequency range bins**: the first and last spectrum bin of a frequency range at an FFT size and sample rate (shared with ANL-011/012).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-010-S1**: The seven test tones give strictly increasing centroids, each within tolerance of its frequency, with normalized values strictly increasing inside 0…1 (the roadmap acceptance).
- **ANL-010-S2**: White noise reads within 5 % of the analysed range's expected mean; two tones read between them, weighted as documented.
- **ANL-010-S3**: One tone reads the same within tolerance at all five FFT sizes, at 44.1 and 48 kHz, and at −6 and −40 dBFS.
- **ANL-010-S4**: Silence, dither and tone-then-silence give only finite values that follow the silence rule.
- **ANL-010-S5**: Through the real pipeline, a high tone's frames read higher than a low tone's, in both values.
- **ANL-010-S6**: The brightness source round-trips, binds, compiles in an expression and drives a bound parameter in the app.
- **ANL-010-S7**: The new package tests add at most a few hundred milliseconds to the AnalysisFeatures suite in the Linux shape, and every existing test passes.

## Assumptions

- The bus keeps 2,048-point spectra at hop 512 and 44.1 kHz; the centroid is valid at every ANL-001 size and rate.
- "Brightness" means the spectral centroid only; perceptual loudness weighting is out of scope.
- The centroid sees the analysis copy after AUD-009 channel selection and AUD-008 trim.
- Simulator results are not device evidence; acceptance is synthetic PCM (unit tests).
