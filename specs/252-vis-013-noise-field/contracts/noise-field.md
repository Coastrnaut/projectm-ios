# Contract: Noise Field generator (VIS-013)

- C1 `SeededNoise`: `mix`, `hash(cellX:cellY:key:)`, `noise(_:key:)`, `fbm(_:octaves:lacunarity:gain:seed:field:)`,
  `warped(_:octaves:lacunarity:gain:seed:warpAmount:warpFrequency:)`, `domainPoint(x:y:width:height:scale:phase:)`;
  `SeededNoiseShader.functions` (MSL text). Identical results to SHD-006 contract N2.
- C2 `NoiseFieldGenerator(device:pixelFormat:configuration:)`: `TextureGenerator`; `encode(into:commandBuffer:bands:context:)`
  reads ANL-002 bands, advances the drive to the context's time, solves the envelope gain, draws; returns false on a
  wrong pixel format. `restartLoop()` resets the drive (envelope history kept). `lastGain`, `drive` readable.
- C3 Determinism: the encoded frame depends only on configuration, the sequence of (bands, context) and the GPU.
