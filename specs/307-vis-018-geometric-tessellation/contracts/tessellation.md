# Contract: VIS-018 Tessellation mode

- **C1 Configuration**: `NoiseFieldConfiguration.tessellation(_ settings:reduceMotion:palette:)`; `clamped()` turns every other mode off when `tessellation != nil`. `NoiseFieldGenerator.mode` returns `.tessellation` first. The drawn palette is `settings.palette`'s unless the shared palette is not Spectrum.
- **C2 Frame**: per frame the generator advances `tessellationDrive` on the frame context's clock with VIS-007's groups of the bands, samples the CPU lattice at 64 points (`NoiseFieldFlashAreas.sampleTessellation`), takes FX-019's gain, writes the shared uniform block plus an 8-float tessellation block at buffer 1, and draws one full-screen triangle with `vis_tess_fragment`. Entering the mode or a loop restart resets the drive.
- **C3 Alignment**: the tile at every pixel depends only on (width, height, tiling, N) and satisfies spec A1–A6. `makeCellPipeline(format:)` (tests) draws (i, j, shape, edge px) per pixel.
- **C4 Finiteness**: every output value is finite and in 0…1 for any bands, time and size.
- **C5 App**: Visual choice `tessellation` ("Tessellation"), five `settings.tessellation.*` keys, host style `.tessellation(TessellationSettings)` (in place on any change), accessibility label/identifier/value as spec Clarifications Q5.
