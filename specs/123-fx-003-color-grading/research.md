# Research: FX-003 Color Grading

All decisions by Claude under the owner's best-judgement rule (owner rule 4), 2026-11-14.

## FX-003-D1: Scope and placement

- **Decision**: one global grade in the compositor's output pass (`cmp_output`), on the finished linear
  premultiplied composite, before FX-002's tone map and the flash guard's gain. It applies to every output of
  the compositor-backed visuals (Camera, Photo, Video, Text): screen and external display, REC-003
  recording, REC-001 capture, CMP-014's bus. Native spectra and projectM are not graded.
- **Rationale**: the output pass is the one place every output already shares, so screen, recording and
  capture agree by construction; grading before the tone map lets graded values above white be mapped
  safely; CMP-013's cached layers and composite are untouched (the output pass runs every frame anyway). The
  native host would need a new full-screen pass in VisualEffects and projectM's ANGLE output a GL pass;
  both are follow-ups.
- **Alternatives**: per layer in CMP-015's inspector (multiplies passes, breaks the "one look" mental model;
  later option); a separate grading pass (an extra texture and pass for nothing); Core Image
  `CIColorKernel` (a second render path and CPU/GPU hand-off; the roadmap says "where appropriate" — it is
  not here).

## FX-003-D2: Operators, equations and order

Per pixel, on the composite's colour `v` (premultiplied, i.e. the colour shown over black), after
sanitising (NaN/±Inf → 0, negatives → 0; alpha passes through):

1. **Temperature** `T ∈ [−1, 1]`: `r = 2^(0.3·T)`, `b = 2^(−0.3·T)`, `n = 0.2126·r + 0.7152 + 0.0722·b`,
   `v ← v · (r/n, 1/n, b/n)`. A von Kries-style diagonal gain in linear RGB, ±0.3 stop on red and blue in
   opposite directions, normalised so a grey keeps its luminance. Unitless (spec Clarifications).
2. **Lift** `L ∈ [−0.1, 0.1]`: `v ← max(v·(1 − L) + L, 0)` (black moves to L, white stays at 1).
3. **Gamma** `γ ∈ [0.5, 2]`: `v ← v^(1/γ)` (v ≥ 0; 0 and 1 fixed; γ > 1 brightens mid-tones).
4. **Gain** `G ∈ [0.5, 2]`: `v ← G·v`.
5. **Saturation** `S ∈ [0, 2]`: `Y = 0.2126·v.r + 0.7152·v.g + 0.0722·v.b`, `v ← max(Y + S·(v − Y), 0)`.

Then FX-002's tone map, then × the flash guard's gain.

- **Rationale**: white balance first (it corrects the input's colour cast before tone shaping), then the
  classic lift/gamma/gain that colourists expect from the three names, then saturation last so it acts on
  the final tones. The classic formula keeps white at 1 under lift and gamma, unlike ASC CDL's offset, which
  would shift white too (the roadmap row names lift, not offset).
- **Alternatives**: ASC CDL slope/offset/power (standard interchange, but "lift" would move white); grading in
  sRGB-encoded space (the composite and FX-002 are linear; one space avoids encode/decode per pixel); a
  Kelvin-based white point via CIE daylight and Bradford (more maths, false precision for an artistic
  control).

## FX-003-D3: Neutral short-circuit and per-operator identities

- **Decision**: the CPU derives an operator flag set: temperature active iff `T ≠ 0`, lift iff `L ≠ 0`, gamma
  iff `γ ≠ 1`, gain iff `G ≠ 1`, saturation iff `S ≠ 1`. The shader skips inactive operators; with no flag it
  returns the composite pixel itself (not even sanitised), so `cmp_tone_map` receives exactly the ungraded
  input and the output is bit-identical to bypass for every pixel, including NaN and over-range pixels.
- **Rationale**: `x·1.0`, `pow(x, 1.0)` and `Y + 1·(v − Y)` are not guaranteed exact in float (the last is
  not); explicit skips make each neutral control an exact identity. The flag test is uniform per draw, so
  the branch costs nothing measurable.

## FX-003-D4: Coefficients on the CPU

- **Decision**: `ColorGrade.coefficients` computes, in Double, the balance gains `(r/n, 1/n, b/n)`, the lift
  scale `1 − L` and offset `L`, the exponent `1/γ`, the gain and the saturation, plus the flags; the shader
  receives them rounded to Float in a 48-byte block (`float4 balance; float4 tone; float saturation; uint
  flags; uint pad[2]`) by `setFragmentBytes` / `setBytes` (copied into the command stream; no buffer).
  The reference applies the same coefficients in Double.
- **Rationale**: no `exp2` or division per pixel; the reference and the shader cannot drift on derivations.

## FX-003-D5: Flash guard

- **Decision**: `cmp_display(c, grade) = cmp_tone_map(cmp_grade(c, grade))` is one Swift string spliced into
  the compositor's source and the flash guard's; the guard's 4,096 samples read through it with the same
  block (bound at compute index 3). Its gain then multiplies the displayed colour in `cmp_output`.
- **Rationale**: the limiter must judge the shown picture (ACC-012, FX-019): a gain raise that turns a
  sub-threshold flicker into a visible flash is limited; a grading change can never hide a flash. The edit
  to `CompositeFlashGuard` is two lines (the spliced string and the sample call) plus the bound block.

## FX-003-D6: Premultiplied alpha

- **Decision**: grade the premultiplied colour (the composite over black), alpha unchanged.
- **Rationale**: every output treats the composite as over black (the screen drawable is opaque, the guard
  measures over black); grading straight colour would leave transparent black un-lifted although the screen
  shows black there. Colour above alpha in captures is the "emissive" case FX-002 already allows.

## FX-003-D7: Parameters and persistence

- **Decision**: MOD-001 IDs `effect.colorGrade.temperature|lift|gamma|gain|saturation` in group
  `effect.colorGrade` ("Color"), continuous, modulation `.continuousDefault`, ranges and defaults read from
  `ColorGrade` (single source). Registered in the app's scene registry (`SceneArchiveService.appRegistry`) and
  the golden renderer's, so bindings and scene rows naming them validate. Live modulation is not wired (no
  compositor-backed visual has a modulator). Storage: one global setting, five UserDefaults Doubles
  `settings.colorGrade.*`; absent, NaN or non-number → neutral, out of range → clamped; added to FILE-005's
  `LibrarySettingsPolicy.includedKeys` and the privacy `ALLOWED_KEYS`. Not in scenes (spec Clarifications).
