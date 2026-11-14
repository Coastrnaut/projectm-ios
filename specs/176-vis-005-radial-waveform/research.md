# Research: VIS-005 Radial Waveform

## VIS-005-D1 Sample source
- **Decision**: VIS-003's `WaveformTap.output` mono history (4,096 samples), read by the host into its existing scratch exactly as the oscilloscope does.
- **Rationale**: The ring shows one waveform; the history already exists, is wait-free and costs nothing extra.
- **Alternatives**: the stereo history (two rings or a mode setting: more settings, little value).

## VIS-005-D2 Seam removal
- **Decision**: Raised-cosine crossfade of the last k = 256 of N = 1,024 points into the k samples preceding the window (input: newest N + k = 1,280 samples). Point j ≥ N − k: s = (1 − c)·x[k + j] + c·x[j + k − N], c = ½ − ½·cos(π(j − (N − k) + ½)/k).
- **Rationale**: Works for any signal, not only periodic ones; preserves constants exactly (weights sum to 1); the newest point lands next to the sample before the oldest, so the closing segment is an ordinary step. Prototype (Python, 2026-11-14): max/median neighbour distance 1.14…1.42 for 55, 97, 110, 147, 220 Hz over 77 phases; without the taper 21…81.
- **Alternatives**: zero-crossing period alignment (fails on non-periodic music); a Tukey taper to zero or to the mean (flat spot on the ring; breaks the DC acceptance when tapering to zero).

## VIS-005-D3 Gain
- **Decision**: Reuse `LissajousAutoGain` unchanged on the peak |s| of the tapered window. Silence (peak < 0.0001) → s = 0 everywhere, the base circle.
- **Rationale**: Deterministic, frame-duration driven, already tested; quiet music still moves the ring.
- **Alternatives**: fixed scale (oscilloscope): quiet music would look static.

## VIS-005-D4 Geometry and drawing
- **Decision**: θᵢ = 2π·i/N clockwise from the top (x = cx + r·sin θ, y = cy − r·cos θ, y down), r = (R₀ + A·s)·min(W, H)/2; N rectangles (closing one included), thickness max(0.006·min(W, H), 1 px), butt ends, palette color k of N; zero-length segments skipped.
- **Rationale**: Same drawing model as VIS-004 (flash area model, premultiplied over), clock-like orientation as VIS-001.

## VIS-005-D5 Settings
- **Decision**: Ring Small/Medium/Large (0.40/0.55/0.70) and Amplitude Low/Medium/High (0.10/0.18/0.25), strings; defaults Medium/Medium. The configuration clamps R₀ to 0.2…0.75 and A to 0…0.25 (non-finite → default), so r stays within 0…1 of half the shorter side for any configuration.
- **Rationale**: Two keys, safe readings, radii always within 0.15…0.95.

## VIS-005-D6 Goldens
- **Decision**: `GeneratorGoldens/RadialWaveform/<class>/` with `radial-sine` (a 220 Hz sine, amplitude 0.8) and `radial-silence`, frames 0 (gain warm-up) and 1 captured, 128×96 and 256×192, as VIS-004.
