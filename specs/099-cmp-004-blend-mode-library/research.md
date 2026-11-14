# Research: CMP-004 Blend Mode Library

## CMP-004-D1: How modes are named and carried

- **Decision**: `LayerBlendMode: String, CaseIterable` with raw values `normal`, `add`, `screen`,
  `multiply`, `overlay`, `difference`. The raw value is the scene format's `composite.blend` string.
- **Rationale**: one spelling for the contract and the document; SceneFormat maps with
  `init(rawValue:)` and needs no switch (ADR-0028 expected the capture switch to change).
- **Alternatives**: a separate mapping table in SceneFormat (two lists to keep in step).

## CMP-004-D2: Equations and the "add" semantics

- **Decision**: W3C Compositing and Blending Level 1 separable modes with source-over:
  co = cs·(1 − αb) + cb·(1 − αs) + αs·αb·B(Cb, Cs); αo = αs + αb·(1 − αs). Add is the separable
  B = min(1, Cb + Cs) inside the same formula.
- **Rationale**: one formula, identical alpha for all modes, add over transparent = normal; clamped
  add equals Photoshop's Linear Dodge (Add).
- **Alternatives**: Porter-Duff plus (`lighter`): alpha adds and colour can grow without bound in a
  half-float composite; different alpha from the other modes.

## CMP-004-D3: Blend space

- **Decision**: B on sRGB-encoded straight colours (unpremultiply, clamp 0…1, encode with the exact
  sRGB piecewise curve), result decoded to linear; coverage terms in linear premultiplied (ADR-0037).
- **Rationale**: opaque results equal what designers and browsers produce for the same encoded
  colours; normal layers and every existing composite stay bit-identical because normal keeps its
  linear "over" path, and B = Cs makes the formula collapse to it anyway.
- **Alternatives**: all in linear light (screen/overlay look very different from every design tool);
  everything in encoded space (changes all existing output and goldens; contradicts CMP-001's linear
  contract).

## CMP-004-D4: Reading the backdrop on the GPU

- **Decision**: two composite textures. A non-normal layer ends the current render encoder, draws
  `cmp_blend` full screen into the other texture (backdrop and picture as inputs, blending off,
  load action don't-care), then the textures swap and the next normal layers continue with load
  action load. The second texture is taken from the texture pool lazily (first non-normal draw at a
  size).
- **Rationale**: works on every Metal device, including the iOS Simulator and Intel/AMD Macs; normal
  stacks unchanged; at most eight layers, so at most eight extra passes.
- **Alternatives**: framebuffer fetch (`[[color(0)]]`) — one pass, cheaper on Apple GPUs, but not
  supported by the Simulator's Metal or non-Apple GPUs. Fixed-function factors — screen and add fit,
  multiply/overlay/difference within source-over do not. A blit copy of the backdrop per mode layer —
  same cost as a pass plus a copy.

## CMP-004-D5: Scene format and unknown modes

- **Decision**: no format change, version stays 1. Validation warns only for unknown names. Live
  state keeps unknown names in `preservedBlendModes`; capture writes them back while the live mode is
  `.normal`.
- **Rationale**: `composite.blend` was designed as an open string (SCN-001), so the six names were
  always representable; version-1 files that already named a mode now draw it. QA-004's matrix lists
  version transitions, and there is none.
- **Alternatives**: a version bump with a migration (nothing to migrate); dropping unknown names on
  capture (violates SCN-001's keep-unknown rule).

## CMP-004-D6: Tolerance and test inputs

- **Decision**: test pictures are uploaded as half floats from a buffer (a pattern layer), so the GPU
  sees exactly the quantized inputs the CPU reference is fed. Tolerance: 1e-3 per linear channel in
  the composite; 1/255 per channel in an 8-bit sRGB output against the reference encoded and rounded.
- **Rationale**: half-float spacing is ≤ 4.9e-4 below 1, float32 `pow` adds ≈1e-6; 1e-3 still
  separates every mode (the smallest difference between two modes on the grid is ≥ 0.01).

## CMP-004-D7: Performance measurement

- **Decision**: an XCTest bench, skipped unless `CMP004_BENCH=1`, renders a 1920 × 1080 two-layer
  stack per mode 120 times and reports the median `gpuEndTime − gpuStartTime`; run in Release on the
  Mac and recorded in `docs/test-reports/blend-modes.md` as not device evidence.
