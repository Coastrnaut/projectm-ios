# Feature Specification: ANL-005 Adaptive Beat Tracker

**Feature Branch**: `feature/anl-005` (spec directory `021-anl-005-adaptive-beat-tracker`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement ANL-005 (Adaptive beat tracker) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Estimate beat times from onset
intervals with confidence." Acceptance, verbatim: "Synthetic 120 BPM pulses converge within a
specified BPM tolerance." Dependencies: ANL-004 (integrated); AUD-016 hand-off: identical beat
outputs on repeated runs. Honor the repository constitution, VIII and ADR-0008 decision 5."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `ANL-005-R1…`, success criteria `ANL-005-S1…`, tasks `ANL-005-T01…`. ANL-004's
requirements (`specs/018-anl-004-spectral-flux-onset-detector/spec.md`), ANL-001's
(`specs/014-anl-001-windowed-fft/spec.md`) and AUD-016's hand-off (AUD-016-R22: identical outputs
on repeated runs) stay in force; this feature cites them and adds to them.

## Baseline: what exists today (audit of 2026-11-13, commit `1192e0d`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Onsets | `Packages/AnalysisFeatures` (ANL-004) turns spectrum frames into discrete onset events, each with an exact sample index on the stream's sample clock (within one analysis hop of the true onset), a strength in 0…1 and a never-repeating sequence number. | Nothing groups onsets into a tempo or predicts the next beat. |
| Beats | No tempo, beat or phase estimate exists in `Packages/`. projectM detects beats internally and exposes nothing (ADR-0008 decision 5). | MOD-009 (tempo-synced LFO), MOD-017 (quantized changes), SHOW-003 (beat-quantized cues), SHOW-010 (beat grid), SHOW-011 (tap tempo), VIS-006 (beat rings), VIS-015 (tunnel warp), ACC-007 (haptic beat) and ANL-006 (tempo confidence states) need a tempo, a beat phase, beat events and a confidence. |
| Fixtures | AUD-016 publishes `pulse-120`, `pulse-120-accent` (accents 1, 0.5, 0.5, 0.5) and `pulse-132` (beat period not a whole number of samples) with exact onset frames at 44.1 and 48 kHz; ANL-004 detects every pulse within one hop. | Nothing checks a tempo or beat estimate against them. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option. Parameter values come from the
prototype in research.md (ANL-005-D1 to D6).

