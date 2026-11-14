# Feature Specification: ANL-006 Tempo Confidence Indicator

**Feature Branch**: `feature/anl-006` (spec directory `088-anl-006-tempo-confidence-indicator`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13

**Input**: User description: "Implement ANL-006 (Tempo confidence indicator) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Expose stable, searching and
uncertain tempo states." Acceptance, verbatim: "Random-noise input never claims high-confidence
BPM." Dependencies: ANL-005 (integrated). Verification: unit tests with synthetic PCM, plus the
simulator. Honor the repository constitution and owner rules 4, 7 and 8."

Identifiers carry the roadmap ID so they never collide with other features: requirements are
`ANL-006-R1…`, success criteria `ANL-006-S1…`, tasks `ANL-006-T01…`. Other features are cited by
their own IDs: ANL-004 (onsets), ANL-005-R7, R8 (beat tracker confidence and its "high" level 0.5),
ANL-016 (analysis bus), SHOW-011-R8 to R14 (tap tempo, tempo source and readout), ACC-001
(`MotionPolicy`), ACC-004 (readout marked static text; the em-dash audit filter), AUD-008 (input
trim on the analysis copy), FR-065 (what the app may store), FR-070 (accessibility).

## Baseline: what exists today (audit of 2026-11-13, commit `e13af72`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Confidence | ANL-005's `AdaptiveBeatTracker` computes confidence = precision × coverage × support × freshness (0…1) on every accepted onset; `highConfidence` = 0.5 (ANL-005-R8). The ANL-016 pipeline publishes it per frame (`AnalysisFrame.bpm`, `beatConfidence`). | A per-frame number; no notion of how long it has held. |
| Tempo source | SHOW-011's `TempoSource` turns the estimate into a `TempoSnapshot`: origin `estimated` only when confidence ≥ 0.5 (`TapTempoRules.minimumEstimateConfidence`) and the BPM is in 60…200, else `none`; a manual (tapped) tempo always wins until Reset. | One threshold, no hysteresis or dwell: a confidence crossing 0.5 back and forth flips the readout between "126 BPM / Detected" and "—" every poll. A low-confidence estimate is hidden entirely. |
| Readout | `TempoControls` in the controls overlay: "120 BPM" over "Manual"/"Detected", or "—"; one static-text element (ACC-004) "Tempo", value "120 BPM, manual" / "126 BPM, detected" / "No tempo". The app polls the analysis every 250 ms on the main actor (`TempoCoordinator`), from its own pipeline while projectM is shown (`runOwnAnalysis`, fed the AUD-008-trimmed analysis tap) or from the native visual's pipeline otherwise. | No searching/uncertain/stable states; nothing tells a user whether a detected tempo can be trusted. |
| Consumers | Only the readout reads the tempo snapshot in the app today; MOD-002 bindings read bands and onsets, not tempo. | None. |
| Noise | ANL-005's tests show random onsets and −10 dBFS white noise stay below 0.5. | Not tested at the readout level, nor with pink noise or over time. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option, recommended option
first.

- Q: What thresholds and times does the indicator use? → A: Enter threshold 0.7, exit threshold 0.5 (ANL-005's "high" level, the same floor the tempo source uses), enter dwell 2.0 s, exit dwell 1.0 s, reacquire time 3.0 s, BPM tolerance 3 % of the reference BPM. Noise that ANL-005 keeps below 0.5 cannot even hold stable, let alone enter it; clean pulses reach confidence ≈ 1 once 8 beats match, so stable follows about 2 s after ANL-005 converges. Rejected: a single threshold (flickers), longer dwells (a 120 BPM track would wait > 8 s) (ANL-006-R4, R5).
- Q: How does a tapped tempo interact with the states? → A: A manual tempo is its own readout state, "Manual", held until Reset exactly as SHOW-011 does today; the indicator keeps tracking the analysis underneath, so Reset shows the analysis's current state immediately (no new dwell). Taps never feed the indicator. Rejected: "manual counts as stable for a while" (would claim a confidence the analysis never measured, and SHOW-011 already keeps manual until Reset) (ANL-006-R7).
- Q: When the tempo changes, is that "searching" or "uncertain"? → A: Leaving stable because the BPM moved beyond the tolerance of the locked BPM (for the exit dwell) is a tempo change: `searching` (no number shown) while the tracker reacquires, for at most the reacquire time; if an estimate is still not stable after that, `uncertain`. Leaving stable because confidence stayed below the exit threshold (BPM unchanged) is `uncertain`. Losing the estimate entirely is `searching` at once. While not stable, a BPM that wanders beyond the tolerance of the run's start BPM restarts the enter dwell (that is the "drifting" case, shown as uncertain) (ANL-006-R2 to R4).
- Q: Do tempo consumers (`TempoSnapshot`, MOD and show rows) change with the indicator? → A: No. The snapshot keeps SHOW-011's rule (estimated from confidence 0.5); the indicator is a separate read-only value next to it that only the readout, the Tap control's value and the Reset announcement use. Changing consumer semantics is out of scope for an S-sized indicator row and would silently alter SHOW-011's tested contract (ANL-006-R10).
- Implementation finding (T04, 2026-11-13): stationary white and pink noise through the real pipeline give ANL-005 no estimate at all (confidence 0, always searching), so they cannot exercise the thresholds. Random noise bursts were added: they give estimates (largest confidence 0.29-0.37), are shown as uncertain at most, and never stable. Inputs were trimmed (white 3 → 2 seeds, 12 → 10 s) and the noise test split in two so each test stays under the 10 s budget in the Linux shape (owner rule 7).
- Implementation finding (T04, 2026-11-13): during the exit dwell after a tempo change the estimate already reports the new BPM; the indicator keeps showing the last BPM within the tolerance until it leaves stable, so a new tempo is never displayed as stable before it earns it (ANL-006-R4).
- Q: How is "uncertain" shown, and are state changes announced? → A: With "≈" before the number and the word "Uncertain"; no dimming (ACC-004's contrast audit runs over the controls) and no animation. State changes are not announced to VoiceOver (an analysis that changes state every few seconds would interrupt the user); the readout's accessibility value carries the state in words whenever it is read. The "—" of the searching state keeps ACC-004's existing em-dash audit filter valid (ANL-006-R8, R9, R11).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The readout tells me whether the tempo can be trusted (Priority: P1)

A performer opens the controls while music plays. At first the tempo readout says it is searching
and shows no number. As the beat becomes clear it shows "≈ 124 BPM" marked uncertain, and once the
estimate has held steady for a moment it shows "124 BPM" marked stable. VoiceOver reads the state in
words.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: Unit tests of the readout texts per state; one UI test on the simulator with a
Debug fake estimate sees the readout change state.

**Acceptance Scenarios**:

1. **Given** no estimate, **When** the controls are shown, **Then** the readout shows "—" with the word "Searching" and no BPM number, and VoiceOver reads "Tempo, Searching for tempo".
2. **Given** an estimate that is not (yet) trusted, **When** the readout is shown, **Then** it shows "≈" before the BPM with the word "Uncertain", and VoiceOver reads "About 124 BPM, uncertain".
3. **Given** an estimate that has held its tempo with high confidence for the dwell time, **When** the readout is shown, **Then** it shows "124 BPM" with the word "Stable", and VoiceOver reads "124 BPM, stable".
4. **Given** a manual (tapped) tempo, **When** the readout is shown, **Then** it shows the tapped BPM with "Manual", exactly as today; Reset returns to whatever state the analysis is in at that moment.

---

### User Story 2 - Noise never claims a confident tempo (Priority: P1)

Whoever checks the analysis (a developer, CI) feeds white noise, pink noise and silence through the
real analysis pipeline and the indicator for several fixed seeds; the indicator never reaches
"stable" and the confidence it reports never reaches the stable threshold.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Package tests with synthetic PCM through the real ANL-016 pipeline, on a
synthetic clock.

**Acceptance Scenarios**:

1. **Given** white noise (2 seeds) and pink noise (2 seeds), 10 s each at a loud level (peak 0.5), 10 s of silence, and random white-noise bursts (30 ms at random times, about 3 per second; 3 seeds, 12 s each), **When** fed through the pipeline and the indicator at the app's 250 ms poll, **Then** the state is never `stable`, the largest confidence seen is below the enter threshold, and the tempo source never reports an estimated tempo.
2. **Given** synthetic 120 BPM and 90 BPM pulse trains, **When** fed the same way, **Then** the state becomes `stable` at the right BPM (±1) within 10 s of the start and stays stable to the end.
3. **Given** 120 BPM pulses that change to 90 BPM, **When** fed the same way, **Then** the state goes `stable` (120) → `searching` or `uncertain` → `stable` (90) within 12 s of the change.

---

### User Story 3 - The indicator does not flicker (Priority: P2)

A confidence that hovers around the threshold, or dips briefly, does not make the readout jump
between states.

**Why this priority**: A flickering state is worse than none.

**Independent Test**: Unit tests with scripted estimate sequences on an injected clock.

**Acceptance Scenarios**:

1. **Given** stable, **When** confidence dips below the exit threshold for less than the exit dwell, **Then** the state stays stable.
2. **Given** a seeded random confidence between 0.45 and 0.75 at a fixed BPM for 60 s, **When** fed at 4 Hz, **Then** the state changes at most twice.
3. **Given** confidence between the exit and enter thresholds, **When** stable, **Then** it stays stable; **When** not stable, **Then** it never becomes stable.

### Edge Cases

- No estimate (analysis stopped, silence timeout, session marker): `searching` at once; no BPM shown.
- Estimate with a non-finite BPM or confidence, or a BPM outside 60…200: treated as no estimate.
- Confidence above 1 or below 0: clamped.
- Times that go backwards (a clock reading earlier than the last): the update is applied with no elapsed time (dwell timers do not advance).
- Analysis stopped and restarted (visual switch, PERF-011 suspension): the indicator restarts from `searching`.
- Manual tempo set while the analysis is stable: the readout shows Manual; the indicator keeps tracking underneath.
- Reduce Motion / Reduce flashing: state changes are not animated (no animation is added; if any is, it goes through `MotionPolicy`).

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-006-R1**: An indicator MUST classify the analysis tempo, on every update with an estimate (BPM and confidence, or none) and a monotonic time, into exactly one of `searching`, `uncertain` and `stable`.
- **ANL-006-R2**: `searching` MUST mean: no usable estimate, or reacquiring after the tempo moved away from a stable tempo. While searching no BPM is reported.
- **ANL-006-R3**: `uncertain` MUST mean: an estimate exists but has not held the enter threshold and one tempo for the enter dwell, or a stable estimate's confidence fell below the exit threshold for the exit dwell, or the tempo wanders (moves beyond the BPM tolerance) while not stable.
- **ANL-006-R4**: `stable` MUST be entered only after the confidence stayed at or above the enter threshold, with the BPM within the tolerance of the BPM at the start of that run, continuously for the enter dwell; it MUST be left only after the exit condition (confidence below the exit threshold, or BPM beyond the tolerance of the locked BPM) held continuously for the exit dwell.
- **ANL-006-R5**: The thresholds and times MUST be fixed values with the enter threshold above the exit threshold (hysteresis) and the exit threshold at least ANL-005's "high" level, so noise that ANL-005 keeps below 0.5 can never be stable.
- **ANL-006-R6**: The indicator MUST be deterministic and read no clock: every time is an argument; it runs on Linux.
- **ANL-006-R7**: A manual (tapped) tempo MUST show as "Manual" until Reset, as today (SHOW-011-R8); the indicator MUST keep tracking the analysis underneath so Reset shows its current state without restarting the dwell.
- **ANL-006-R8**: The readout MUST show one short state word plus the BPM: "Stable" with "120 BPM"; "Uncertain" with "≈120 BPM"; "Searching" with "—" (no number); "Manual" with "120 BPM". The accessibility element stays one static-text element labeled "Tempo" whose value says the state in words: "120 BPM, stable", "About 120 BPM, uncertain", "Searching for tempo", "120 BPM, manual".
- **ANL-006-R9**: The readout MUST NOT reduce contrast (no dimming) so ACC-004's audit stays clean; uncertainty is shown with "≈" and the word.
- **ANL-006-R10**: What tempo consumers read (`TempoSnapshot`) MUST be unchanged; the indicator is an additional read-only value.
- **ANL-006-R11**: No new setting, no new stored data, no network; no animation outside `MotionPolicy`.
- **ANL-006-R12**: The Reset announcement and the Tap control's value MUST use the same state words as the readout.

### Key Entities

- **Tempo confidence state**: searching, uncertain or stable.
- **Indicator rules**: enter and exit thresholds, enter and exit dwell times, reacquire time, BPM tolerance.
- **Indicator**: the current state, the BPM and confidence it reports, the locked BPM while stable, the start of the current candidate run, the start of the current exit condition, and a count of state changes.
- **Readout state**: manual, stable, uncertain or searching, with the BPM to show.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-006-S1**: White noise (2 seeds), pink noise (2 seeds) and silence (10 s each), and random noise bursts (3 seeds, 12 s each) never reach `stable`, never report confidence at or above the enter threshold, and never yield an estimated tempo snapshot (the roadmap acceptance).
- **ANL-006-S2**: 120 BPM and 90 BPM pulse trains reach `stable` at ±1 BPM within 10 s and stay stable.
- **ANL-006-S3**: A 120 → 90 BPM change leaves `stable` and returns to `stable` at 90 BPM within 12 s of the change.
- **ANL-006-S4**: A borderline confidence sequence (60 s, 4 Hz) changes state at most twice; short dips do not leave stable.
- **ANL-006-S5**: The readout text, state word and accessibility value are exact for every state, and a UI test of at most 30 s sees the readout reach stable and then move to uncertain (the starting searching/uncertain phase passes before the controls can be read reliably, so unit tests cover it).
- **ANL-006-S6**: Every existing PerformanceControl test and the existing tap-tempo app and UI tests pass (updated only where the "Detected"/"No tempo" wording changed).

## Assumptions

- The app keeps polling every 250 ms (SHOW-011 research D5); the indicator is updated on each poll with the monotonic clock.
- The analysis follows AUD-008's trimmed analysis tap, so the trim changes what the indicator sees exactly as it changes the estimate; nothing here touches the trim.
- Simulator results are not device evidence; this row's acceptance is synthetic PCM through the real pipeline (unit tests).
