# Feature Specification: AUD-008 Input Trim

**Feature Branch**: `feature/aud-008` (spec directory `086-aud-008-input-trim`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (device task AUD-008-T13 open)

**Input**: User description: "Implement AUD-008 (Input trim) from docs/FEATURE_ROADMAP_AUTONOMOUS.md
line 95. Observable behavior, verbatim: "Add bounded gain before feature extraction, without clipping
PCM sink buffers." Acceptance, verbatim: "Test tone gain changes levels predictably and saturates
safely." Verification: unit tests plus the simulator; device testing for routes and interruptions is
last. Honor the repository constitution and owner rules 4, 7 and 8."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `AUD-008-R1…`, success criteria `AUD-008-S1…`, tasks `AUD-008-T01…`. Requirements
of other features are cited by their own IDs: FR-065 (what the app may store), FR-070
(accessibility); ANL-001-R9 (the analysis tap), ANL-016-R9 (capture-session generation), VIS-001-R14
(native visuals read the tap), VIS-003-R2 (the oscilloscope's pass-through tap), SHOW-011 (tap
tempo's own analysis).

## Baseline: what exists today (audit of 2026-11-13, commit `9f6839e`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

Audio path, from every source to the analysis and the visuals:

1. **Sources** (System/App Capture, Microphone, In-App Playback with the audio library of AUD-001 to
   AUD-007) deliver PCM to the `PCMSink`'s real-time ring (the audio callback only copies).
2. **Analysis work queue** (`AudioAnalyzer`, every 10 ms, never on the audio callback) drains the
   sink, measures levels for the audio-state classifier (silence, active audio) and runs the
   `Normalizer` (Float32 interleaved stereo, 44.1 kHz) into the `NormalizedPCMRing`.
3. **The normalized ring** (`CaptureManager.normalizedOutput`) is read by the projectM renderer
   (`renderer.attach(pcm:)`): this is the engine's PCM input.
4. **The analysis tap** (ANL-001-R9) is a second ring that receives a copy of every write to the
   normalized ring; it has exactly one consumer at a time: the shown native host's
   `LiveBandAnalyzer` (ANL-016 pipeline: spectra, bands, onsets, tempo), with VIS-003's
   `WaveformTap` passing reads through on the way, or, while projectM is shown, the tap tempo's own
   analysis (`TempoCoordinator.runOwnAnalysis`). Every native host (circular and linear spectrum,
   oscilloscope, camera, photo, video, text) gets the tap from `AppCoordinator` as `manager.analysisTap`.
5. **Playback** (In-App Playback) goes to the output device through the system mixer; the app's
   analysis never touches it. Recording (REC rows) captures rendered frames, not this PCM.

| Area | Today | Gap for this row |
|---|---|---|
| Gain before feature extraction | None. The tap's samples reach the FFT and band extraction at the source's level. | A bounded, user-set trim on the analysis copy only. |
| Normalization or AGC | The Normalizer converts format and rate only; no gain, no AGC. Band normalization (ANL-002) maps decibels with a fixed −80 dB floor. | Quiet sources (microphone across a room) give dim bars; loud ones pin them. |
| Saturation | None needed today (no gain). | A gain above 0 dB must stay bounded and finite. |
| Settings | No audio-level control. | One control with a dB readout and Reset. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option, recommended option
first.

- Q: Where does the trim apply? → A: On the analysis read only: a pass-through reader wraps the
  analysis tap, forwards each read, then scales the frames just read in the consumer's own scratch
  buffer (the copy the pipeline already owns) before FFT and band extraction. The PCM sink, the
  normalized ring (projectM's input), the audio-state classifier's levels, playback and every other
  consumer stay bit-identical. Rejected: gain in the Normalizer or the sink (would change projectM's
  input and the silence classification); gain inside the ANL-016 pipeline (ANL-003 is changing it
  in parallel, and the tempo's own analysis would need a second change) (AUD-008-R1, R2).
- Q: Does the oscilloscope show trimmed or raw samples? → A: Trimmed. It is an analysis display:
  the wrapper sits in front of VIS-003's `WaveformTap`, so the line and the bands move together
  (AUD-008-R3).
- Q: One trim for all sources, or one per source? → A: One global trim, persisted. It describes how
  the user wants the analysis to react, not a property of a source; per-source values would need a
  source-keyed store and a UI to explain which applies. A per-source trim can be added later
  without changing the processing (AUD-008-R6).
- Q: What range, steps and saturation? → A: −12 dB to +24 dB in 1 dB steps, default 0 dB. Gain =
  10^(dB/20). At 0 dB the processing is skipped entirely (bit-exact). Otherwise each sample is
  multiplied and passed through a soft clip: linear up to a knee at 0.5 (−6 dBFS), then a cubic
  curve that meets ±1 with zero slope at |x| = 1.25 and stays at ±1 beyond; NaN reads as 0 and ±∞
  as ±1, so the output is always finite and in [−1, 1]. Rejected: a hard clip (adds strong
  harmonics that light up high bands); tanh (needs libm per sample and never reaches the bound
  exactly) (AUD-008-R4, R5).
- Q: How do gain changes avoid zipper noise, and what happens when the source changes? → A: Linear
  ramp of the linear gain over 2,048 frames (≈ 46 ms, one FFT window) from the current gain to the
  new target, per frame, carried across reads; a new target during a ramp starts a new ramp from the
  current gain. A new capture session (the tap's session generation changes: start, restart or
  source switch) snaps the gain to the target, because the analysis starts afresh anyway. A new
  wrapper (a newly shown visual) starts at the target (AUD-008-R5, R7).
- Q (clarify pass): Does the trim affect projectM presets, the audio-state indicator or tap tempo?
  → A: projectM and the audio-state indicator: no (they read the sink and the normalized ring, which
  stay raw; Constitution VIII: nothing computed for the app's analysis reaches projectM). Tap tempo's
  detected estimate: yes, it is feature extraction on the same tap and gets the same wrapper. The
  Settings footer says so in plain words (AUD-008-R1, R8).
- Q (clarify pass): Which control? → A: A slider from −12 to +24 dB (1 dB steps) with a "+6 dB"
  style readout and a "Reset to 0 dB" button, in an "Audio Analysis" section of Settings, shown
  for every visual; VoiceOver reads "Input trim" and the signed value. Rejected: a stepper alone (36
  taps across the range) (AUD-008-R8, R9).
- Q (clarify, 2026-11-13): Do MOD-002 audio-feature bindings (for example glow following the level)
  see the trimmed analysis? → A: Yes. They read the same analysis pipeline's frames, so they follow
  the trim like the bars; nothing else to configure (AUD-008-R11).
- Q (clarify, 2026-11-13): Is the trim part of a scene, a show cue or a scene archive? → A: No. It is
  a device-level user setting like Reduce flashing: scenes and cues describe the look, the trim
  describes the room's audio level. SceneFormat, autosave and show documents are unchanged
  (AUD-008-R6).
- Q (clarify, 2026-11-13): Does CaptureLab or a diagnostics export carry the trim? → A: No.
  CaptureLab measures sources at their real level (FR-031 evidence must be unaltered); the trim lives
  only in the projectM-iOS app (AUD-008-R1).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Make quiet or loud audio drive the visuals well (Priority: P1)

A user visualizing a quiet microphone signal sees dim bars. They open Settings, raise "Input trim"
to +12 dB, and the native visuals react more strongly. What they hear, what projectM receives and
what any recording captures do not change. Later they tap "Reset to 0 dB". The choice is remembered
on the next launch.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: In the simulator, set the trim to +24 dB (the slider's end stop: XCUITest drags
land only within a few steps of a mid position), relaunch, check +24 dB is shown, tap Reset, check 0 dB.
Intermediate values and their persistence are unit-tested.

**Acceptance Scenarios**:

1. **Given** Settings open, **When** the user moves Input trim, **Then** the readout shows the signed value in whole dB ("+6 dB", "0 dB", "−12 dB") and VoiceOver reads the same value.
2. **Given** a trim of +6 dB (unit test) or +24 dB (UI test), **When** the app is relaunched, **Then** Settings shows that value.
3. **Given** any trim, **When** the user taps "Reset to 0 dB", **Then** the trim is 0 dB and is stored.

---

### User Story 2 - A test tone's levels change predictably and saturate safely (Priority: P1)

A fixed test tone analysed at trims of −12, 0, +6 and +24 dB gives levels that follow the gain
exactly while the signal stays below the knee, and stay bounded and finite when the gain drives it
past full scale.

**Why this priority**: It is the roadmap's acceptance criterion.

**Independent Test**: Unit tests on the host and in the Linux shape.

**Acceptance Scenarios**:

1. **Given** a −20 dBFS 1 kHz sine, **When** trimmed by −12, +6 or +12 dB, **Then** its RMS changes by that many dB within 0.05 dB.
2. **Given** the same tone through the band analysis, **When** trimmed by −12 or +6 dB, **Then** the band holding the tone moves by trim/80 in normalized units (the band floor is −80 dB) within 0.005.
3. **Given** a full-scale tone, **When** trimmed by +24 dB, **Then** every sample is finite and within [−1, 1], and NaN or infinite input samples come out finite.
4. **Given** 0 dB, **When** any signal is read, **Then** the output is bit-identical to the input.
5. **Given** a jump of the target from −12 to +24 dB, **When** read in buffers of varying size, **Then** no frame-to-frame gain change exceeds the ramp's bound and the target is reached after 2,048 frames.

---

### User Story 3 - The sinks stay untouched (Priority: P1)

Whatever the trim, projectM's PCM, the audio-state levels and playback are the same as without the
feature.

**Why this priority**: The row's constraint ("without clipping PCM sink buffers").

**Independent Test**: A unit test at the seam: write a tone into the normalized ring with a tap,
read the tap through the trim at +24 dB, and compare the main ring's output bit for bit with a run
without the trim.

**Acceptance Scenarios**:

1. **Given** a ring with an analysis tap and a +24 dB trim reading the tap, **When** the main ring is read, **Then** its frames equal the written frames bit for bit.

### Edge Cases

- Trim changed while audio flows: the ramp starts from the current gain; no step.
- Trim changed while no audio flows: the next frames ramp from the previous gain.
- Capture restart or source switch: the gain snaps to the target at the new session's first read.
- Stored value missing, NaN or out of range: 0 dB, or clamped to the range.
- Silence: stays silence (0 × gain = 0).
- Input samples above full scale at 0 dB: passed through unchanged (bit-exact rule).

## Requirements *(mandatory)*

### Functional Requirements

- **AUD-008-R1**: The trim MUST apply only to the analysis tap's consumer copy (ANL-001-R9), after the tap and before spectra, bands, onsets and tempo. The PCM sink, the normalized ring read by projectM, the audio-state classifier's levels and playback MUST be unchanged bit for bit for any trim.
- **AUD-008-R2**: The trim MUST be a pass-through reader around the tap: it forwards the wrapped reader's frame count and capture-session generation (ANL-016-R9) unchanged and scales only the frames it returned, in the caller's buffer.
- **AUD-008-R3**: The oscilloscope (VIS-003) MUST show the trimmed samples: the trim sits in front of `WaveformTap`.
- **AUD-008-R4**: Range −12…+24 dB, default 0 dB; values are clamped to the range and NaN reads as 0 dB. Linear gain = 10^(dB/20).
- **AUD-008-R5**: At unity gain with no ramp in progress the reader MUST return the wrapped reader's samples bit-identical. Otherwise each sample y = softClip(x · g): |v| ≤ 0.5 → v; 0.5 < |v| < 1.25 → sign(v)·(0.5 + 0.5·(u − 4u³/27)) with u = (|v| − 0.5)/0.5; |v| ≥ 1.25 → sign(v); NaN → 0. Outputs MUST be finite and within [−1, 1].
- **AUD-008-R6**: One global trim for all sources, persisted under the user-setting key `settings.inputTrim.decibels` (a Double); it is not part of scenes, show cues or scene archives, and CaptureLab has no trim. This amends FR-065: exactly this one key is added to what may be stored, and the device privacy check's allowed list gains it.
- **AUD-008-R7**: Gain changes MUST ramp linearly in linear gain over 2,048 frames per change, carried across reads, so the per-frame gain change never exceeds (g(+24) − g(−12)) / 2,048; a new reader starts at the target, and a change of the session generation snaps to the target.
- **AUD-008-R8**: Settings MUST offer, for every visual, an "Audio Analysis" section with an "Input trim" slider (−12…+24 dB, 1 dB steps), a readout of the signed whole-dB value, a "Reset to 0 dB" button, and a footer saying the trim changes only how strongly the native visuals and tempo detection react, not what is heard, projectM or recordings.
- **AUD-008-R9**: Accessibility (FR-070): the slider's label is "Input trim" and its value the signed readout ("+6 dB", "0 dB", "−12 dB"); the button's label is "Reset to 0 dB"; stable identifiers `inputTrimSlider`, `inputTrimValue`, `inputTrimReset`.
- **AUD-008-R10**: Real-time safety (Constitution VII): the reader holds only scalar state, allocates nothing after creation, takes no lock (one atomic load per read) and never runs on an audio callback (it runs on the analysis worker).
- **AUD-008-R11**: Every native host (and with it MOD-002's audio-feature bindings) and the tap tempo's own analysis MUST receive the trimmed tap; a trim change applies to the running analysis without restarting the source or the visual.

### Key Entities

- **Input trim setting**: the target in dB (user setting).
- **Trim control**: the shared target, written by the UI, read by the analysis worker.
- **Trim state** (per reader): current linear gain, target, ramp step and frames remaining, last session generation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-008-S1**: At −12, +6 and +12 dB a −20 dBFS sine's RMS changes by the trim within 0.05 dB; at +24 dB a full-scale sine's samples are all within [−1, 1] and finite.
- **AUD-008-S2**: At 0 dB, 100 % of output samples are bit-identical to the input.
- **AUD-008-S3**: The tone's band value moves by trim/80 within 0.005 at −12 and +6 dB.
- **AUD-008-S4**: No frame-to-frame gain change exceeds the ramp bound; the target is reached after exactly 2,048 frames.
- **AUD-008-S5**: projectM's ring output is bit-identical with and without a +24 dB trim on the tap.
- **AUD-008-S6**: Setting +24 dB, relaunching and resetting works in one UI test of at most 30 s.
- **AUD-008-S7**: Every existing AudioCore, VisualGenerators and app test passes unchanged.

## Assumptions

- The tap is Float32 interleaved stereo at 44.1 kHz (normalized ring format).
- Device checks of routes and interruptions with a trim set are `{device}` work for the roadmap's final phase; simulator results are not evidence for them.
- No new stored data besides the one user-setting key; no network; the privacy manifest does not change.
