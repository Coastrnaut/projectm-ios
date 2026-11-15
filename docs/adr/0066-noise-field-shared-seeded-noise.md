# ADR-0066: The Noise Field Compiles a Module-Constant Shader Built from SHD-006's Shared Seeded Noise

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: VIS-013 (`specs/252-vis-013-noise-field`)
- **Constitution**: I (public APIs), VI (modular boundaries), X (evidence); ADR-0024 (SHD-011 code-execution policy)

## Context

VIS-013 asks for "layered procedural noise with frequency and seed controls", accepted when the "same seed and
settings produce matching frames on same GPU class". SHD-006 already has deterministic seeded noise (an integer lattice
hash, fBm, domain warp) inside the Noise Flow material, whose module depends on the native visuals package, so the
native visuals could not use it. A native visual drawn by a fragment shader also needs a new Metal compile site, and
ADR-0024 makes every compile site a reviewed entry of `check_compliance.py`'s `METAL_SOURCE_ALLOWED`.

## Decision

1. SHD-006's noise core moves to `VisualGenerators` as `SeededNoise` (CPU mirror) and `SeededNoiseShader.functions`
   (the Metal text of `mat_nhash`, `mat_snoise`, `mat_sfbm`). ProceduralMaterials' `NoiseTextureReference` calls the
   CPU mirror. The material's shader literal stays unchanged, because SHD-001's source-safety test forbids
   interpolation in it; `SharedNoiseSourceTests` asserts it contains the shared text verbatim, and `MaterialNoiseTests`'
   recorded digests prove the material's pictures unchanged.
2. `NoiseFieldGenerator.swift` becomes the tenth entry of `METAL_SOURCE_ALLOWED`. It compiles only
   `NoiseFieldGenerator.shaderSource`, a concatenation of three module constants (the standard include, the shared
   functions, its own body); nothing comes from user text, files, documents or downloads. Its pipeline goes through
   PERF-009's native pipeline archive, whose key now also covers this source.
3. Flash safety for a non-geometric visual: the CPU mirror is sampled on an 8 × 8 grid each frame and FX-019's
   envelope solves the gain over the 17 areas from those samples.

## Consequences

- One definition of the noise; a change to it changes both visuals, and the material's digests catch it.
- The allowlist grows by one reviewed file; no user-authored shader becomes possible.
- The flash estimate is exact at its sample points only; the field is smooth at its frequencies (≤ 8 base cells
  across the shorter side), and the envelope additionally bounds every rise when Reduce flashing is on.
