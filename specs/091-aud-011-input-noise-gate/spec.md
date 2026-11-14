# Feature Specification: AUD-011 Input Noise Gate

**Feature Branch**: `feature/aud-011` (spec directory `091-aud-011-input-noise-gate`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement AUD-011 (Input noise gate) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md line 98. Observable behavior, verbatim: "Suppress low-level
ambient mic noise using configurable threshold and hysteresis." P1, M. Acceptance, verbatim:
"Silence fixture remains gated; tone crossing threshold opens within configured attack."
Verification: unit tests plus the simulator; device testing for routes and interruptions is last.
Applies only to the analysis copy, like AUD-008 (input trim) and AUD-009 (channel selection);
projectM, the sink, the classifier and playback stay bit-identical."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `AUD-011-R1…`, success criteria `AUD-011-S1…`, tasks `AUD-011-T01…`. Requirements
of other features are cited by their own IDs: FR-011 (the audio-state classifier's thresholds),
FR-065 (what the app may store), FR-070 (accessibility); ANL-001-R9 (the analysis tap), ANL-016-R9
(capture-session generation), VIS-003-R2 (the oscilloscope's pass-through tap), AUD-008-R1…R11 (the
input trim), AUD-009-R1…R10 (the channel selection).

## Baseline: what exists today (audit of 2026-11-13, commit `97bb762`)

This is a gap row. The audit confirms the gap.

- **Microphone path**: `MicrophoneSource` with `AVMicrophoneBackend` runs the audio session in
  `.record` / `.measurement` mode, which turns off the system's voice processing (no automatic gain,
  no noise suppression). Room noise (air conditioning, fans, hiss of the built-in microphone) reaches
  the PCM sink unchanged; the Normalizer duplicates the mono input to L = R; the analysis tap
  (ANL-001-R9) feeds the native visuals and tempo detection through `AppCoordinator.trimmedAnalysisTap`
  = tap → `ChannelSelectionReader` (AUD-009) → `InputTrimReader` (AUD-008) → `WaveformTap` (VIS-003)
  → analysis pipeline. With no music playing, the bars and the oscilloscope therefore twitch with
  room noise, and AUD-008's boost (up to +24 dB) makes it worse.
- **Audio-state classifier** (`AudioStateClassifier`, FR-011): peak ≥ −50 dBFS for 250 ms → active,
  < −60 dBFS for 2 s → silent. It drives the "Listening/Silent" truthfulness indicator from the
  sink's levels, before the analysis tap. It is a different thing from a gate (it labels, it does not
  mute) and this row does not change it.
- **Other sources**: System/App Capture and In-App Playback deliver digital audio with no ambient
  noise floor.

| Area | Today | Gap for this row |
|---|---|---|
| Low-level room noise in the analysis | Passed through; visuals react to it. | An optional gate mutes the analysis copy while the level stays below a threshold. |
| Settings | "Audio Analysis": input trim (AUD-008), analysis channel (AUD-009). | One more section: noise gate on/off and threshold. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option, recommended option
first.

- Q: Does the gate apply to every source or only the microphone? → A: Only while the active source
  is Microphone. The roadmap says "ambient mic noise", and capture and playback have no ambient
  floor: gating them would only cut quiet passages and fades out of the visuals. The setting is one
  global on/off and threshold; with another source the analysis copy passes through bit-exact
  whatever the setting (AUD-011-R3).
