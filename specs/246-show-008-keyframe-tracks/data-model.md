# Data Model: SHOW-008 Keyframe Tracks

- **ShowKeyframeColor**: `red`, `green`, `blue`, `alpha` (Double, finite, 0…1, sRGB-encoded). JSON `[r, g, b, a]`.
- **ShowKeyframeValue**: `number(Double)` (finite) or `color(ShowKeyframeColor)`. JSON: a number or a 4-array.
- **ShowKeyframeInterpolation**: `hold`, `linear`, `ease` (JSON strings).
- **ShowKeyframe**: `time` (Int milliseconds, 0…921,600,000), `value`, `interpolation` (to the next keyframe).
- **ShowKeyframeTrack**: `id` (UUID), `parameter` (well-formed ParameterID), `keyframes` (≤ 256, strictly increasing
  times, one kind). JSON `{"id", "parameter", "keyframes": [{"time", "value", "interpolation"}]}`.
- **ShowKeyframeTracks**: ≤ 16 tracks, unique IDs and parameters. `ShowCueList.tracks`; JSON `tracks` (optional).
- **ShowTrackOutput** (app): `numbers: [ParameterID: Double]`, `color: ShowKeyframeColor?`.
- Warnings: `droppedKeyframeTracks(Int)`, `droppedKeyframes(Int)`.
