# Feature Specification: AUD-013 Source Latency Calibration

**Feature Branch**: `feature/aud-013` (spec directory `095-aud-013-source-latency-calibration`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-14 (device task AUD-013-T15 open)

**Input**: User description: "Implement AUD-013 (Source latency calibration) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md line 100. Observable behavior, verbatim: "Measure or set
analysis-to-visual offset per source, saved locally." P1, M. Acceptance, verbatim: "Known pulse and
frame timestamps produce offset within a documented tolerance." Verification: unit tests plus the
simulator; device testing for routes and interruptions is last."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `AUD-013-R1…`, success criteria `AUD-013-S1…`, tasks `AUD-013-T01…`. Requirements
of other features are cited by their own IDs: FR-065 (what the app may store), FR-070
(accessibility), SC-006 (audio-to-visual delay under 150 ms), ANL-001-R9 (the analysis tap),
ANL-016-R5, R9 (the bus clock and session generation), AUD-008-R1 (the input trim), AUD-009-R5 (the
channel selection), AUD-011-R1 (the noise gate), AUD-012-R8, R12 (the source switch), VIS-003-R2
(the oscilloscope's pass-through tap).

## Baseline: what exists today (audit of 2026-11-13, commit `ab68d80`)

This is a gap row. The audit confirms the gap: no offset of any kind exists between the audio the
user hears and the visuals.

**Timestamps along the path** (source → rendered frame):

| Stage | Timestamp that exists | Notes |
|---|---|---|
| Capture source | CMSampleBuffer PTS (System/App Capture), `AVAudioTime` host time of the mixer tap (In-App Playback) or the input tap (Microphone) | Used only by the T062 "Capture delivery" signpost (PCMSink arrival minus capture time). |
| PCM sink → Normalizer | None carried with the samples; the sink logs delivery delay. | Samples are converted to 44.1 kHz stereo; position is implicit in sample count. |
| `NormalizedPCMRing` (projectM's ring) | None; the freshness rule (R-06) caps the backlog at 50 ms (2,205 frames). | The renderer reads it once per frame (`ANGLERenderer`, up to the engine's samples per frame). |
| Analysis tap (ANL-001-R9) | A session generation (ANL-016-R9), advanced by `reset()` and AUD-012's `resetForHandoff`. | One consumer; no freshness rule; drop-oldest at 0.5 s. |
| Reader chain (`AppCoordinator.trimmedAnalysisTap`) | Generation forwarded by each reader: channel selection → trim → gate → `WaveformTap`. | Each reader acts in the caller's buffer. |
| `AnalysisPipeline` frames | Sample clock: session sample (end of window), timeline sample, and host nanoseconds = anchor (injected clock at the session's first chunk minus its duration) + sample / rate (ANL-016-R5). | 2,048-point spectra at hop 512 (11.6 ms), worker every 10 ms. |
| `LiveBandAnalyzer` | "Latest wins": the frame loop copies the newest frame and its host time. | No look-back; an older frame is never chosen. |
| `NativeSpectrumHost` | The `CADisplayLink` frame drives the draw; no comparison between frame time and analysis time. | |
| projectM's PCM read | None. | |

**Earlier latency measurements**: SC-006 (median audio-to-visual delay < 150 ms by 240 fps camera,
20 clicks) was never measured: T087 is "not required" (owner ruling 2026-11-10, ADR-0006). T062 and
T114 measured pipeline stages on the simulator only (not evidence): ring + conversion median
0.03 ms, capture delivery about 85 ms (mixer tap buffering), normalized residency median 36.9 ms,
max 50 ms. SC-007 (preset switch) and SC-015 (cold launch) are not latency between sound and
visuals. Nothing measured the output route's latency (speaker, wired, Bluetooth).

**Offsets that already exist**: none. SHOW-011's tap tempo sets a BPM, not a phase; ANL-005's beat
tracker predicts beats from analysis time with no output compensation; MOD-002 bindings apply the
newest frame.

| Area | Today | Gap for this row |
|---|---|---|
| Output route latency (Bluetooth ≈ 150–250 ms) | Visuals run ahead of what the user hears. | A per-source delay of the visuals' audio feed. |
| Settings | Audio Analysis: trim, channel, noise gate. | A "Visual delay" section per source with an estimate and a reset. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option, recommended option
first.

- Q: Can the offset be negative, so the visuals run ahead of the analysed audio? → A: No. The range
  is 0…250 ms for every source. The analysis can only see audio once it has arrived, and the
  pipeline already adds its window (46 ms) and hop (11.6 ms); for Microphone and System/App
  Capture an earlier visual is impossible. For In-App Playback it would need analysing the file
  ahead of playback, a second decode path that this M-sized row does not include (recorded as a
  possible follow-up). The section's footer says the visuals can only be delayed; stored or typed
  values below 0 clamp to 0 (AUD-013-R1, R4).
- Q: How is the offset "measured" — a self-measurement with the microphone, a tap-to-align screen,
  or the system's reported latency? → A: The system's reported output latency plus I/O buffer
  duration, offered as "Estimate from Output" on the user's request, plus the manual slider; the
  live visuals are the check. Default 0 for every source (no automatic change when the route
  changes). Rejected: a click played through In-App Playback and heard by the microphone (needs
  the microphone permission for a non-microphone source and a play-and-record session that
  changes routes and conflicts with the active source's session); a tap-along mode (new UI and
  timing statistics for a P1/M row; deferred). The real measurement with hardware stays a
  `{device}` task. No new permission; FILE-013's permission catalog is unchanged (AUD-013-R9).
- Q: Is the offset stored per source only, or per source and output route (speaker, wired,
  Bluetooth)? → A: Per source only: three keys. The route is what changes the latency most, but
  per-route storage multiplies the settings by route kinds and needs route-change handling that
  AUD-007 does not provide for this; the estimate button reads the current route when pressed
  (AUD-013-R11). Recorded as a follow-up.
- Q: Is projectM's PCM feed delayed too, or only the analysis that drives the native visuals? →
  A: Both, by the same value. projectM is the main visual, and a delay that left it early would
  not fix the Bluetooth case. Its feed is raw PCM, so the same delay reader wraps the renderer's
  reader; at 0 ms it forwards unchanged, so today's freshness rule and bit-identity hold. Rejected:
  analysis only (does not meet the user need) (AUD-013-R2, R6, R7).
- Q: What happens to the delay lines on a source switch or restart? → A: The analysis delay line
  is emptied when the session generation changes, so no old-source audio is analysed as the new
  source (the pipeline discards straddling chunks the same way), and the new source's value
  applies at once; projectM's delay line keeps its content, because AUD-012 guarantees projectM a
  continuous fade-out → silence → fade-in, and moves to the new value at the bounded rate
  (a quarter of the arriving frames per read) (AUD-013-R5, R7, R8).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Visuals in time with Bluetooth headphones (Priority: P1)

A user plays a track through In-App Playback on Bluetooth headphones. The visuals react before the
beat is heard. In Settings → Visual Delay the user picks In-App Playback and sets 180 ms (or taps
"Estimate from Output"); from then on the visuals, the oscilloscope, bindings, the kick and the
centroid all react 180 ms later, in time with the headphones. The value is kept for the next
launch, and the Microphone and System/App Capture values are not affected.

**Why this priority**: It is the row's observable behavior and acceptance.

**Independent Test**: A synthetic pulse train with known sample times, analysed through the real
analysis pipeline with a simulated clock and simulated display frames, shows the configured offset
within the documented tolerance.

**Acceptance Scenarios**:

1. **Given** a pulse train at known sample times and display frames at 60 Hz, **When** the offset is 0, +100 or +250 ms, **Then** the first display frame showing each pulse is later than with offset 0 by the configured offset within ±(1 display frame + 1 analysis hop).
2. **Given** an offset outside the range (for example 400 ms or −50 ms), **When** it is set, **Then** it is clamped to 250 ms or 0 ms.
3. **Given** Microphone 0 ms, In-App Playback 180 ms and System/App Capture 40 ms, **When** each source is active, **Then** that source's value applies and changing one leaves the others unchanged.

---

### User Story 2 - Change the delay while it plays (Priority: P1)

While the visuals run, the user drags the slider. The visuals shift smoothly to the new delay with
no burst of catch-up frames and no long freeze.

**Independent Test**: A unit test changes the target mid-stream and checks the frames delivered per
read.

**Acceptance Scenarios**:

1. **Given** a running delay of 0 ms, **When** the target changes to 250 ms, **Then** the reads after each arrival deliver at least 75 % of the frames that arrived, and the delay reaches 250 ms within 1.1 s.
2. **Given** a running delay of 250 ms, **When** the target changes to 0 ms, **Then** the reads after each arrival deliver at most 125 % of the frames that arrived plus one frame of rounding, and the delay reaches 0 within 1.1 s.

---

### User Story 3 - Estimate and reset (Priority: P2)

The user taps "Estimate from Output" for the picked source: the value becomes the route's reported
output latency for In-App Playback and System/App Capture, and 0 for Microphone (its sound reaches
the microphone through the room, and the visuals cannot be advanced). "Reset" sets 0.

**Independent Test**: Unit tests with an injected latency value; no real audio session.

**Acceptance Scenarios**:

1. **Given** an injected output latency of 0.160 s and buffer 0.005 s, **When** estimating for In-App Playback, **Then** the value is 165 ms.
2. **Given** an injected latency of 0.400 s, **When** estimating, **Then** the value is 250 ms (clamped); a non-finite or negative latency gives 0.
3. **Given** any latency, **When** estimating for Microphone, **Then** the value is 0 ms.

---

### User Story 4 - Source switch (Priority: P2)

During a switch (AUD-012) the delay follows the new source's value. The old source's delayed audio
is not shown as the new source.

**Acceptance Scenarios**:

1. **Given** the analysis delay line holds old-source audio, **When** the session generation changes, **Then** the delay line is emptied and the new source's value applies from its first frame.
2. **Given** projectM's feed during a switch, **When** the generation changes, **Then** its delay line keeps its content (AUD-012's continuous fade-out → silence → fade-in passes through) and moves to the new value at the bounded rate.

### Edge Cases

- Offset 0: the feeds are bit-identical to today, including the freshness rule, with no copy.
- Stored value missing, NaN, not a number or out of range: 0 ms, or clamped.
- The reader stalls and more than the delay plus 50 ms accumulates in projectM's feed: the oldest excess is skipped, as the freshness rule does today.
- More than the delay line's capacity arrives between two reads (the analysis worker stalled): the oldest frames are dropped and counted.
- No source active: values are editable; they apply when the source starts.

## Requirements *(mandatory)*

### Functional Requirements

- **AUD-013-R1**: The app MUST keep one visual delay per source (Microphone, In-App Playback, System/App Capture) in whole milliseconds, 0…250 ms, default 0. Values outside the range are clamped; NaN or a stored non-number reads as 0.
- **AUD-013-R2**: The delay MUST shift when audio reaches every consumer that drives visuals: the analysis tap's consumer chain (native spectra, oscilloscope, MOD-002 bindings, kick, centroid, tempo detection) and projectM's PCM feed. Playback, the PCM sink and the audio-state classifier MUST NOT be delayed.
- **AUD-013-R3**: The delay is applied to the audio on the sample clock: a frame leaves the delay line `round(delay × 44.1)` frames after it entered (in steady state), so every derived analysis item is shifted by the same amount.
- **AUD-013-R4**: Negative values (visuals earlier than the audio) are not offered: the analysis cannot see audio before it arrives. The UI says so.
- **AUD-013-R5**: A change of the target delay MUST move the applied delay at a bounded rate: per read, by at most a quarter of the frames that arrived in that read. Between two arrivals, the reads that drain the line deliver no fewer than 75 % and no more than 125 % of the arrived frames because of a change (plus one frame of rounding).
- **AUD-013-R6**: With target and applied delay 0 and nothing buffered, the delay reader MUST forward the wrapped reader's read unchanged (bit-identical, no copy).
- **AUD-013-R7**: The analysis delay line MUST be emptied when the wrapped reader's session generation changes (restart or switch, ANL-016-R9); the new target applies at once. projectM's delay line MUST NOT be emptied (AUD-012's continuity) and MUST skip the oldest frames beyond delay + 2,205 frames (the freshness rule).
- **AUD-013-R8**: The active source's value applies when a session starts and when a switch's new session begins after the old source's fade-out (the same hook as AUD-012-R12), and at once when the user changes the active source's value.
- **AUD-013-R9**: "Estimate from Output" MUST set the picked source's value (the section's picker starts on the active source) to round((output latency + I/O buffer duration) × 1,000) ms clamped to the range for In-App Playback and System/App Capture, and to 0 for Microphone. Non-finite or negative inputs count as 0. No new permission is used.
- **AUD-013-R10**: Settings MUST offer a "Visual Delay" section: a source picker (Microphone, In-App Playback, System Audio; it starts on the active source, or In-App Playback with none), one "Visual delay" slider for the picked source (0…250 ms, 5 ms steps) with a readout ("180 ms"), an "Estimate from Output" button and a "Reset" button for the picked source, and a footer saying it delays the visuals only, never earlier than the sound.
- **AUD-013-R11**: Persisted under `settings.latencyOffset.microphone`, `settings.latencyOffset.inAppPlayback` and `settings.latencyOffset.systemAppCapture` (Double, ms); device-level user settings, not part of scenes, show cues or archives. This amends FR-065 by exactly these three keys; the device privacy check's allowed list gains them; `-uitestResetNotice` clears them.
- **AUD-013-R12**: Accessibility (FR-070): picker label "Delay for source"; slider label "Visual delay" with the readout as the value; identifiers `latencyOffsetSource`, `latencyOffsetSlider`, `latencyOffsetValue`, `latencyOffsetEstimate`, `latencyOffsetReset`.
- **AUD-013-R13**: Real-time safety (Constitution VII): the delay line is allocated when the reader is created; a read never allocates, locks or logs (relaxed atomic loads only).

### Key Entities

- **Visual delay setting**: three values in ms (user settings).
- **Delay control**: target frames; written by the app, read by the delay readers.
- **Delay reader** (per consumer): delay line, applied delay, last session generation, dropped count.
- **Latency estimate**: a pure function of source, output latency and buffer duration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-013-S1**: Pulse train through the analysis pipeline with simulated time: the measured shift of the first reacting display frame equals the configured offset (0, 100, 250 ms) within ±28.3 ms (one 60 Hz frame 16.7 ms + one hop 11.6 ms) for every pulse.
- **AUD-013-S2**: Clamping: 400 → 250, −50 → 0, NaN → 0.
- **AUD-013-S3**: Per source: setting one value never changes another; the active source's value is the applied target.
- **AUD-013-S4**: A mid-run change delivers 75–125 % of the arrived frames per arrival and settles within 1.1 s.
- **AUD-013-S5**: A generation change empties the analysis delay line; projectM's line keeps content.
- **AUD-013-S6**: With 0 ms, 100 % of frames are bit-identical to the wrapped reader.
- **AUD-013-S7**: The Settings section works in one UI test under 30 s; every existing test passes.

## Assumptions

- The tap and the ring are Float32 interleaved stereo at 44.1 kHz.
- The output latency the system reports is a starting estimate, not a measurement; the real measurement on hardware (speaker, wired and Bluetooth, microphone or a 240 fps camera) is a `{device}` task for the roadmap's final phase. Simulator results are not evidence.
- No network; no new permission; the privacy manifest does not change.