- Q: Where in the analysis chain does the gate sit? → A: After the trim: tap → channel selection →
  trim → gate → `WaveformTap` → pipeline. The threshold is then measured on exactly what the
  analysis sees (after the user's channel choice and trim), and the gate's silence stays silence
  through the oscilloscope and every analyzer. Rejected: before the trim (the trim would move the
  effective threshold, and a boosted noise floor could exceed it) (AUD-011-R1).
- Q: What does the detector measure, and in which unit? → A: A peak envelope in dBFS: per frame the
  larger of |L| and |R|, held by an instant-attack, 10 ms exponential-release envelope. Peak matches
  the classifier's units (FR-011), reacts within one sample to an onset (needed for a 5 ms attack),
  and costs one compare and one multiply per frame. Rejected: windowed RMS (adds a window's latency
  to the opening) (AUD-011-R4).
- Q: Which law, thresholds and times, and what is the closed level? → A: Open threshold T
  (Settings, −80…−20 dBFS in 1 dB steps, default −50 dBFS); close threshold T − H with hysteresis
  H = 6 dB; attack 5 ms, hold 100 ms, release 150 ms; closed level full mute (gain 0, −∞ dB). The
  gain ramps linearly (attack 0 → 1 in 5 ms, release 1 → 0 in 150 ms), never switches. Full mute
  because the row's acceptance demands a gated silence fixture and a residual floor would still move
  the bars. Every parameter is bounded in the engine: T −80…−20 dBFS, H 0…20 dB, attack 0.5…50 ms,
  hold 0…1,000 ms, release 10…2,000 ms (AUD-011-R5, R6).
- Q: Which parameters does Settings expose? → A: An on/off toggle (off by default) and the
  threshold slider. Hysteresis and times stay fixed at the defaults in the app: they are
  configurable in the engine (tests use other values), but exposing four more sliders would add
  testing and accessibility surface for little value. Two keys: `settings.noiseGate.enabled` (Bool,
  default false) and `settings.noiseGate.thresholdDecibels` (Double, default −50) (AUD-011-R7, R8).
- Q: What happens when the gate is switched on or off, or a new capture session starts? → A: Off,
  or a non-microphone source: bit-exact pass-through with no state kept. On (or a new session while
  on): the gate starts closed with an empty envelope, so a quiet room stays gated from the first
  frame and music opens it within the attack. A threshold change applies at the next read (the
  state machine continues) (AUD-011-R9).
- Q: Should Settings or the visualizer show whether the gate is currently open? → A: No. The row
  asks for suppression, not metering; the analysis worker's state would need a second atomic path to
  the UI and a live indicator in Settings, which is closed while the visualizer runs. The visuals
  themselves show the effect. Recorded as out of scope (AUD-011-R7).
- Q: How does the gate know the active source is the microphone? → A: The app sets a "microphone
  source" flag on the shared gate control whenever it starts a source (true for Microphone, false
  for the others) and clears it on Stop; the analysis reader reads it with the enabled flag at each
  read. A source started while the gate is on therefore starts gated from its first read, and
  switching to playback passes through from the next read (AUD-011-R3, R9).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Quiet room, still visuals (Priority: P1)

A user visualizes the microphone in a room with a fan. With "Noise gate" on in Settings, the native
visuals and the oscilloscope stay still while nobody plays music; when music starts they react at
once, and they fall still again shortly after the music stops. What is heard, what projectM receives
and recordings are unchanged.

**Why this priority**: It is the row's observable behavior and acceptance.

**Independent Test**: Unit tests on the host and in the Linux shape with fixtures (silence, noise,
a stepped tone).

**Acceptance Scenarios**:

1. **Given** the gate on at −50 dBFS, **When** digital silence followed by noise at −70 dBFS RMS is analysed, **Then** every output sample is zero.
2. **Given** the same gate, **When** a 1 kHz tone steps from −80 to −30 dBFS, **Then** the gain is within 1 dB of unity no later than the configured attack plus one buffer (measured in sample frames from the step).
3. **Given** the gate open, **When** the tone stops, **Then** the gain stays at unity for the hold time and reaches zero after the hold plus the release (± one buffer).
4. **Given** a tone whose level sits between the close and open thresholds, **When** analysed, **Then** a closed gate stays closed and an open gate stays open (no chatter).

---

### User Story 2 - Turn it on and set the threshold (Priority: P1)

In Settings → Audio Analysis the user turns on "Noise gate" and moves "Gate threshold". The choice
is remembered on the next launch. With another source than the microphone nothing changes.

**Independent Test**: A UI test toggles the gate and checks the threshold control and readout; a
unit test covers persistence (a new store on the same defaults).

**Acceptance Scenarios**:

1. **Given** Settings open, **When** the user looks at Audio Analysis, **Then** a "Noise gate" toggle is off and the threshold slider reads "−50 dBFS" and is disabled.
2. **Given** the toggle turned on, **When** the user moves the slider, **Then** the readout shows the whole-dBFS value and VoiceOver reads the same value.
3. **Given** the gate on with −40 dBFS, **When** the app is relaunched (unit test), **Then** both values are restored.
4. **Given** the gate on, **When** the source is System/App Capture or In-App Playback, **Then** the analysis copy is bit-identical to the input.

---

### User Story 3 - The sinks stay untouched (Priority: P1)

Whatever the gate does, projectM's PCM, the audio-state levels and playback are the same as without
the feature.

**Independent Test**: The AUD-008/AUD-009 seam test with all three readers on the tap.

**Acceptance Scenarios**:

1. **Given** a ring with an analysis tap read through selection, trim and a closed gate, **When** the main ring is read, **Then** its frames equal the written frames bit for bit, while the analysis copy is muted.

### Edge Cases

- Gate turned on during a quiet passage: it starts closed (no burst of noise).
- Gate turned off while closed: the next read passes the input through unchanged (an instant step in the analysis only; acceptable, it is a deliberate user action).
- Threshold moved while open: the open/close decisions use the new value from the next read.
- NaN input samples: counted as level 0 by the detector; output is 0 while closed and x · gain while open (NaN propagates only while open, as without the gate; the trim, when active, has already removed it).
- Source switch or capture restart: a new session starts the gate closed.
- Stored values missing, NaN or out of range: off and −50 dBFS, or clamped.

