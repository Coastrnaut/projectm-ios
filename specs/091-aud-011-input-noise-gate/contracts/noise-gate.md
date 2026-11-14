# Contract: AUD-011 Noise Gate

## C1 `NoiseGateParameters` (AudioCore)

`public struct NoiseGateParameters: Sendable, Equatable` with the fields and bounds of the data
model; `init(...)` clamps every field (NaN → default); `static let default`; computed
`closeDecibels`, `attackFrames`, `holdFrames`, `releaseFrames`. `NoiseGate.sampleRate = 44_100`,
`NoiseGate.detectorReleaseSeconds = 0.010`, `NoiseGate.linear(decibels:)` = 10^(dB/20).

## C2 `NoiseGateControl` (AudioCore)

`public final class NoiseGateControl: Sendable` — `init(isEnabled:isMicrophoneSource:openDecibels:)`;
lock-free `isEnabled`, `isMicrophoneSource`, `openDecibels` (clamped −80…−20, NaN → −50) and
read-only `isActive`. Any thread.

## C3 `NoiseGateProcessor` (AudioCore)

`public struct NoiseGateProcessor: Sendable` — `init(parameters:)` starts closed;
`gain`, `phase`, `envelope` readable; `setOpenThreshold(decibels:)` (recomputes the linear
thresholds only on change); `reset()`; `process(_:frames:channels:)` applies R4/R5 in place.
Gain 0 writes exact zeros; gain 1 leaves samples bit-identical.

## C4 `NoiseGateReader` (AudioCore)

`public final class NoiseGateReader: NormalizedPCMReader, AnalysisSessionReporting` —
`init(_ reader:, control:, parameters: = .default)`. `read` forwards the wrapped read; if 0 frames,
returns; if `control.isActive` is false, returns unchanged (and marks itself inactive); otherwise
resets on activation or on a session-generation change, updates the threshold, processes. Forwards
`analysisSessionGeneration`.

## C5 App composition

`AppCoordinator.trimmedAnalysisTap` = `noiseGate.gated(inputTrim.trimmed(channelSelection.selected(manager.analysisTap)))`.
`AppCoordinator.start(mode)` sets `noiseGate.control.isMicrophoneSource = (mode == .microphone)`;
`stop()` sets it false.

## C6 Settings UI

Section "Noise gate": `Toggle("Noise gate")` id `noiseGateToggle`; readout id
`noiseGateThresholdValue` ("−50 dBFS"); `Slider` −80…−20 step 1, label "Gate threshold", value =
readout, id `noiseGateThresholdSlider`, disabled while off; footer per AUD-011-R7.