- Q: What does the tracker consume: ANL-004 onset events only, or also the per-frame onset strength? → A: Onset events only (sample index, strength, sample rate), plus the stream's current sample position so time can pass without onsets. The roadmap row says "from onset intervals"; event sample indices are exact on the sample clock; and an event-only input lets SHOW-011 feed taps through the same path later. The continuous strength function was rejected for this row (more work per frame, and its autocorrelation needs a longer buffer; ANL-006 may add it) (ANL-005-R1, R2).
- Q: How is the tempo estimated and how are octave errors (half or double tempo) handled? → A: A comb histogram of inter-onset intervals over a bounded window: every pair of onsets at most 4 s apart votes for the periods it is 1, 2, 3 or 4 times of, with weight 1/n for the n-th multiple and a recency weight (half-life 2 s), on a 0.25 BPM grid restricted to the preferred range 60–200 BPM, multiplied by a mild log-normal tempo preference centred on 120 BPM (one octave wide). The 1/n weights make the true period beat both its half (double tempo: half the votes, at larger n) and its double (half tempo: only every other interval); the preference breaks the remaining ties toward 120 BPM. A tracked tempo is kept while its score stays at 90 % or more of the best (hysteresis), so the estimate does not flip between octaves (ANL-005-R3, R4).
- Q: How are the phase and the exact tempo found, and what does a beat prediction mean? → A: The coarse period is refined by a least-squares fit of a beat grid (time = anchor + k × period, integer k) to the onsets that lie on it within a timing tolerance of 35 ms (the grid is first found with twice that tolerance, then refitted three times). The fit gives a tempo far finer than the grid and an anchor beat time; the next beat is the first grid time at or after the current stream position. Predictions are sample indices on the same clock as the onsets (ANL-005-R5, R6).
- Q: What does the confidence mean, and what is "high"? → A: Confidence in 0…1 is the product of four factors: precision (share of onsets in the window that lie on the grid), coverage (share of grid beats between the window's first and last onset that have an onset), support (0 with 2 or fewer matched beats, rising to 1 at 8) and freshness (1 until 1.5 beat periods after the last on-grid onset, then falling linearly to 0 at the silence timeout of 4 s). An estimate needs at least 4 matched beats to exist. Confidence of 0.5 or more is "high" (the tempo is supported); the synthetic pulse trains reach at least 0.8, and random onsets must stay below 0.5. ANL-006 will define named states on top of this value (ANL-005-R7, R8).
- Q: What is the BPM tolerance of the acceptance, and when is a run "converged"? → A: Converged at time t means: at every frame from t to the end of the input an estimate exists, its tempo is within ±1.0 BPM of the true tempo and its confidence is at least 0.8. Each pulse fixture must converge within 4.0 s of the stream start (8 beats at 120 BPM). After convergence every true beat gets exactly one beat event, within one analysis hop of the catalog onset frame, and no other beat event appears. A tempo change from 120 to 132 BPM must re-converge to 132 within 6.0 s of the change (the 6 s window then holds only the new tempo). Supported analysis hops are at most 1,024 samples (23.2 ms at 44.1 kHz), which the 35 ms timing tolerance covers (ANL-005-S1 to S4).
- Q: What happens after silence or a gap? → A: Time passes through the stream position. With no on-grid onset, freshness lowers the confidence from 1.5 periods after the last one; 4 s after it the estimate is dropped ("no tempo": no estimate, confidence 0, no beat events) and the onset history is cleared, so the next music locks from scratch like a new stream (ANL-005-R9).
- Q: Where does Accelerate (vDSP) fit, and how do the paths agree? → A: vDSP clears the histogram, applies the tempo preference (element-wise multiply) and finds the best bin (first maximum); the portable path does the same element-wise operations in the same order. Element-wise products and the first maximum are exact, and all sums run in scalar code in a fixed order on both paths, so both paths give bit-identical estimates and beat events (ANL-005-R12).

## User Scenarios & Testing *(mandatory)*

The "users" of this row are later modulation, show and visual features and the developers and CI
that check them. Nothing in the app changes visibly.

### User Story 1 - A steady pulse train locks to its tempo (Priority: P1)

A developer feeds the analysis a click track at 120 BPM. Within a few seconds the tracker reports
120 BPM within the stated tolerance with high confidence, and keeps reporting it.

**Why this priority**: It is the roadmap row's acceptance ("Synthetic 120 BPM pulses converge
within a specified BPM tolerance").

**Independent Test**: Run `pulse-120`, `pulse-120-accent` and `pulse-132` through the spectrum
stream, the ANL-004 detector and the tracker in the representative cases of ANL-005-R17, and
record the time of convergence and the reported tempo.

**Acceptance Scenarios**:

1. **Given** `pulse-120` or `pulse-120-accent` in a representative case of ANL-005-R17 (hops 512 and 1,024 samples), **When** one 10 s loop is analysed from the stream start, **Then** the run converges (tempo within ±1.0 BPM of 120, confidence ≥ 0.8, at every frame from then on) within 4.0 s.
2. **Given** `pulse-132` (a period that is not a whole number of samples), **When** analysed the same way, **Then** it converges to 132 within ±1.0 BPM within 4.0 s.
3. **Given** the accented fixture, **When** analysed, **Then** the tempo is the beat (120), not the bar (30) or half the beat (60 BPM).

---

### User Story 2 - Beat times are predicted on the sample clock (Priority: P1)

A visual that pulses on the beat needs the time of the next beat before it happens, as a sample
index on the same clock as the audio.

**Why this priority**: "Estimate beat times" is the observable behavior.

**Independent Test**: After convergence, compare every beat event and the predicted next beat
with the catalog onset frames.

**Acceptance Scenarios**:

1. **Given** a converged run, **When** the stream advances, **Then** each true beat after convergence gets exactly one beat event whose sample index is within one analysis hop of the catalog onset frame, and there are no other beat events.
2. **Given** an estimate, **When** it is read, **Then** it states the tempo, the period in samples, an anchor beat time, the next predicted beat (a sample index at or after the current position) and the confidence.

---

### User Story 3 - Tempo changes and gaps re-lock (Priority: P1)

A DJ mix changes tempo, or the music stops and a new track starts. The tracker follows.

**Why this priority**: "Adaptive" in the row's name; consumers must not keep a stale tempo.

**Independent Test**: Concatenate `pulse-120` and `pulse-132`; separately insert 6 s of silence
between `pulse-120` and `pulse-132`.

**Acceptance Scenarios**:

1. **Given** 10 s of 120 BPM pulses followed directly by 132 BPM pulses, **When** analysed, **Then** the run converges to 132 (±1.0 BPM, confidence ≥ 0.8) within 6.0 s of the change.
2. **Given** pulses, then silence, **When** the pulses stop, **Then** the confidence never rises during the silence, and the tracker reports no tempo (no estimate, confidence 0, no beat events) no later than 4.0 s after the last pulse.
3. **Given** a gap of silence followed by pulses at another tempo, **When** analysed, **Then** the new tempo converges within 4.0 s of the new music's start, as for a fresh stream.

---

### User Story 4 - Noise and silence never claim a tempo (Priority: P1)

A visual driven by beats must not lock onto hiss or random hits.

**Why this priority**: The confidence must mean something; ANL-006's acceptance ("Random-noise
input never claims high-confidence BPM") builds on it.

**Independent Test**: Feed seeded random onset streams (1 to 16 onsets per second) to the tracker
directly, and seeded white noise and silence through the full pipeline.

**Acceptance Scenarios**:

1. **Given** silence, **When** analysed, **Then** there is never an estimate and the confidence is 0.
2. **Given** random onsets at average rates of 1, 4 and 16 per second (one fixed seed each, 30 s), **When** tracked, **Then** the confidence never reaches 0.5.
3. **Given** loud white noise through the full pipeline, **When** analysed, **Then** the confidence never reaches 0.5.

---

### User Story 5 - Same beats on every run and every CI path (Priority: P2)

CI runs on macOS, the iOS Simulator and Linux. Beat outputs repeat exactly, and the accelerated
and portable paths agree.

**Why this priority**: AUD-016's hand-off ("identical beat outputs on repeated runs").

**Independent Test**: Track one pulse case twice and compare every estimate and beat event bit for
bit; track one case on each path and compare.

**Acceptance Scenarios**:

1. **Given** any input, **When** tracked twice with the same path, **Then** every estimate and beat event is identical in every field (bit for bit).
2. **Given** the same onsets tracked by the accelerated and the portable path, **When** compared, **Then** every estimate and beat event is identical.

### Edge Cases

- Fewer than 4 matched beats (start of a stream, after a reset or a timeout): no estimate, confidence 0, no beat events.
- An onset at another sample rate, or earlier than the previous onset: ignored and counted.
- Advancing the position backwards: ignored and counted; the position never decreases.
- A position jump over several predicted beats (for example a large hop): one beat event, for the latest crossed beat; the skipped ones are counted.
- A re-fit that moves the next predicted beat closer than half a period to the last reported beat: that prediction is not reported again (a beat is reported once).
- A tempo whose refined value falls outside 60–200 BPM: the fit is rejected and the previous estimate kept.
- Onsets on off-beats (eighth notes) lower precision: confidence for real music may be below the synthetic fixtures' values; ANL-006 refines the states.
- More than 64 onsets in the window: the oldest are dropped (bounded memory and work).

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-005-R1**: The tracker MUST accept ANL-004 onset events (sample index, strength, sample rate) and keep those of the last 6 s (at most 64) as its onset history; an onset at another sample rate or earlier than the previous one MUST be ignored and counted.
- **ANL-005-R2**: The tracker MUST accept the stream's current sample position (directly, or as the end of a spectrum frame: frame index + FFT size) so that time passes without onsets; a position earlier than the previous one MUST be ignored and counted.
- **ANL-005-R3**: When an onset is added, the tracker MUST compute a tempo score on a 0.25 BPM grid from 60 to 200 BPM: every pair of onsets at most 4 s apart votes, for n = 1…4, for the periods within the timing tolerance of interval / n, with a triangular weight, a factor 1/n and a recency factor 0.5^(age of the older onset / 2 s); the scores MUST be multiplied by the tempo preference exp(−½ · log2(BPM / 120)²). The best score's period is the coarse period.
- **ANL-005-R4**: If an estimate exists and the score at its tempo is at least 90 % of the best, the coarse period MUST be the estimate's period (hysteresis against octave and neighbour flips).
- **ANL-005-R5**: The tracker MUST find the beat grid (time = anchor + k · period, k an integer) as follows: the anchor is the onset with the largest recency-weighted count of onsets within twice the timing tolerance (35 ms) of the coarse grid through it (the most recent on a tie); then three unweighted least-squares fits of time against k over the onsets on the grid (within twice the tolerance in the first fit, the tolerance afterwards) refine the period and anchor. A fit with fewer than 3 distinct beats, or a tempo outside 60–200 BPM, MUST leave the previous estimate unchanged.
- **ANL-005-R6**: An estimate MUST exist only with at least 4 distinct matched beats, and MUST state: tempo (BPM), period (samples, fractional), anchor beat time, the next predicted beat (the first grid time at or after the current position, rounded to a sample index), confidence, matched beats, onsets in the window, sample rate, and the position it was computed at.
- **ANL-005-R7**: Confidence MUST be precision × coverage × support × freshness, each in 0…1: precision = onsets in the window within the tolerance of the grid / onsets in the window; coverage = matched beats / grid beats from the window's first to its last onset; support = clamp((matched beats − 2) / 6, 0, 1); freshness = 1 up to 1.5 periods after the last matched onset, then falling linearly to 0 at the silence timeout. With no estimate the confidence is 0.
- **ANL-005-R8**: The tracker MUST publish the threshold of "high" confidence (0.5) as a constant; random onsets MUST stay below it (ANL-005-S4).
- **ANL-005-R9**: When the position is 4 s (the silence timeout) or more after the last matched onset, the tracker MUST drop the estimate and clear the onset history; it then behaves like a new tracker except for its counters.
- **ANL-005-R10**: When the position passes a predicted beat (previous position < beat ≤ … < current position, half-open on the right: beat < current position), the tracker MUST report one beat event for the latest such beat, carrying a sequence number (1, 2, 3… over the tracker's lifetime, never reused, not restarted by a reset), the beat's sample index, the tempo, the period, the confidence and the sample rate; a beat closer than half a period to the previously reported beat MUST NOT be reported; skipped beats are counted.
- **ANL-005-R11**: The tracker MUST offer a pull interface only: adding an onset, advancing the position (returns at most one beat event), a convenience that does both for one spectrum frame, the current estimate and confidence, counters and reset. No subscription, queue or event bus (ANL-016's).
- **ANL-005-R12**: The same inputs MUST give bit-identical estimates and beat events on repeated runs (AUD-016-R22). The tracker MUST work without the platform's accelerated math library through a portable path with the same interface; both paths MUST give bit-identical estimates and beat events.
- **ANL-005-R13**: After creation, adding an onset and advancing MUST NOT allocate, lock, log or do I/O (Constitution VII); the onset history, histogram and preference table are created with the tracker, and the per-onset work is bounded (at most 64 onsets). The tracker is confined to the one worker that owns it, like the analyser (ANL-001-R14).
- **ANL-005-R14**: The configuration (sample rate, tempo range, preferred tempo, window, timing tolerance, silence timeout) MUST be validated at creation; invalid values MUST be rejected with an error naming the field.
- **ANL-005-R15**: Reset MUST drop the estimate, the onset history and the position while keeping the beat sequence counter and the counters.
- **ANL-005-R16**: Nothing computed here MAY be passed to projectM (Constitution VIII, ADR-0008 decision 5); no UI is added by this row.
- **ANL-005-R17**: The acceptance tests MUST use a few representative cases (owner rule 7, 2026-11-13: short tests that exist to produce evidence), each run through the spectrum stream (`.silence` lead-in), the ANL-004 detector and the tracker: `pulse-120` at 44.1 kHz with FFT size/hop 2048/512 (typical) and 4096/1024 (the largest supported hop); `pulse-120-accent` at 44.1 kHz, 2048/512; `pulse-132` at 48 kHz, 2048/512 and at 44.1 kHz, 4096/1024. Each run MUST print: converged tempo, time to converge, largest |tempo error| after convergence, beat events after convergence, missed and extra beats, and the largest beat-time error. Wider sweeps, if wanted, belong in the `Bench` package, not the test target.

### Key Entities

- **Beat tracker configuration**: sample rate, minimum and maximum tempo, preferred tempo, window length, timing tolerance, silence timeout.
- **Beat tracker**: onset history (ring of at most 64), score histogram and preference table, current estimate, last matched onset, position, last reported beat, sequence and counters.
- **Beat estimate**: tempo, period, anchor, next beat, confidence and its factors' inputs (matched beats, onsets in window), sample rate, position.
- **Beat event**: sequence number, sample index, tempo, period, confidence, sample rate.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-005-S1**: In 100 % of the 5 representative pulse runs of ANL-005-R17 the run converges within 4.0 s to the fixture tempo within ±1.0 BPM with confidence ≥ 0.8, and stays converged to the end of the loop.
- **ANL-005-S2**: In those runs, after convergence, every catalog onset gets exactly one beat event within one hop (|beat − onset| ≤ hop), with 0 missed and 0 extra beat events.
- **ANL-005-S3**: The 120 → 132 BPM change re-converges within 6.0 s of the change; after pulses stop, the confidence never rises and the estimate is gone within 4.0 s of the last pulse; after a 6 s gap a new tempo converges within 4.0 s of its start.
- **ANL-005-S4**: Silence never yields an estimate; random onsets (1, 4 and 16 per second, one fixed seed each, 30 s) and loud white noise through the pipeline never reach confidence 0.5.
- **ANL-005-S5**: Repeated runs and the two paths give bit-identical estimates and beat events (0 differing fields).
- **ANL-005-S6**: 0 heap allocations when adding onsets and advancing, checked by reading the code; each new test takes about 1–2 s on the Mac host (Debug, at most 10 s) and all new tests together less than 20 s (reported, never asserted; owner rule 7).
- **ANL-005-S7**: Existing behavior unchanged: every existing AnalysisFeatures test passes unchanged.

## Hand-off to ANL-006, ANL-016, MOD-009, MOD-017, SHOW-003, SHOW-010, SHOW-011, VIS-006, VIS-015 and ACC-007

- ANL-006 (tempo confidence states) maps the confidence and its inputs (matched beats, freshness through the position) to stable, searching and uncertain states; "high" starts at 0.5.
- ANL-016 (event bus) wraps the tracker on its worker next to the onset detector; beat sequence numbers never repeat within a tracker's lifetime.
- MOD-009 (tempo-synced LFO) reads tempo, period and anchor to place cycles; MOD-017 and SHOW-003 quantize to the next predicted beat and use "no estimate" as their explicit fallback.
- SHOW-010 (beat grid) draws ticks at anchor + k · period; SHOW-011 (tap tempo) can feed tap times as onsets, or override the estimate in its own layer.
- VIS-006 (beat rings), VIS-015 (tunnel warp) and ACC-007 (haptic beat) consume beat events and gate on confidence.
- Every later row keeps ANL-005-R16: nothing goes into projectM.

## Assumptions

- Onsets come from ANL-004 with its defaults and the `.silence` lead-in; their sample indices are within one hop of the true onsets.
- The normalized stream is 44.1 kHz; fixtures are also checked at 48 kHz. One tracker serves one sample rate.
- Analysis hops up to 1,024 samples are supported for the stated beat-time accuracy; larger hops are outside this row's acceptance.
- Music outside 60–200 BPM is reported at a multiple or fraction inside that range (an octave of the true tempo).
- No new dependencies, no stored data, no network use, no entitlement: the privacy policy and manifest do not change. Persistence: none (the tracker's state lives in memory and is rebuilt from audio).
- Device measurements are not needed for this row's acceptance.