## Requirements *(mandatory)*

### Functional Requirements

- **AUD-011-R1**: The gate MUST apply only to the analysis tap's consumer copy, after AUD-008's trim and before `WaveformTap` and the pipeline (tap → selection → trim → gate). The PCM sink, projectM's ring, the audio-state classifier and playback MUST be unchanged bit for bit.
- **AUD-011-R2**: The gate MUST be a pass-through reader: it forwards the wrapped reader's frame count and session generation unchanged and changes only the frames it returned, in the caller's buffer.
- **AUD-011-R3**: The gate MUST be active only when it is enabled AND the active source is Microphone (a flag the app sets when it starts a source and clears on Stop); otherwise the output MUST be bit-identical to the input.
- **AUD-011-R4**: Detector: per frame e = max(max(|L|, |R|), e · r) with r = exp(−1 / (0.010 s · 44,100 Hz)); NaN magnitudes count as 0. Thresholds compare e against 10^(dBFS/20).
- **AUD-011-R5**: Law: closed (gain 0) → when e ≥ open threshold, attack: the gain rises linearly by 1/attackFrames per frame to 1 (open). While open, e ≥ close threshold re-arms the hold; after holdFrames below the close threshold, release: the gain falls linearly by 1/releaseFrames per frame to 0 (closed). During release, e ≥ open threshold starts the attack again from the current gain; e between close and open thresholds continues the current phase. Output y = x · gain; gain 0 writes exactly 0.
- **AUD-011-R6**: Parameters and bounds: open threshold −80…−20 dBFS (default −50, NaN → default); hysteresis 0…20 dB (default 6; close = open − hysteresis); attack 0.5…50 ms (default 5); hold 0…1,000 ms (default 100); release 10…2,000 ms (default 150). Times convert to whole frames at 44.1 kHz, at least 1.
- **AUD-011-R7**: Settings → Audio Analysis MUST offer a "Noise gate" section: a toggle (default off), a "Gate threshold" slider −80…−20 dBFS in 1 dB steps disabled while off, a readout ("−50 dBFS", U+2212 minus), and a footer saying it applies to the microphone only and changes only how the native visuals and tempo detection react. No live open/closed indicator.
- **AUD-011-R8**: Persisted under `settings.noiseGate.enabled` (Bool) and `settings.noiseGate.thresholdDecibels` (Double); device-level user settings, not part of scenes, show cues, archives or CaptureLab. This amends FR-065 by exactly these two keys; the device privacy check's allowed list gains them; `-uitestResetNotice` clears them.
- **AUD-011-R9**: Off or inactive keeps no state; becoming active, or a session-generation change while active, starts closed with e = 0. Setting changes reach a running reader at its next read without restarting the source or the visual.
- **AUD-011-R10**: Accessibility (FR-070): toggle label "Noise gate"; slider label "Gate threshold" with the readout as its value; identifiers `noiseGateToggle`, `noiseGateThresholdSlider`, `noiseGateThresholdValue`.
- **AUD-011-R11**: Real-time safety (Constitution VII): scalar state only, no allocation, lock or logging per read (relaxed atomic loads only), never on an audio callback.

### Key Entities

- **Noise gate setting**: enabled, open threshold (user settings).
- **Gate control**: enabled flag, microphone-source flag, threshold; written by the app, read by the analysis worker.
- **Gate state** (per reader): envelope, gain, phase (closed, attack, open, hold, release), hold frames left, last session generation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-011-S1**: A silence fixture (digital silence, then −70 dBFS RMS noise, 2 s) gives 100 % zero output with the gate on at −50 dBFS.
- **AUD-011-S2**: A tone stepping from −80 to −30 dBFS reaches a gain within 1 dB of unity no later than attack + one buffer (5 ms + 512 frames) after the step, on the sample clock.
- **AUD-011-S3**: After the tone stops, the gain is unity through the hold and zero by hold + release + one buffer.
- **AUD-011-S4**: A tone hovering between the thresholds causes zero open/close transitions over 2 s.
- **AUD-011-S5**: Off, or a non-microphone source: 100 % of samples bit-identical.
- **AUD-011-S6**: projectM's ring output is bit-identical with selection, trim and gate on the tap.
- **AUD-011-S7**: The Settings control works in one UI test under 30 s; every existing test passes.

## Assumptions

- The tap is Float32 interleaved stereo at 44.1 kHz (normalized ring format).
- Device checks with a real room, routes and interruptions are `{device}` work for the roadmap's final phase; simulator results are not evidence for them.
- No network; the privacy manifest does not change.
