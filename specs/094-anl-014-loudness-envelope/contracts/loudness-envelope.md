# Contract: ANL-014 Loudness Envelope

## C1 KWeighting (AnalysisFeatures)

- `KWeighting.powerGain(frequency:sampleRate:) -> Double`: |H_shelf|²·|H_hp|² at `frequency` for
  the biquads designed for `sampleRate` (research D2). Pure; finite for 0 ≤ f ≤ rate/2.
- `KWeighting.table(size:sampleRate:) -> [Float]`: `size.binCount` entries, entry k = powerGain at
  k·R/N; entry 0 is 0 (DC excluded).
- At 997 Hz and 48 kHz or 44.1 kHz: 10·log10(powerGain) = 0.69 ± 0.02 dB.

## C2 LoudnessEnvelope (AnalysisFeatures)

- `LoudnessConfiguration(sampleRate:floorDecibels:ceilingDecibels:times:) throws(LoudnessConfigurationError)`;
  `.standard`; `normalized(decibels:)`.
- `LoudnessEnvelope(configuration:size:)` (size defaults to 2,048 points; the weight table is built for it); `reading: LoudnessReading`; `reset()`;
  `process(_ frame: SpectrumFrame, magnitudes: UnsafeBufferPointer<Float>) -> LoudnessReading`
  (`@discardableResult`): allocation-, lock-, log- and clock-free.
- Per frame: z = Σ_{k=1}^{N/2} w_k·m_k² / 3 (non-finite m_k count as 0); L = −0.691 + 10·log10 z, or
  −120 when z is not finite or ≤ 10⁻¹²; L clamped to ≥ −120; x = normalized(L); envelope ← x on the
  first frame after init/reset, else e + a·(x − e) with a = `SmoothingTimes.coefficient(timeConstant:
  x > e ? attack : release, frameInterval: hop / rate)`; then clamp to 0…1; if x == 0 and e < 0.001,
  e = 0.
- Invariants: `decibels` finite and ≥ −120; `envelope` finite and in 0…1.

## C3 Pipeline (AnalysisFeatures)

- `AnalysisPipelineConfiguration(…, loudness: LoudnessConfiguration = .standard)`: its rate must
  match the spectrum's (`.sampleRateMismatch`, no new error case); the pipeline builds the envelope
  for the spectrum's size.
- Every `AnalysisFrame` carries `loudness` (envelope) and `loudnessDecibels`; a session start
  resets the envelope.

## C4 Modulation (ParameterGraph)

- `AudioFeatureSource.loudness`, `id == "audio.loudness"`, `init?(id:)` round trip; `value(in:)`
  reads `AudioFeatureFrame.loudness` (nil or non-finite → 0, clamped by the existing `finite`).
- `ExpressionOpcode.loudness = 16`, stack effect +1; the expression `audio.loudness` compiles to it.

## C5 App

- `NativeSpectrumHost.applyModulation(bands:kick:centroid:loudness:timeNanoseconds:)`; the frame loop
  passes `LiveBandFrameInfo.loudness`; reset to 0 on start like the kick and centroid.
