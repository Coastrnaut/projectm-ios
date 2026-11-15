# Research: SHD-012 Authoring Preview Fixture

## SHD-012-D1 Reuse REC-013's offline core for audio and clock
- **Decision**: `OfflineFixtureAudio.samples(seed:seconds:)` (4 s), `OfflineFrameClock(fps: 30)`, and one
  `OfflineAnalysisDriver` per run, advanced to `clock.samplePosition(frame: n)` before frame n.
- **Rationale**: already proven deterministic (REC-013 acceptance), Linux-buildable, the live analysis
  configuration (bar count 64, the spectrum floor).
- **Alternatives**: synthetic band curves (not the real analysis, so a binding would behave differently live);
  a recorded audio file (needs a bundled asset).

## SHD-012-D2 The trajectory
- **Decision**: per frame: time (ns), frame duration (from `LayerFrameClock` fed the same times the renderer
  uses), each bound parameter's effective value after `MaterialParameterValues.set` (what the GPU reads), the
  motion phase and audio level from a `MaterialMotion` advanced exactly as `ProceduralMaterialLayer.render` does.
  Modulator time = the frame's time; feature frame = bands + kick envelope.
- **Rationale**: those are the numbers the shader uses, so the trajectory explains the picture. Recording the
  phase lets a test cross-check the layer's own motion after each GPU frame.
- **Alternatives**: recording all parameters (unbound ones are constant; noise).

## SHD-012-D3 Frame checksums
- **Decision**: SHA-256 (CryptoKit) of the raw half-float read-back of each frame, as REC-013 hashes frames and
  SHD-006 reads back; run digest = SHA-256 over the concatenated frame digests. Apple only (the recorder is
  Metal), so the Linux shape has the trajectory only.
- **Alternatives**: FNV-1a (SHD-006's per-GPU reference table) — SHA-256 matches REC-013's sidecar and the
  brief.

## SHD-012-D4 Rendering each frame
- **Decision**: one `ProceduralMaterialLayer` prepared once for the picture; `resetMotion()` at the start; per
  frame set the effective values, build the `LayerFrameContext` from a `LayerFrameClock` at
  1 s + t(n) (REC-002/REC-013's start offset), feed the frame's bands as `LayerAudioContext`, render, blit,
  wait, hash. Reduce flashing on.
- **Rationale**: the same GPU path as SHD-006's still and the compositor; waiting per frame keeps memory
  bounded and the order fixed.

## SHD-012-D5 Pacing independence
- **Decision**: the sequencer's state is advanced only by `step()`; `run(frames:)` is a loop of `step()`.
  Chunked and per-frame stepping are therefore identical by construction; tests prove it (S2).

## SHD-012-D6 UI placement and playback
- **Decision**: Noise editor, "Fixture preview" section under the still. Playback by a SwiftUI
  `TimelineView(.periodic(from:by: 1/30))` that only picks which pre-rendered frame to show (no
  `.animation`, so ACC-001's motion policy is untouched); with Reduce Motion on, no auto-play.
- **Alternatives**: native visual settings (REC-013 export already covers native visuals); a new screen
  (harder to reach).
