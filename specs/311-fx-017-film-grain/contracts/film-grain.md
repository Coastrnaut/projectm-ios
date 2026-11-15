# Contract: FX-017 Film grain

## C1 — Compositor

- `Compositor.filmGrain: FilmGrain` (default `.off`), set between frames. Inactive: no pass, no picture, output
  bit-identical. Turning it off returns the picture to the pool.
- `filmGrainFrames: Int`, `holdsFilmGrainPicture: Bool`, `lastFilmGrainFrame: UInt32` (tests, diagnostics).
- The pass runs at the `.filmGrain` position of `outputEffectOrder` (standard: last); a non-neutral Color listed before
  it is applied right before it; the flash guard and tone map come after. The grain frame comes from the frame's
  `LayerFrameContext` (presentation time, Reduce flashing).

## C2 — Pixel rule (CPU reference = GPU)

For output pixel (x, y) with input c (premultiplied rgba): cell (cx, cy) = (x ÷ size, y ÷ size) (integer division);
for channel ch (0 for r, g, b in monochrome; 0, 1, 2 in colour): h = pcg(cx + pcg(cy + pcg(frame + pcg(seed × 4 + ch))))
(32-bit wrapping); n = Float(h >> 8) × 2⁻²³ − 1; d = (scale × n) × c.a; out = max(c + d, min(c, 0)) per colour channel;
out.a = c.a. scale = 0 → out = c exactly.

The GPU's hash and noise equal the reference exactly; the output agrees within one half-float step.

## C3 — Scene entry

`fx.filmGrain` with `opacity`, `size`, `color`, `seed`, `animated` (FX-020 list); absent or disabled = default.

## C4 — App setting

`FilmGrainSetting` with the six keys; Settings → Film grain: `filmGrainToggle`, slider `filmGrainOpacity`, picker
`filmGrainSize`, picker `filmGrainColor`, stepper `filmGrainSeed`, toggle `filmGrainAnimated`. The compositors receive
`filmGrain.effective(reduceMotion: settings.systemReduceMotion)`; a Reduce Motion change re-applies it.
