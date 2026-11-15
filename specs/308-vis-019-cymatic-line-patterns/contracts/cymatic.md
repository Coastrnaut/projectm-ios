# Contract: VIS-019 Cymatic Lines mode

- **C1 Configuration**: `NoiseFieldConfiguration.cymatic(_ settings:reduceMotion:palette:)`; `clamped()` turns every other mode off (including `signedDistance`) when `cymatic != nil`. `NoiseFieldGenerator.mode` returns `.cymatic` first.
- **C2 Frame**: per frame the generator advances `cymaticDrive` on the frame context's clock with the bands and the selected range, samples the CPU mirror at 64 points (`NoiseFieldFlashAreas.sampleCymatic`), takes FX-019's gain, writes the shared uniform block (brightness × gain in slot 3) plus the 40-float cymatic block at buffer 1, and draws one full-screen triangle with `vis_cym_fragment`. Entering the mode or a loop restart resets the drive to rest.
- **C3 Pattern**: a steady pure tone settles the drive's target to the part of its loudest selected band; two tones in different parts give nodal masks differing in ≥ 10% of pixels (CPU and GPU, `makeCymaticMaskPipeline()` tests-only view).
- **C4 Settle**: after 1 s of silence (2 s with Reduce Motion) the drive equals the rest state exactly, and the frame equals a fresh generator's silent frame when the gain is 1.
- **C5 Finiteness**: every output value is finite and in 0…1 for any bands, time and size.
- **C6 App**: Visual choice `cymatic` ("Cymatic Lines"), key `settings.cymatic.bands`, host style `.cymatic(bands:)` (in place on range change), accessibility label/identifier/value as spec R13.
