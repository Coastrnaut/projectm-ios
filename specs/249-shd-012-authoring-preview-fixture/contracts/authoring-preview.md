# Contract: Authoring Preview (SHD-012)

## P1 Sequencer (plain Swift, Linux)
`AuthoringPreviewSequencer(request:) throws(AudioFeatureBindingError)` — refuses a binding exactly as
`AudioFeatureModulator.replaceBindings` does; nothing runs.
- `step() -> AuthoringPreviewFrame?`: frame n = `index`, nil after the last frame. Frame n: analysis advanced to
  `OfflineFrameClock.samplePosition(frame: n)`; modulator advanced with bands + kick at time t(n); for each bound
  parameter the effective value is stored into the frame's values with the material's clamping; motion advanced
  with the `LayerFrameClock` duration for time 1 s + t(n), the band level of the bands, the effective speed and
  audio reactivity.
- `run(frames:) -> [AuthoringPreviewFrame]` = repeated `step()`.
- `static record(_ request:) throws -> AuthoringPreviewTrajectory`.

## P2 Determinism
Equal requests give `==` trajectories (Double equality) whatever the stepping. A different fixture seed or
binding (target, source) changes the bound trajectory.

## P3 Recorder (Metal, Apple only)
`AuthoringPreviewRecorder(device:)`; `record(_ request:, width:, height:, keepImages:) throws -> AuthoringPreviewRecording`.
Per frame: the layer gets the frame's values, renders with that frame's context and bands (Reduce flashing on),
read back as half floats; SHA-256 per frame. The layer's motion after frame n equals the trajectory's phase and
audio level for frame n. Same request, same GPU → equal checksum sequences.

## P4 Editor
Noise editor › Fixture preview: binding target picker (`fixturePreviewTarget`), source picker
(`fixturePreviewSource`), seed stepper (`fixturePreviewSeed`), Play/Stop button (`fixturePreviewPlay`), the picture
(`fixturePreviewPicture`), frame slider (`fixturePreviewFrame`), summary text (`fixturePreviewSummary`,
e.g. "120 frames · Warp amount 0.80…2.10 · run 1a2b3c4d").
