# Research: ANL-006 Tempo Confidence Indicator

## ANL-006-D1 Where the indicator lives

- **Decision**: a value type `TempoConfidenceIndicator` in `PerformanceControl`, beside SHOW-011's
  `TempoSource`, fed the same `TempoEstimate` plus a monotonic time.
- **Rationale**: the tempo source already owns "what tempo do consumers see"; the indicator is the
  same input viewed over time. Pure Swift, every time an argument (SHOW-011-R11 style), runs on
  Linux. The acceptance tests can drive it from the real ANL-016 pipeline with
  `PerformanceControlAnalysis`'s reader, like `TempoBusEndToEndTests`.
- **Alternatives**: inside `AdaptiveBeatTracker` (changes ANL-005's tested output and the bus;
  AnalysisFeatures' Linux-shape suite already takes ≈ 81 s); inside `TempoCoordinator` (app only,
  not Linux-testable); changing `TempoSnapshot` (alters consumer semantics, rejected in
  Clarifications).

## ANL-006-D2 Thresholds and times

- **Decision**: enter 0.7, exit 0.5, enter dwell 2.0 s, exit dwell 1.0 s, reacquire 3.0 s, BPM
  tolerance 3 % (relative to the run's start BPM, or the locked BPM while stable).
- **Rationale**: ANL-005's confidence is precision × coverage × support × freshness; support alone
  stays ≤ 0.5 until 6 beats match and reaches 1 at 8, so a clean track climbs from 0 to ≈ 1 within a
  few beats of convergence. ANL-005's S4 tests keep random onsets and −10 dBFS noise below 0.5, so an
  exit threshold at 0.5 means noise could not even hold stable, and the enter threshold 0.7 leaves a
  margin. 2 s ≈ 4 beats at 120 BPM: long enough to reject a lucky stretch, short enough that a
  120 BPM track is stable in ≈ 6 s. 1 s exit dwell rides over a single missed beat (freshness falls
  only after 1.5 periods). 3 % covers the tracker's fit jitter (≈ ±0.5 BPM) and a DJ's pitch
  nudge, while a real tempo change (120 → 90 is 25 %) leaves it at once.
- **Alternatives**: one threshold at 0.5 (today's readout flips "Detected"/"—" on every crossing);
  4 s dwell (a 90 BPM track would need ≈ 10 s); an absolute ±2 BPM tolerance (too tight at 200 BPM,
  too loose at 60).

## ANL-006-D3 State rules

- **Decision** (per update with estimate `e` at time `t`; `e` usable when BPM and confidence are
  finite and BPM is in 60…200, confidence clamped to 0…1):
  - no usable `e`: → `searching` (clears the run, the exit timer and the lock).
  - `stable`: the exit condition is "confidence < exit" or "BPM beyond tolerance of the locked BPM".
    When it has held for the exit dwell: BPM departure → `searching` (reacquiring, remember `t`),
    else → `uncertain`. The run restarts at `t`. Otherwise stay stable (and clear the exit timer).
  - `searching` / `uncertain` with usable `e`: the run is the time since confidence ≥ enter with
    the BPM within tolerance of the run's first BPM; a weak update clears it, a BPM outside the
    tolerance restarts it at `t`. Run ≥ enter dwell → `stable` (lock the current BPM). Else, from
    `searching` without a reacquire time (no estimate before) → `uncertain`; from reacquiring
    searching → `uncertain` once the reacquire time has passed.
  - time earlier than the last update: treated as the last time (no elapsed time).
- **Rationale**: the minimal machine that has hysteresis on both value and time, separates
  "nothing" from "not trusted", and models a tempo change as reacquiring.

## ANL-006-D4 Manual tempo

- **Decision**: `TempoReadout.manual(bpm)` whenever the snapshot is manual; the indicator keeps
  running underneath; taps never feed it. See Clarifications.

## ANL-006-D5 Readout presentation

- **Decision**: two lines as today: the number line ("120 BPM", "≈120 BPM", "—") and the word line
  ("Stable", "Uncertain", "Searching", "Manual"). Accessibility value: "120 BPM, stable",
  "About 120 BPM, uncertain", "Searching for tempo", "120 BPM, manual". No dimming (ACC-004's
  contrast audit), no animation (ACC-001), no announcements on state changes.
- **Strings**: built in typed `let` steps returning `String` from `switch` statements; the view
  passes finished strings to modifiers (Xcode 26 type-checker lesson).

## ANL-006-D6 Test inputs

- **Decision**: white noise from a fixed-seed 64-bit LCG (uniform, peak 0.5, seeds 1, 2, 3); pink
  noise from the same LCG through Paul Kellet's economy filter (peak-normalized to 0.5, seeds 4, 5);
  silence; 12 s each, stereo 44.1 kHz through `NormalizedPCMRing`'s analysis tap and a real
  `AnalysisPipeline` stepped synchronously; the indicator updated every 250 ms of audio (the app's
  poll) on the sample clock. Pulses: AUD-016 `ToneGenerator` pulse trains at 120 and 90 BPM (2 ms,
  amplitude 0.5), 12 s; the change test plays 12 s at 120 then 14 s at 90.
- **Rationale**: the real path the app uses (pipeline → reader → estimate), deterministic, a few
  representative cases (owner rule 7).

## ANL-006-D7 UI test fake

- **Decision**: DEBUG launch argument `-uitestTempoEstimate 120:0.9:40:0.3`: the poll reports
  120 BPM at 0.9 for the first 40 polls (10 s), then 0.3. The UI test waits for
  "120 BPM, stable", then for "About 120 BPM, uncertain".
- **Rationale**: no fake for the analysis existed (SHOW-011's UI test only fakes the tap clock);
  replacing the poll's result keeps the real coordinator, indicator and view in the loop.
