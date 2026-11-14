# Research: FX-004 Hue Shift

Decisions by Claude under the owner's best-judgement rule (owner rule 4). Luminance weights are FX-002's
Rec. 709 values w = (wR, wG, wB) = (0.2126, 0.7152, 0.0722), which sum to exactly 1.

## FX-004-D1: The operator — rotate the chroma differences about grey, rebuild around the colour's luminance

**Decision**: for a sanitised linear colour v = (r, g, b) and angle θ (c = cos θ, s = sin θ, k = s/√3):

1. differences d1 = r − g, d2 = b − g;
2. luminance y = g + wR·d1 + wB·d2 (equal to wR·r + wG·g + wB·b because the weights sum to 1);
3. rotated differences (e1, e2) = T(θ)·(d1, d2), with
   `T(θ) = [[c − k, 2k], [−2k, c + k]]` (det T = 1);
4. g' = y − wR·e1 − wB·e2, and the result is (g' + e1, g', g' + e2);
5. the gamut step (D3).

T(θ) is what Rodrigues' rotation by θ about the grey axis (1, 1, 1)/√3 does to (r − g, b − g): the rotation
fixes greys, so it acts on differences alone. Step 4 then replaces the rotation's grey component by the one that
restores the input's luminance. As a 3 × 3 matrix (before D3) the operator is
M(θ) = 1·wᵀ + P·T(θ)·D with D = [[1, −1, 0], [0, −1, 1]] and P = [[1 − wR, −wB], [−wR, −wB], [−wR, 1 − wB]].
For example

```
M(120°) = [[-0.5026, 0.6430,  0.8596],      M(240°) = [[0.1404, 1.5026, -0.6430],
           [ 0.4974, 0.6430, -0.1404],                 [0.1404, 0.5026,  0.3570],
           [-0.5026, 1.6430, -0.1404]]                 [1.1404, 0.5026, -0.6430]]
```

Every row sums to 1 (greys fixed) and wᵀ·M = wᵀ (luminance kept), exactly in real arithmetic.

**Rationale**: the angle is defined on the equal-energy opponent plane, so ±120° steps move one primary's hue
exactly onto the next (red → green → blue at +120°, the direction of CSS `hue-rotate`); the luminance
reconstruction makes "grayscale content" unchanged.

**Alternatives considered**: the W3C `hue-rotate` matrix (its rounded constants 0.213/0.715/0.072 do not sum the
luminance exactly: wᵀM differs from wᵀ by about 2e-4, and greys come out equal only up to rounding of the row
sums); a YIQ/YCbCr rotation (Cb/Cr scaling makes 120° land between primaries, and greys go through a luminance
dot product that rounds); an HSV/HSL rotation (not linear, changes luminance, discontinuous at grey); plain
Rodrigues rotation (keeps |v| but not luminance: red at 120° becomes full green, 3.4 × brighter).

## FX-004-D2: Greys are exact fixed points, in Double and in Float

**Proof**: for a grey r = g = b = x (x ≥ 0 after sanitising, any size including above 1):
d1 = x − x = 0 and d2 = 0 exactly in IEEE arithmetic; y = x + wR·0 + wB·0 = x exactly; e1 = T00·0 + T01·0 = 0
and e2 = 0 (finite coefficients); g' = x − 0 − 0 = x; the result is (x + 0, x, x + 0) = (x, x, x); its minimum
x ≥ 0, so the gamut step does not run. The output equals the input bit for bit, with or without fused
multiply-add, for every angle. This is why y is computed from g and the differences rather than as a dot product
(a dot product of a grey with weights rounds, e.g. 0.2126x + 0.7152x + 0.0722x ≠ x in Float).

For non-greys luminance is kept to rounding: |y(out) − y(in)| ≤ a few ulps (tested ≤ 1e-9 in Double over 10,000
samples, ≤ 1e-5 relative in Float on the GPU).

## FX-004-D3: Results that need a negative channel are pulled toward grey

**Decision**: after step 4, let m = min channel. If m < 0: if y ≤ 0 the result is black; else
q = y / (y − m) and every channel becomes max(y + q·(x − y), 0) (the lowest channel lands on 0). Results above 1
are left to FX-002's tone map.

**Rationale**: a luminance-keeping rotation of a saturated colour toward a brighter primary needs negative
channels (red at 120° = (−0.5026, 0.4974, −0.5026)). Clipping at 0 would change both hue and luminance; scaling
the chroma keeps both, mirroring FX-002's above-white desaturation. Red at 120° becomes pure green of red's
luminance: (0, wR/wG, 0) = (0, 0.29726, 0).

