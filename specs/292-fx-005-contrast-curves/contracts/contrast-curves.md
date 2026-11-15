# Contract: FX-005 contrast curves

C1. `ContrastCurve.value(_ x: Double, curve:, strength:) -> Double`: input NaN → 0, clamped to 0…1; output in 0…1,
f(0) = 0, f(1) = 1 exactly, monotone non-decreasing; `linear` or strength ≤ 0 returns the clamped input.

C2. Grade step 7 (`ColorGradeCoefficients.apply`, `cmp_grade`): runs only when a curve flag (256 S-curve, 512
Filmic) is set; `v ← ToneMap.map(v, a)`, then C1 on each channel. Linear/strength 0: the step is skipped and the
result is bit-identical to the grade without FX-005.

C3. Shader block `CMPGrade`: `{ float4 balance; float4 tone; float4 hue; float saturation; uint flags; uint pad0;
uint pad1; float4 contrast; }`, 80 bytes, `contrast` at offset 64 = (c = 1 + s, s, τ = 0.1, σ = 0.5).

C4. Scene `fx.grade` entry: `parameters.contrast` ∈ {`linear`, `sCurve`, `filmic`}, `parameters.contrastStrength`
number 0…1. Missing → linear / 0.5; unknown name or non-number → fallback with a `valueClamped` warning.

C5. Settings keys `settings.colorGrade.contrast`, `settings.colorGrade.contrastStrength`, in `ColorGradeSetting.allKeys`,
FILE-005's included keys and the device privacy allow-list.
