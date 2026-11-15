# Research: FX-006 Chromatic Split

## FX-006-D1: Own pass after the stack phase, not in the per-pixel grade

- **Decision**: A separate full-screen pass `cmp_chromatic` (`ChromaticSplitPass`) writing one pooled picture, run
  in the compositor's output-effect walk. Not part of `cmp_grade`/`cmp_output`.
- **Rationale**: the split reads neighbouring pixels; the grade is per pixel and FX-005 edits it in parallel. The
  `OutputGradePass` pattern (own function, own picture, pooled, released when unused) is proven.
- **Alternatives**: fold into `cmp_output` (would also need the guard's measure pass to sample neighbours, and
  conflicts with FX-005); VisualEffects' `PostProcessEffect` (serves only the native spectra).

## FX-006-D2: Split vector

- **Decision**: amountPx = amount × min(width, height). Linear: v = amountPx × (cos θ, −sin θ) in texture
  coordinates (y down), components with |c| < 1e-9 snapped to 0. Radial: v = amountPx × (p − c) ÷ |c|, c the centre
  ((w−1)/2, (h−1)/2) in pixel-index coordinates, so |v| ≤ amountPx and v = 0 at the centre. Red is read at p − v
  (appears moved by +v), blue at p + v.
- **Rationale**: one formula for every size; a whole-pixel amount at 0°/90° gives exact integer shifts for tests.

## FX-006-D3: Edge rule

- **Decision**: fade f = clamp(e ÷ max(amountPx, 1), 0, 1) with e = min(x, w−1−x, y, h−1−y) in pixel indices;
  v' = f × v. Samples are clamped to [0, w−1] × [0, h−1] as well. Then |v'| ≤ e, so every sample lies inside the frame
  mathematically, and the clamp only guards rounding; the border ring (e = 0) is passed through.
- **Rationale**: pure clamp-to-edge smears border pixels inward over the amount; pure fading alone relies on float
  maths. Both together give a crisp, testable rule ("edges stay within frame bounds").
- **Alternatives**: mirror addressing (pulls interior colour to the border, changes border pixels); a fixed band.

## FX-006-D4: Sampling, alpha and non-finite values

- **Decision**: bilinear by hand from `read` (four reads per sample, clamped); a weight of exactly 0 selects the
  first texel without arithmetic, so whole-pixel offsets copy exactly and a non-finite neighbour cannot leak
  through `0 × Inf`. Output = (R from p − v, G and own pixel at p, B from p + v), alpha = max of the three samples'
  alpha (premultiplied colour ≤ alpha). v' = 0 or a non-finite own pixel → the own pixel unchanged.
- **Rationale**: `access::read` textures need no sampler state; the CPU reference mirrors it exactly.

## FX-006-D5: Value and ranges

- **Decision**: `ChromaticSplit { isEnabled, amount (0…0.02, default 0.005), angleDegrees (0…360, default 0),
  isRadial }`. Active when enabled and amountPx > 0. NaN → default; out of range → nearest bound; angle wraps.
- **Rationale**: 2% of the shorter side is a strong but bounded look (≈ 15 px on a 750-px-wide phone).

## FX-006-D6: Place in the FX-020 chain

- **Decision**: new `OutputEffectKind.chromatic = "fx.chromatic"`, appended to the enum, so the standard order is
  Trails, Color, Chromatic split and every stored order without it reads with it appended. The compositor walks the
  order: a non-neutral Color (output pass allowed) that comes before an active Trails or split is applied by
  `OutputGradePass` right before the first such effect, and the outputs then use the neutral grade; otherwise Color
  stays in the output pass. Trails' graded-history reset rule is unchanged.
- **Rationale**: honours the user's order with the existing passes; Trails/Color behaviour is identical to FX-020
  whenever the split is inactive.

## FX-006-D7: Shader policy

- **Decision**: `ChromaticSplitPass.source` is concatenated into the existing `CompositorShaders.library` call in
  `Compositor.init` (the reviewed compile site) and added to `CompositorShaderSources.archived` (PERF-009 key). No
  new compile site; `check_compliance.py` unchanged.

## FX-006-D8: No safety cap, no contrast-aware softening

- **Decision**: see Clarifications. The split moves channel values only; the flash guard measures the shown frame.

## FX-006-D9: Settings and storage

- **Decision**: global `ChromaticSplitSetting` (UserDefaults `settings.chromatic.enabled|amount|angle|radial`,
  default values not written), included in backups (FILE-005 includedKeys) and erase, privacy allow-list, UI-test
  reset; scene/preset entry `fx.chromatic` with `amount`, `angle`, `radial` (0/1); `isDefault` treats a disabled
  split as default so older scenes still encode byte-identically.