- **Alternatives**: one encoded JSON key (opaque to the backup's typed values and the privacy review);
  a scene field (later; needs CMP-006-style optional field and scene UI).

## FX-003-D8: Reference image and tolerances

- **Decision**: a 64 × 8 image: rows 0–3 linear ramps 0…1 in grey, red, green and blue; row 4 the
  primaries, secondaries, black and white; row 5 fixed greys (0.18, 0.5, 0.9, …); row 6 a 0…4 over-range grey
  ramp; row 7 a NaN/Inf/negative row (bit-identity at neutral covers all of them). Tolerances: one 8-bit step
  for `bgra8Unorm_srgb`, 0.002 for `rgba16Float` (spec Clarifications).

## FX-003-D9: GPU timing

- **Decision**: record the output pass's GPU time at 1920 × 1080 with neutral and with every operator active
  (median of 30 command buffers' `gpuEndTime − gpuStartTime`, after 5 warm-ups) on the Mac; no threshold.
  Device frame rate is a `{device}` task.
- **Result (Mac Studio, 2026-11-14, `ColorGradeOutputTests.testOutputPassGPUTimeIsRecorded`)**: neutral 0.033 ms,
  every operator active 0.044 ms (FX-002's tone-mapped pass alone measured 0.037-0.070 ms). Not device evidence.
- **Operator error table** (worst |GPU − reference| over the D8 image, `testEachOperatorMatchesTheReference`):

  | Setting | Half float | Screen (8-bit steps) |
  |---|---|---|
  | temperature +0.6 / −1 | 0.00049 / 0.00049 | 0.60 / 0.77 |
  | lift +0.05 / −0.1 | 0.00044 / 0.00048 | 0.50 / 0.52 |
  | gamma 0.5 / 1.8 | 0.00048 / 0.00048 | 0.74 / 0.52 |
  | gain 0.5 / 2 | 0.00048 / 0.00048 | 0.56 / 0.54 |
  | saturation 0 / 2 | 0.00049 / 0.00048 | 0.66 / 0.57 |
  | all five (T 0.4, L 0.02, γ 1.3, G 1.4, S 1.5) | 0.00049 | 0.62 |

  Neutral vs bypass: 512/512 pixels bit-identical in `bgra8Unorm_srgb` and `rgba16Float` (416 in range; the NaN,
  Inf, negative and over-range pixels are identical too).

## FX-003-D10: ACC-012's sensory safety profile

- **Decision** (after ACC-012 was integrated on 2026-11-14): the flash guard keeps measuring the graded, tone-mapped
  output with the profile's envelope (`Compositor.flashLimits`). In addition, gain's boost above 1 is treated as an
  intensity-type value: the app hands the compositors `1 + intensity(gain − 1, maximum: 2 − 1)` (Reduced ≤ 1.5,
  Strict ≤ 1.25; Standard and Custom at limit 1 unchanged, so Standard stays bit-identical). The stored setting is
  not changed, so lowering the profile restores the user's grade. Dimming (gain < 1) is never capped.
- **Rationale**: the profile's intensity limit exists to cap brightness boosts (it caps glow intensity); gain is the
  grade's direct brightness boost. Lift (at most +0.1 linear), gamma (fixed 0 and 1) and saturation (luminance-
  neutral) are bounded by their ranges, and any flash they make is judged by the guard.
- **Alternatives**: no cap (the guard alone limits flashes, but a Strict user could still double steady
  brightness); capping every control (would change saturation and temperature, which do not raise luminance).
