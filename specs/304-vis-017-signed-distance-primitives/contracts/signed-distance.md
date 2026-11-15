# Contract: VIS-017 SDF Shapes mode

- **C1 Configuration**: `NoiseFieldConfiguration.signedDistance(_ settings:reduceMotion:palette:)`; `clamped()` turns every other mode off when `signedDistance != nil`. `NoiseFieldGenerator.mode` returns `.signedDistance` first after reaction diffusion.
- **C2 Frame**: per frame the generator advances `signedDistanceDrive` on the frame context's clock with VIS-007's groups of the bands, samples the CPU mirror at 64 points (`NoiseFieldFlashAreas.sampleSignedDistance`), takes FX-019's gain, writes the shared uniform block plus a 12-float SDF block at buffer 1, and draws one full-screen triangle with `vis_sdf_fragment`. Entering the mode or a loop restart resets the drive (rest pose, angle 0).
- **C3 Step cap**: for every preset and every pixel the march takes ≤ `quality.stepCap` steps (and never more than 128). `makeStepCountPipeline()` (tests) draws step counts into red.
- **C4 Finiteness**: every output value is finite and in 0…1 for any bands, time and size.
- **C5 App**: Visual choice `signedDistance` ("SDF Shapes"), key `settings.signedDistance.quality`, host style `.signedDistance(quality:)` (in place on quality change), accessibility label/identifier/value as spec R11.
