# Contract: AUD-009 Channel Selection

## C1 — `ChannelSelection.apply(_:frames:mode:)` (AudioCore)

`static func apply(_ samples: UnsafeMutablePointer<Float>, frames: Int, mode: AnalysisChannelMode)`

- Interleaved stereo frames (`NormalizedPCMRing.channelCount` = 2), processed in place.
- `mix` or `frames <= 0`: returns without touching memory (bit-exact).
- Otherwise for each frame i with L = samples[2i], R = samples[2i+1]: s per data-model table;
  samples[2i] = samples[2i+1] = s.
- No allocation, no lock, no libm call.

## C2 — `ChannelSelectionControl`

- `init(mode: AnalysisChannelMode = .mix)`; `var mode` lock-free; unknown raw → `.mix`.

## C3 — `ChannelSelectionReader(_ reader:, control:)`

- `read(into:maxFrames:)`: forwards to the wrapped reader, loads the mode once, applies C1 to the
  frames returned, returns the same count.
- `analysisSessionGeneration`: the wrapped reader's (0 when it reports none).

## C4 — Composition (app)

- `AppCoordinator.trimmedAnalysisTap` = `inputTrim.trimmed(channelSelection.selected(manager.analysisTap))`
  (selection inside, trim outside). nil tap → nil.

## C5 — Setting (app)

- Key `ChannelSelectionSetting.modeKey = "settings.analysisChannel.mode"`; listed in
  `scripts/run_device_tests.py` `ALLOWED_KEYS`; removed by `-uitestResetNotice`.
- Settings section: segmented `Picker` with label "Analysis channel", identifier
  `analysisChannelPicker`; a readout of the selected spoken name, identifier `analysisChannelValue`;
  each segment's accessibility label is the spoken name.
