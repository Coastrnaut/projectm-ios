# Feature Specification: AUD-009 Channel Selection

**Feature Branch**: `feature/aud-009` (spec directory `089-aud-009-channel-selection`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement AUD-009 (Channel selection) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md line 96. Observable behavior, verbatim: "Offer stereo mix, left,
right and mid modes for analyzers." Acceptance, verbatim: "A left-only fixture produces expected
values for each selected mode." Verification: unit tests plus the simulator; device testing for
routes and interruptions is last. Applies only to the analysis copy, composed before AUD-008's input
trim; projectM, the sink, the classifier and playback stay bit-identical."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `AUD-009-R1…`, success criteria `AUD-009-S1…`, tasks `AUD-009-T01…`. Requirements
of other features are cited by their own IDs: FR-065 (what the app may store), FR-070
(accessibility); ANL-001-R5 (the spectrum's channel mode), ANL-001-R9 (the analysis tap),
ANL-016-R9 (capture-session generation), VIS-003-R2 (the oscilloscope's pass-through tap),
AUD-008-R1…R11 (the input trim on the same copy).

## Baseline: what exists today (audit of 2026-11-13, commit `e13af72`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

The audio path is the one AUD-008 mapped (`specs/086-aud-008-input-trim/spec.md`, Baseline): every
source → PCM sink → analysis work queue (levels for the audio-state classifier, then the Normalizer:
Float32 interleaved **stereo**, 44.1 kHz; a mono source is duplicated to L = R) → normalized ring
(projectM's input) plus the analysis tap (ANL-001-R9), whose one consumer reads it through AUD-008's
`InputTrimReader` (`AppCoordinator.trimmedAnalysisTap`), used by the five native hosts (circular and
linear spectrum and oscilloscope, camera, photo, video, text) and the tap tempo's own analysis.

Where the analysis makes mono today (every place sums the two channels the same way):

| Place | Code | Maths |
|---|---|---|
| Spectra, bands, onsets, tempo (ANL-016 pipeline) | `SpectrumStream.append(interleaved:)`, `ChannelMode.mid`, the pipeline's default (`AnalysisPipelineConfiguration.defaultSpectrum`) | (L + R)·0.5 |
| Reference band feed (VIS-001 tests) | `SpectrumBandFeed`, `channelMode: .mid` | (L + R)·0.5 |
| Oscilloscope history (VIS-003) | `WaveformTap.read`, before the pipeline | (L + R)·0.5 |

No consumer of the analysis copy needs stereo: every analyzer and the oscilloscope consume one mono
signal. ANL-001's `ChannelMode` already has `.left` and `.right`, but nothing in the app chooses
them (its doc comment: "Choosing a channel in the UI is AUD-009's job").

| Area | Today | Gap for this row |
|---|---|---|
| Channel choice for the analyzers | Always (L + R)/2. | A user choice of mix, left, right and mid (plus side, see Clarifications), on the analysis copy only. |
| Consistency between bars and oscilloscope | Both use (L + R)/2. | One choice must reach both. |
| Settings | AUD-008's "Audio Analysis" section (input trim). | One more control next to it. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose which channel drives the visuals (Priority: P1)

A user plays a recording with a guitar hard-left and drums hard-right. In Settings they pick
"Left" under the analysis channel, and the native visuals follow only the guitar. "Mid" follows what
both channels share; "Side" follows the stereo difference; "Mix" (the default) behaves as before.
What they hear and what projectM receives do not change. The choice is remembered on the next launch.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: In the simulator, choose "Left", relaunch, check "Left" is still selected.

**Acceptance Scenarios**:

1. **Given** Settings open, **When** the user looks at Audio Analysis, **Then** a channel control offers Mix, Left, Right, Mid and Side, with Mix selected by default, and VoiceOver reads each option's full name.
2. **Given** "Left" selected, **When** the app is relaunched, **Then** "Left" is still selected.
3. **Given** a running visual, **When** the user changes the mode, **Then** the analysis uses the new mode from its next read, without restarting the source or the visual.

---

### User Story 2 - A left-only fixture gives the expected values in each mode (Priority: P1)

A tone on the left channel with silence on the right, analysed in each mode, gives exactly the level
and band values the mode's definition predicts.

**Why this priority**: It is the roadmap's acceptance criterion.

**Independent Test**: Unit tests on the host and in the Linux shape.

**Acceptance Scenarios**:

1. **Given** a left-only sine, **When** read in each mode, **Then** the analysed signal's RMS relative to the left channel is: Mix −6.02 dB, Left 0 dB, Right silent, Mid −3.01 dB, Side −3.01 dB (within 0.01 dB).
2. **Given** the same fixture through the band analysis, **When** analysed in each mode, **Then** the tone's band value relative to Left moves by the same dB divided by the 80 dB band range (within 0.005), and Right gives no band above the floor.
3. **Given** a right-only fixture, **Then** Left is silent and Right is full, Mix and Mid as above.
4. **Given** an anti-phase fixture (R = −L), **Then** Mix and Mid are silent and Side is +3.01 dB relative to L.
5. **Given** a mono source (L = R), **Then** Mix, Left and Right give the mono signal bit for bit, Mid gives it +3.01 dB and Side is silent.
6. **Given** Mix, **When** any signal is read, **Then** the output is bit-identical to today's.

---

### User Story 3 - Nothing outside the analysis changes (Priority: P1)

Whatever the mode (and trim), projectM's PCM, the audio-state levels and playback are the same as
without the feature.

**Why this priority**: The constraint the row shares with AUD-008.

**Independent Test**: A unit test at the seam (AUD-008's pattern).

**Acceptance Scenarios**:

1. **Given** a ring with an analysis tap read in Side mode with a +24 dB trim, **When** the main ring is read, **Then** its frames equal the written frames bit for bit.

### Edge Cases

- Mode changed while audio flows: the next read uses the new mode (a deliberate user step; no crossfade).
- Stored value missing or unknown: Mix.
- Mid or Side of a loud correlated (or anti-correlated) signal can exceed full scale by up to +3.01 dB; with a trim other than 0 dB the trim's soft clip bounds it to [−1, 1].
- Silence stays silence in every mode; NaN and infinities pass through the selection as the arithmetic gives them (the trim, when active, makes them finite).

## Requirements *(mandatory)*

### Functional Requirements

- **AUD-009-R1**: The selection MUST apply only to the analysis tap's consumer copy, in the consumer's buffer. The PCM sink, the normalized ring read by projectM, the audio-state classifier's levels and playback MUST be unchanged bit for bit for any mode.
- **AUD-009-R2**: Modes and maths, per frame with s the analysed signal: Mix s = (L + R)·0.5; Left s = L; Right s = R; Mid s = (L + R)·(1/√2); Side s = (L − R)·(1/√2). Default Mix.
- **AUD-009-R3**: Every analyzer and the oscilloscope MUST see the same selected signal s.
- **AUD-009-R4**: In Mix the analysis output MUST be bit-identical to today's.
- **AUD-009-R5**: The selection MUST come before AUD-008's input trim (selection → trim → oscilloscope history → analysis pipeline).
- **AUD-009-R6**: One global mode, persisted as a user setting; not part of scenes, show cues or scene archives; CaptureLab has none. This amends FR-065 by exactly one key, and the device privacy check's allowed list gains it.
- **AUD-009-R7**: Settings MUST offer the mode next to AUD-008's input trim, with a footer explaining the modes and that the choice does not change what is heard, projectM or recordings.
- **AUD-009-R8**: Accessibility (FR-070): the control's label is "Analysis channel"; each option's spoken name is its full name ("Stereo mix", "Left", "Right", "Mid", "Side"); stable identifiers for the control.
- **AUD-009-R9**: Real-time safety (Constitution VII): no allocation after creation, no lock (one atomic load per read), never on an audio callback.
- **AUD-009-R10**: A mode change MUST reach the running analysis at its next read without restarting the source or the visual.

### Key Entities

- **Analysis channel setting**: the selected mode (user setting).
- **Channel control**: the shared mode, written by the UI, read by the analysis worker.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-009-S1**: For a left-only sine, the analysed RMS relative to the left channel is Mix −6.02, Left 0, Mid −3.01, Side −3.01 dB (±0.01 dB) and Right is exactly silent.
- **AUD-009-S2**: The same fixture's tone band moves by the S1 dB/80 relative to Left (±0.005) and Right lights no band.
- **AUD-009-S3**: Right-only, anti-phase and mono fixtures give the values of User Story 2.
- **AUD-009-S4**: In Mix, 100 % of output samples are bit-identical to the input.
- **AUD-009-S5**: projectM's ring output is bit-identical with and without Side + 24 dB trim on the tap.
- **AUD-009-S6**: Choosing a mode and relaunching keeps it, in one UI test of at most 30 s.
- **AUD-009-S7**: Every existing AudioCore, VisualGenerators and app test still passes.

## Assumptions

- The tap is Float32 interleaved stereo at 44.1 kHz; mono sources arrive as L = R (Normalizer, R-05).
- Device checks of routes and interruptions with a mode set are `{device}` work for the roadmap's final phase; simulator results are not evidence for them.
- No new stored data besides one user-setting key; no network; the privacy manifest does not change.
