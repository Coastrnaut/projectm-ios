# ADR-0064: Procedural Materials May Have Up to 16 Parameters

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: SHD-006 (`specs/245-shd-006-noise-editor`)
- **Constitution**: VI (modular boundaries), X (evidence)
- **Amends**: SHD-001 contract "at most 8 parameters" (`specs/039-shd-001-procedural-material-catalog`), SHD-003
  validation rule "at most eight parameters" (`specs/218-shd-003-shader-parameter-metadata`); ADR-0018 is otherwise
  unchanged

## Context

SHD-006 adds seed, lacunarity, gain, warp amount and warp frequency to the Noise Flow material, which already has six
parameters (scale, speed, octaves, tint, brightness, audio reactivity). Every material parameter is one `float4`
uniform slot at its position, and SHD-001 fixed the uniform block at 8 slots; SHD-003's validator refuses more than
eight parameters.

## Decision

1. The cap is 16 parameters for every material: `ShaderMetadataReader.maximumParameters`,
   `MaterialDefinition.maximumParameterCount` and the shader's `MatUniforms` (16 `float4` slots, 272 bytes, passed
   with `setFragmentBytes`, well under its 4 KB limit).
2. "Parameter i is slot i" stays: metadata, values, controls and the slot cross-check are unchanged.
3. No existing material's parameters, slots or pictures change because of the cap.

## Alternatives rejected

- A separate noise material with exactly 8 parameters: it would have to drop scale, tint and brightness.
- Packing several scalars into one slot (a `component` key): breaks the slot model in values, controls and the scan.
- A second uniform block outside the metadata (SHD-005's approach for gradient stops): the noise settings are plain
  scalars that belong in the registry, scenes and generic controls.

## Consequences

- 128 more bytes per material draw (negligible). Metadata documents with 9-16 parameters now validate; 17 are
  refused (`ShaderMetadataValidatorTests`).
