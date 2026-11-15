# Data Model: VIS-015 Tunnel Warp

- **TunnelPace** (enum, String raw): `half` (0.5 rings per beat, "1 ring every 2 beats"), `beat` (1, "1 ring per
  beat", default), `double` (2, "2 rings per beat"). Stored as `settings.tunnel.pace`; anything else → `beat`.
- **TunnelTempo** (value): `bpm` Double?, `confidence` Double. `validBPM`: bpm when finite, > 0 and confidence ≥ 0.5
  (finite), else nil. `.none`.
- **TunnelMapping** (CPU mirror): constants `depthScale` 0.5, `minimumRadius` 1e-3, `fogInner` 0.02, `fogOuter` 0.5,
  `phasePeriod` 4096; `depth(p:phase:)`, `texture(u:v:seed:)`, `ring(v)`, `fog(r)`, `shade(...)`.
- **TunnelDrive** (value): `speed` rings/s, `brightness` 0.5…0.8, `phase` rings in [0, 4096); constants
  `baseRingsPerSecond` 1.5, `maximumRingsPerSecond` 3, `speedTimeConstant` 0.5, `maxStep` 0.25,
  `minimumConfidence` 0.5, `reduceMotionScale` 0.5. `targetSpeed(tempo:pace:reduceMotion:)`, `advance(...)`, `reset()`.
- **NoiseFieldConfiguration** (VIS-013) + `tunnelPace` Double (0 = off; else 0.5, 1 or 2 — other positives snap to
  the nearest; a tunnel forces `wedges` 0); `isTunnel`; `static func tunnel(pace:reduceMotion:palette:)`.
- **App**: `VisualChoice.tunnel`, `NativeSpectrumStyle.tunnel(pace:)`, `AppSettings.tunnelPace`.
