# ADR-0050: The Compositor's Output Pass Grades the Composite Before the Tone Map, and the Flash Guard Measures the Graded Colour

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-003 (`specs/123-fx-003-color-grading`)
- **Constitution**: VI (modular boundaries: grading inside `Packages/Compositor`), VIII (upstream fidelity: neutral is
  bit-identical), X (evidence-based quality); sensory safety (FX-019, ACC-012)
- **Amended**: 2026-11-14 by FX-004 (hue shift; see the amendment below)
- **Builds on and amends**: ADR-0047 (FX-002: "tone map, then × gain" becomes "grade, tone map, then × gain"),
  ADR-0013 (CMP-001 output pass), ADR-0040 (CMP-013 caching, unaffected), ADR-0049 (ACC-012 safety clamp)
- **Number**: 0050, the next free number after ACC-012's 0049; 0015, 0016, 0025, 0026, 0031, 0045 and 0046 stay
  unused.

## Context

The roadmap row FX-003 asks for lift, gamma, gain, saturation and temperature, with the acceptance "neutral defaults
are pixel-equivalent to bypass within tolerance". The compositor-backed visuals (Camera, Photo, Video, Text) share
one output pass for every output (screen, external display, REC-003 recording, REC-001 capture, CMP-014's bus), and
FX-019's composite flash guard measures through the same tone-map function. The native spectra and projectM do not
use that pass.

## Decision

1. **One grading stage, in the existing output shader**, before FX-002's tone map: `cmp_display(c) =
   cmp_tone_map(cmp_grade(c))`, then × the guard's gain. No new pass, texture or buffer; the coefficients are a
   48-byte block copied with `setFragmentBytes` / `setBytes`.
2. **Operators and order** (research FX-003-D2), in linear light on the premultiplied colour (the composite over
   black): temperature (a luminance-normalised von Kries gain, ±0.3 stop on red and blue), lift (`max(v·(1 − L) + L,
   0)`), gamma (`v^(1/γ)`), gain (`G·v`), saturation around Rec. 709 luminance (`max(Y + S·(v − Y), 0)`). Master
   controls; ranges temperature −1…1, lift −0.1…0.1, gamma 0.5…2, gain 0.5…2, saturation 0…2.
3. **Neutral is bypass, bit for bit.** The CPU sets one flag per non-neutral control; with no flag `cmp_grade` returns
   the composite pixel untouched, so the output equals FX-002's for every pixel (measured: 512/512 pixels of the
   reference image, both formats). Each neutral control is skipped, so it is an exact identity.
4. **The flash guard measures the graded, tone-mapped colour** (`cmp_display` spliced into its source, the same block
   at compute buffer 3). A grade that turns a sub-threshold flicker into a visible flash is limited; a grade cannot
   hide a flash. ACC-012's profile envelope (`flashLimits`) applies unchanged.
5. **ACC-012 intensity limit on gain**: the app caps gain's boost above 1 at the profile's intensity limit ×
   (2 − 1) (Strict: at most 1.25); Standard unchanged; dimming is never capped. Lift (≤ +0.1 linear), gamma and
   saturation are not capped: their brightening is bounded by their ranges and the guard judges any flash.
6. **Scope**: compositor-backed visuals only; the native spectra and projectM are not graded (follow-up: a shared
   native step). One global setting (five UserDefaults keys), MOD-001 descriptors in a `ColorGradeParameters` target,
   not in scenes yet.

## Consequences

- Graded colours above white are tone-mapped (hue kept, never NaN); recordings and captures match the screen.
- Cost on the Mac (1920 × 1080): 0.033 ms neutral, 0.044 ms with every operator (median of 30; recorded only,
  device check pending).
- CMP-013's layer and composite caches stay valid when the grade changes (the composite is graded at output).
- Every golden image is unchanged.

## Amendment 2026-11-14: FX-004 hue shift (decided by Claude under owner rule 4)

`specs/126-fx-004-hue-shift` (research FX-004-D1 to D10) adds a sixth master control to the same stage instead of a
new pass or ADR:

1. **Operator 6, hue θ (degrees −180…180, neutral 0), after saturation and before the tone map.** The differences
   d = (r − g, b − g) are multiplied by `T(θ) = [[c − k, 2k], [−2k, c + k]]` (c = cos θ, k = sin θ/√3), which is what
   a rotation by θ about the grey axis (1, 1, 1)/√3 does to them (+120° maps red's hue to green's, as CSS
   `hue-rotate`); the colour is rebuilt around its own luminance y = g + wR·d1 + wB·d2: g' = y − wR·e1 − wB·e2,
   v = (g' + e1, g', g' + e2). As a 3 × 3 matrix every row sums to 1 and wᵀM = wᵀ (Rec. 709 weights sum to 1). A
   result with a negative channel m is pulled toward y by y/(y − m) (hue and luminance kept); above white is left to
   the tone map.
2. **Greys are exact fixed points**: for r = g = b = x the differences are exactly 0 in IEEE arithmetic, so y = x
   and the output is (x, x, x) bit for bit at every angle (measured on the GPU: 37/37 greys of a ramp 0…4,
   spread 0 and identical to hue 0, at 30, 90, 180 and −120°, half float and sRGB). The W3C `hue-rotate` matrix was
   rejected because its rounded constants keep greys and luminance only to about 2e-4.
3. **Red test patch** (linear, displayed): 0° (1, 0, 0); 120° (0, wR/wG, 0) = (0, 0.29726, 0); −120° (= 240°)
   (0.1404, 0.1404, 1.1404) before the tone map, (0.15133, 0.15133, 1) shown. GPU errors 0.00014 (half float) and
   0.0018 (sRGB, under one 8-bit step).
4. **Block**: `CMPGrade` gains `float4 hue` (T row by row) after `tone`: 64 bytes; flag bit 5 (32). Hue 0 leaves
   the flag off, so every FX-003 output and the neutral bypass stay bit-identical; every golden image is unchanged.
5. **Safety**: the guard measures the shifted colour. A hue shift keeps luminance but can create redness: a black ↔
   blue flicker (luminance step 0.072, not limited) turned red by +120° is limited (minimum gain 0.17). ACC-012 does
   not cap the hue.
6. One more setting key `settings.colorGrade.hue` (FILE-005 backup, FILE-011 Settings erase, privacy allow-list),
   MOD-001 ID `effect.colorGrade.hue` (unit degrees), and a "Hue" slider in Settings → Color.

## Alternatives considered

ASC CDL (its offset moves white); grading in sRGB-encoded space (an encode/decode per pixel, and the composite is
linear); a separate grading pass or Core Image kernel (an extra texture and pass); per-layer grading in CMP-015's
inspector (later option); Kelvin white points via CIE daylight and Bradford (false precision for an artistic control).