## FX-004-D4: Place in the order — last, after saturation

**Decision**: temperature → lift → gamma → gain → saturation → hue, then FX-002's tone map.

**Rationale**: (a) saturation around luminance and a luminance-keeping linear map that fixes greys commute:
M·(Y·1 + S·(v − Y·1)) = Y·1 + S·(M·v − Y·1), since M·1 = 1 and wᵀM = wᵀ; so for in-gamut colours the place does
not matter, and differs only in where the 0-clamps act; (b) appending leaves every FX-003 test vector
unchanged; (c) the hue step's gamut handling is then the last clamp before the tone map. The reference test
checks the commutation away from the clamps.

## FX-004-D5: Coefficients and the shader block

**Decision**: `ColorGradeCoefficients` gains `hueMatrix: SIMD4<Double>` (T00, T01, T10, T11; identity when off)
and `hueFlag = 32`. Hue ≠ 0 after clamping sets the flag. `CMPGrade` becomes
`{ float4 balance; float4 tone; float4 hue; float saturation; uint flags; uint pad0; uint pad1; }` (64 bytes),
`GradeBlock` mirrors it. Hue ±180 both give c = −1, s ≈ 0 (identical output to rounding).

## FX-004-D6: The red test patch reference (linear, before the tone map)

| Angle | After step 4 | After the gamut step (expected) | Hue of the result | Displayed (after tone map) |
|---|---|---|---|---|
| 0° | flag off: (1, 0, 0) | (1, 0, 0) | red | (1, 0, 0) |
| 30° | (0.70889, 0.13154, −0.44581) | (0.372852, 0.186426, 0) | orange (HSV 30°) | same |
| 90° | (−0.158636, 0.418714, −0.735986) | (0.129397, 0.258795, 0) | chartreuse (HSV 90°) | same |
| 120° | (−0.5026, 0.4974, −0.5026) | (0, 0.29726, 0) = (0, wR/wG, 0) | green | same |
| 180° | (−0.5748, 0.4252, 0.4252) | (0, 0.270003, 0.270003) | cyan | same |
| 240° = −120° | (0.1404, 0.1404, 1.1404) | (0.1404, 0.1404, 1.1404) | blue (tint) | (0.15133, 0.15133, 1) |

Every row has luminance 0.2126 (red's) before the tone map. At 240° pure blue cannot reach red's luminance
(blue's maximum is 0.0722), so the result is a lighter blue tint; the tone map keeps its hue and luminance.

## FX-004-D7: Value, parameter, setting and UI

- `ColorGrade.hue` (degrees), range −180…180, neutral 0, step hint 1; `clamped` as the other fields; Codable
  decoding treats a missing `hue` as 0 (older encoded grades).
- MOD-001: `effect.colorGrade.hue`, "Hue (degrees)", unit `.degrees`, `.continuousDefault`, after saturation.
- App: `settings.colorGrade.hue` in `ColorGradeSetting.allKeys` (so the UI-test reset and FILE-011's erase of
  settings include it), FILE-005 `LibrarySettingsPolicy.includedKeys`, the privacy allow-list
  (`scripts/run_device_tests.py`).
- Settings → Color: "Hue" slider `colorHueSlider`, readout "+30°" / "0°" / "−120°" (U+2212), VoiceOver step
  10°, spoken value via a new `SpokenUnit.signedDegrees` ("plus 30 degrees", "0 degrees", "minus 1 degree").
- No ACC-012 cap (luminance kept).

## FX-004-D8: Flash safety

The guard already measures `cmp_display(sample, grade)` with the same block, so it sees the hue step. A test
alternates black and a bright red-ish patch above the threshold with hue 120° and checks the guard engages, and
that the guard's measured luminance of a shifted steady colour equals the unshifted one (luminance kept).

## FX-004-D9: Records

ADR-0050 is amended (operator 6, block 64 bytes, red reference) instead of a new ADR: the decision extends the
same output-pass grading stage.

## FX-004-D10: Tolerances

GPU vs reference: FX-003's (one 8-bit step for the sRGB screen format, 0.002 for half float). Grey neutrality:
spread exactly 0 in both formats (D2; equal Float inputs to the same encoder give equal outputs). Grey value vs
the hue-0 output: bit-identical expected, checked within the same tolerances.
