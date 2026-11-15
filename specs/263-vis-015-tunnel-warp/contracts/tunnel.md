# Contract: Tunnel warp (VIS-015)

- T1 `TunnelDrive.targetSpeed(tempo:pace:reduceMotion:)` = min(pace × bpm / 60, 3) for a valid tempo, else
  min(1.5 × pace, 3); × 0.5 with Reduce Motion. Never NaN, never > 3.
- T2 `advance`: speed' = speed + (target − speed)(1 − e^(−dt/0.5)); phase' = (phase + speed' · dt) mod 4096, dt the
  timestamp delta clamped to 0…0.25 s; first frame after `reset()` sets speed = target and dt = 0.
- T3 `TunnelMapping` (CPU) and `TunnelShader.function` (MSL `vis_tunnel_shade`) compute the same colour; the GPU frame
  agrees with the CPU mirror at sample pixels within 0.02 (linear).
- T4 The texture is continuous across u = 0/1 and periodic in depth with period 4096.
- T5 `NoiseFieldGenerator` with `tunnelPace == 0` draws byte-identical frames to before (noise field and kaleidoscope
  digests and goldens); switching modes in place gives a fresh generator's frames.
- T6 Host: `tunnelTempo` closure read once per frame while the tunnel is shown; accessibility value
  "<pace title>, <glow>".
