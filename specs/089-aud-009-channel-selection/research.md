# Research: AUD-009 Channel Selection

## AUD-009-D0: Audit (2026-11-13, commit `e13af72`)

- Mono is made in three places, all (L + R)·0.5: `SpectrumStream.append(interleaved:)` with
  `ChannelMode.mid` (the ANL-016 pipeline's default spectrum, used by `LiveBandAnalyzer` and the tap
  tempo's own analysis), `SpectrumBandFeed` (the synchronous VIS-001 reference path) and
  `WaveformTap.read` (the oscilloscope history).
- No consumer of the analysis copy needs stereo. projectM reads the normalized ring (stereo, raw);
  the audio-state classifier reads levels from the sink in `AudioAnalyzer` before the ring is
  written; playback never passes through the app's analysis.
- ANL-001's `ChannelMode` has `.left`/`.right` but no caller chooses them.

## AUD-009-D1: Mode definitions

- **Decision**: Mix s = (L + R)·0.5; Left s = L; Right s = R; Mid s = (L + R)·k; Side s = (L − R)·k,
  k = 1/√2 = `Float(0.70710678)` (0x3F3504F3). Mid/Side is the orthonormal M/S pair: M² + S² = L² + R².
- **Rationale**: Mix must stay bit-exact with today, so it keeps the half-level sum. The usual
  "mid" (L + R)/2 would be a second name for the same thing; the equal-power mid differs (−3.01 dB
  on one channel instead of −6.02 dB, +3.01 dB above Mix on correlated content) and pairs with Side,
  the only mode that sees anti-phase content. All five are linear, so no harmonics are added.
- **Mono sources** (L = R = x): Mix = Left = Right = x bit-exact; Mid = √2·x; Side = 0. No linear
  mode can differ from Mix and preserve mono; recorded in the spec's Clarifications.
- **Alternatives**: Mid = (L + R)/2 (duplicate); non-linear centre extraction (harmonics, needs an
  STFT upmixer); no Side (leaves Mid as a pure +3 dB of Mix with nothing to show the M/S intent).

## AUD-009-D2: Where the selection sits and in which order

- **Decision**: A `NormalizedPCMReader` decorator, `ChannelSelectionReader`, directly around the tap;
  `InputTrimReader` wraps it (`AppCoordinator.trimmedAnalysisTap` = trim(select(tap))). It writes
  s into both channels of each frame (L′ = R′ = s).
- **Rationale**: Downstream every mono mix of (s, s) is s exactly: (s + s)·0.5 = s in IEEE
  arithmetic (doubling and halving are exact barring overflow at ±Float.greatestFiniteMagnitude), so
  `SpectrumStream`, `SpectrumBandFeed` and `WaveformTap` need no change and all agree. Selection
  before trim lets the trim's soft clip bound Mid/Side's +3 dB overshoot and makes the trim's level
  law act on the chosen signal. Same pattern as AUD-008-D1 and VIS-003-D1.
- **Alternatives**: setting `ChannelMode` in the pipeline (needs Mid/Side in AnalysisFeatures, a
  pipeline restart on change, and `WaveformTap` would still mix (L + R)/2: bars and line would
  disagree); trim before selection (the soft clip would act on each channel before the sum, and
  Mid of two clipped channels could exceed 1 again).

## AUD-009-D3: Sharing the mode across threads

- **Decision**: `ChannelSelectionControl` stores the mode's `UInt8` raw value in an `Atomic<UInt8>`
  (relaxed store from the main actor, relaxed load per read on the analysis worker); an unknown raw
  value reads as Mix.
- **Rationale**: Lock-free, allocation-free, a single independent value (AUD-008-D4's pattern).

## AUD-009-D4: Mode changes and sessions

- **Decision**: No crossfade; the next read applies the new mode. The reader is stateless besides the
  control, so session changes need nothing; the generation is forwarded.
- **Rationale**: Rare, deliberate user action; a crossfade would compute two signals per frame and
  hold ramp state for no visible benefit (ANL-003's smoothing already softens the bars).

## AUD-009-D5: Settings and storage

- **Decision**: `ChannelSelectionSetting` (@Observable, @MainActor) owns the key
  `settings.analysisChannel.mode` (String raw value) and the control; `didSet` stores and updates the
  control. `ChannelSelectionSection` (own file) shows a segmented `Picker` "Analysis channel" with
  short segment titles and full spoken names, plus a footer. Strings come from typed static
  functions and constants.
- **Rationale**: Separate files avoid conflicts with ANL-006 and ACC-006; segmented control is one
  tap per change and testable by segment button.
