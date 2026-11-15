# Research: VIS-019 Cymatic Line Patterns

## VIS-019-D1: Compile site
- **Decision**: New entry points in `NoiseFieldGenerator.shaderSource` (a mode, `NoiseFieldConfiguration.cymatic`).
- **Rationale**: SHD-011 limits `makeLibrary(source:)` to reviewed files; the noise field's already hosts the procedural modes. The PERF-009 archive key covers the new text automatically.
- **Alternatives**: A separate generator with its own compile site (a reviewed change in `check_compliance.py`, ADR-0024; rejected).

## VIS-019-D2: Standing-wave model
- **Decision**: Square-plate Chladni superposition F = cos(nπx)cos(mπy) + s·cos(mπx)cos(nπy) on the unit plate; eight driven modes in rising complexity plus a resting mode (1,1,+); blended linearly by weights and normalized by their sum; lines where |F̄| is small.
- **Rationale**: The classic closed-form approximation of a free square plate's figures; cheap (4 cosines per mode), smooth, bounded (|F| ≤ 2), identical on CPU and GPU up to float rounding.
- **Alternatives**: Simulating the plate (wave equation on a grid): far costlier, needs state textures, and not deterministic across GPUs; Bessel circular-plate modes (no closed form in MSL; rejected).

## VIS-019-D3: Band selection and hysteresis
- **Decision**: The selected range is All or one of VIS-007's thirds; the loudest band's relative position picks one of 8 equal parts; a new part wins only at ≥ 1.25 × the current part's loudest band (about +2 dB).
- **Rationale**: ANL-002 bands are log-spaced from 20 Hz, so thirds are roughly decades; a single band index maps a pure tone to one part deterministically; the hysteresis stops two neighbouring bands (a tone on a band edge) from flickering.

## VIS-019-D4: Linear slews for an exact settle
- **Decision**: Weights and amplitude move linearly at fixed rates (weights 2/s; amplitude +4/s, −2/s; halved by Reduce Motion), on the injected clock with ≤ 0.25 s per step.
- **Rationale**: An exponential smoother never reaches its target, so "settles to baseline" could only hold within a tolerance; linear slews reach it exactly in bounded time (≤ 0.5 s, 1 s with Reduce Motion), and the frame then equals the resting frame bit for bit.

## VIS-019-D5: Measuring the pattern on the GPU
- **Decision**: A tests-only entry point `vis_cym_mask_fragment` writes F̄ in red and L in green to an `rgba16Float` target; the nodal mask is |F̄| ≤ 0.04 (at amplitude 0) from that read-back, and the CPU mirror computes the same mask.
- **Rationale**: Reading the field directly avoids inferring lines from palette colours; the same pattern as VIS-017-D6's step-count view.

## VIS-019-D6: Flash estimate
- **Decision**: The 64 FX-019 samples come from `CymaticField.shade` at the sample points.
- **Rationale**: Same approach as every noise-field mode (ADR-0066 decision 3); thin lines are under-sampled, so the estimate is conservative only on average, but brightness ≤ 0.8 and amplitude rises at most 4/s × 0.45 = 1.8 brightness/s keep every area smooth; the envelope bounds rises with Reduce flashing on.
