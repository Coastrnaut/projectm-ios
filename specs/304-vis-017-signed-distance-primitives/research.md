# Research: VIS-017 Signed-Distance Primitives

## VIS-017-D1: Compile site
- **Decision**: New entry points in `NoiseFieldGenerator.shaderSource` (a mode, `NoiseFieldConfiguration.signedDistance`).
- **Rationale**: SHD-011 limits `makeLibrary(source:)` to ten reviewed files; the noise field's is one and already hosts five modes. The pipeline archive key (PERF-009) covers the new text automatically.
- **Alternatives**: A separate generator with its own compile site (reviewed change in `check_compliance.py` and ADR-0024; rejected).

## VIS-017-D2: Bounded march
- **Decision**: Sphere tracing inside a bounding sphere (radius 2): analytic ray–sphere entry/exit, `t` starts at the entry, each step advances by the scene distance (at least the hit threshold), stops at a hit (d < ε·max(1, t)), at the exit, or at the step cap (min(preset cap, 128)). Misses take zero steps.
- **Rationale**: Every loop has a constant upper bound, independent of input; the bounding sphere keeps `t` finite and small (≤ camera distance + 2 r).
- **Alternatives**: Unbounded marching with a far plane only (cost depends on scene; rejected); fixed-step marching (slower, banding).

## VIS-017-D3: Primitives
- **Decision**: Inigo Quilez's standard formulas, written from the definitions (public mathematics): sphere |p| − r; torus |(|p.xz| − R, p.y)| − r; rounded box |max(|p| − b, 0)| + min(max(q.x, q.y, q.z), 0) − rr. Rotations by the drive's angle about fixed axes. Union = min, with the primitive kind tracked for colour.
- **Rationale**: Exact or bound-correct distances (Lipschitz ≤ 1), so sphere tracing never overshoots.

## VIS-017-D4: Normals and shading
- **Decision**: Tetrahedral 4-tap normal estimate at hits only; Lambert with one fixed light plus 0.15 ambient; palette colour per kind (16-stop palette at t = 0.15 sphere, 0.5 torus, 0.85 boxes); result × brightness × gain, NaN → 0, clamp 0…1.
- **Rationale**: Bounded cost (cap + 4), no secondary marches.

## VIS-017-D5: Flash estimate
- **Decision**: `NoiseFieldFlashAreas.sampleSignedDistance` evaluates the CPU mirror at the 64 sample points (as the tunnel), giving exact colours there.
- **Rationale**: Same structure as VIS-015; ≤ 64 × 100 scene evaluations per frame.

## VIS-017-D6: Measuring the GPU cap
- **Decision**: A second entry point `vis_sdf_steps_fragment` writes the step count into red (rgba16Float holds integers ≤ 2048 exactly); tests render it per preset and read back. Built only when asked (`makeStepCountPipeline`, tests), never by the app.
- **Rationale**: Direct GPU evidence for "quality presets bound step counts" rather than inference from the CPU mirror.

## VIS-017-D7: Float differences CPU vs GPU
- **Decision**: CPU–GPU agreement is checked loosely (hit/miss classification at sample points away from silhouettes, colour within a tolerance); exact equality is not expected (fast-math on GPU). The golden is the exact GPU reference per platform class.
