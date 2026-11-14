# Research: SHD-004 Shader Variant Switching

- **SHD-004-D1 Variants inside the material's document.** One `variants` list per document keeps the
  parameters single-sourced. Alternatives: one document per variant (duplicated parameters, drift); a Swift
  list (code, not data; SHD-003 moved away from that).
- **SHD-004-D2 GPU families.** `MTLGPUFamily.apple7/.apple8/.apple9` exist in every SDK used (Xcode 26 CI,
  Xcode 27.2). A16 (D1, D3) is family 8; M5 (D2) supports 9; the host Mac (Apple silicon M-series) supports
  9. `requires` takes those three names; the default variant may not require anything, so fallback always
  exists. Capability is a plain struct of supported families, made from a device by
  `supportsFamily` (ProceduralMaterialShaders.swift, Metal-only) and injectable in tests.
- **SHD-004-D3 Precompiled = built in prepare and cached.** The build Mac has no Metal Toolchain (ADR-0009),
  so the library is still compiled from the module constant once per layer. `prepare` then builds the
  default pipeline (failure = layer unavailable, as SHD-001) and each supported non-default variant
  (failure = that variant unavailable, notice). Render only reads the resolved pipeline. Alternative:
  asynchronous pipeline creation (completion handlers, locks on the render path, nondeterministic tests);
  rejected for ≤ 3 tiny pipelines.
- **SHD-004-D4 Resolution.** `MaterialVariantResolution.resolve(selection:variants:capabilities:built:)`
  (plain Swift, Linux-testable) returns the drawn variant ID and an optional notice:
  unknown → `unknownVariant(id)`; requires a missing family → `unsupported(variant:requires:)`; pipeline
  missing after prepare → `pipelineUnavailable(variant)`; else none. The selection is never changed.
- **SHD-004-D5 Scene field at layer level.** `materialVariant` lives beside `content`: older versions keep
  unknown layer fields verbatim in `extra`, but drop unknown `content` keys. Written only when non-nil;
  the inspector/setters store nil for the default, so untouched scenes keep their bytes.
- **SHD-004-D6 Variant shaders.** Plasma Detailed adds two higher-frequency wave terms (time terms still
  one cycle per phase cycle, normalised by 6 instead of 4 terms → `v * 1/12`). Noise Flow Low cost drops
  the domain warp (one fbm, octaves capped at 3). Both reuse `mat_finish` (clamped, finite, opaque).
- **SHD-004-D7 App.** Materials are not drawn by the app (CMP-015), so the picker is read-only like
  SHD-003's controls; the unsupported note uses `MTLCreateSystemDefaultDevice()` once (public API).
