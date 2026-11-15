# Research: VIS-015 Tunnel Warp

## D1 Where the tunnel lives
- Decision: third mode of `NoiseFieldGenerator` (entry point `vis_tunnel_fragment`, lazily built pipeline).
- Rationale: reuses the reviewed compile site (ADR-0066), SHD-006 noise, the 8 × 8 flash estimate, the palette fill,
  the host's in-place style switching; VIS-014 proved separate entry points keep the other modes byte-identical.
- Alternatives: a new generator (second compile site, duplicate plumbing); a branch inside `vis_noise_fragment`
  (VIS-014 measured 1/255 golden drift from that).

## D2 Mapping and texture
- Decision: p relative to the centre over the shorter side; r = max(|p|, 1e-3); u = atan2(p.y, p.x)/2π + 0.5;
  v = 0.5 / r + phase. Ring = 0.7 + 0.3 cos(2π·fract v) (implementation: a 0.4…1 swing keeps headroom under FX-019's envelope at the 3 rings/s cap). Texture t = blend over the angle cut of two octaves of
  `mat_snoise` at (8u, v) and (16u, 2v) (weights 0.65, 0.35; field key 3), so u = 0 and u = 1 read the same lattice
  cells. Fog = smoothstep(0.02, 0.5, r). Colour = palette((t − 0.2)/0.6, as the noise field) × ring × fog × (0.35 + 0.65 t) × brightness.
- Rationale: integer cell counts around and integer lacunarity make the texture periodic in both directions
  (lattice wraps every 4096 cells), so the phase can wrap at 4096 rings without a jump; value noise is cheap.
- Alternatives: fBm with lacunarity 2.03 (not periodic in depth); texture sampling (edge handling, compile of a
  sampler path).

## D3 Speed, fallback and smoothing
- Decision: target = min(pace × bpm/60, 3) when the tempo is valid (finite, > 0, confidence ≥ 0.5), else
  min(pace × 1.5, 3); × 0.5 with Reduce Motion. speed += (target − speed)(1 − e^(−dt/0.5)); phase += speed · dt;
  dt = timestamp delta clamped 0…0.25 s (0 on the first frame and backwards). First frame after reset: speed = target.
- Rationale: one-pole smoothing bounds every per-frame change by the gap times 1 − e^(−dt/τ); integrating speed
  keeps the position continuous at any tempo change; 3 rings/s = at most 3 luminance cycles per second per pixel
  (WCAG general flash limit) and also covers tempos above ANL-005's 200 BPM.
- Alternatives: phase locked to SHOW-010's beat grid (jumps when the anchor moves); tempo × constant without a cap.

## D4 Bass punch
- Decision: brightness target 0.5 + 0.3 × low (× 0.5 of the punch under Reduce Motion), attack τ 0.08 s, release
  τ 0.3 s, ≤ 0.8; the FX-019 envelope then limits the frame.
- Rationale: visible on kicks, bounded below full white (ACC-012), and the envelope catches any remaining risk.

## D5 Tempo plumbing
- Decision: `NativeSpectrumHost.tunnelTempo: (@MainActor () -> TunnelTempo)?`, set by `AppCoordinator.connectLFOs`
  from `tempo.snapshot` (bpm, confidence) and read once per frame while the tunnel is shown.
- Rationale: same pattern as MOD-009's `lfoTempoBPM`; VisualGenerators stays free of PerformanceControl.
