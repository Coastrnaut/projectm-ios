# Data Model: VIS-010 Particle Trails

- **ParticleTrailLength** (`off`, `short`, `long`): half-life 0 / 0.1 / 0.3 s. App setting `ParticleTrailSetting`
  stores the raw value under `settings.particleTrails`; unknown or non-string → Off.
- **Effective half-life**: base h; × 0.5 with Reduce Motion; min(h, 0.25 s) with Reduce flashing or a stricter
  flash profile (frame context's `flashLimits` set).
- **ParticleTrailPass**: textures[2] (512², `rgba16Float`, private), `newest` index, `needsReset`, last output size,
  pipelines (decay, accumulate, present), `ParticleTrailFlashBound`.
  State: created (needsReset) → frame drawn (alternates `newest`) → reset on loop restart / size change / Off→on.
- **ParticleTrailFlashBound**: 17 `FlashLevels` (the bound E), 17 scratch levels; `advance(decay:particleLevels:background:)`, `reset()`.
- **ParticleTrailModel** (tests and fixture): fixed `width × height × 4` floats ×2, ping-pong; `step(decay:stamps:)`.
