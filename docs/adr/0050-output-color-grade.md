# ADR-0050: The Compositor's Output Pass Grades the Composite Before the Tone Map, and the Flash Guard Measures the Graded Colour

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-003 (`specs/123-fx-003-color-grading`)
- **Constitution**: VI (modular boundaries: grading inside `Packages/Compositor`), VIII (upstream fidelity: neutral is
  bit-identical), X (evidence-based quality); sensory safety (FX-019, ACC-012)
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

## Alternatives considered

ASC CDL (its offset moves white); grading in sRGB-encoded space (an encode/decode per pixel, and the composite is
linear); a separate grading pass or Core Image kernel (an extra texture and pass); per-layer grading in CMP-015's
inspector (later option); Kelvin white points via CIE daylight and Bradford (false precision for an artistic control).
