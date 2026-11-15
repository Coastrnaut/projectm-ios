# Research: VIS-016 Starfield Flight

## D1 Where it lives
- Decision: own generator on `FlatShapePass`, CPU simulation and layout (as VIS-008/009).
- Rationale: no shader added (SHD-011), reuses the flash-area model, avoids the noise field VIS-012 is editing.
- Alternatives: a fragment shader over the frame (new shader text, per-pixel cost); point sprites (new shader).

## D2 Determinism
- Decision: whole pool stepped always; one SplitMix64 stream; draws in a fixed order (reset: x, y, z per star in index
  order; respawn: x, y in index order within a step); fixed 1/240 s steps from an anchor in integer nanoseconds.
- Rationale: positions depend only on seed, band input and the step count at a time, so 60 Hz and jittery frame times
  agree bit for bit at shared times; density cannot perturb the sequence.
- Alternatives: per-frame variable Δt (frame-rate dependent); stepping only active stars (density changes the RNG order).

## D3 Cap
- Decision: fixed 2000 on every device class and power profile (PERF-008 not consulted).
- Rationale: cost is small; the acceptance asks for an exact cap; a device-dependent cap would make goldens and tests
  device-dependent.

## D4 Light and flashes
- Decision: alpha ∝ 1/z capped at 0.8; fades at both depth ends; mean frame light bounded at 0.05 by a uniform alpha
  scale; FX-019 envelope from the squares.
- Rationale: stars brighten slowly and smoothly; the bound keeps the densest, fastest field calm; the envelope catches
  anything left (bass surges).

## D5 Speed
- Decision: three speeds; bass boost × (1 + 0.5·low) smoothed per step, capped at 0.6 depth/s; Reduce Motion × 0.5.
- Alternatives: tempo sync (VIS-015 covers it); a free slider (one more unsafe range).
