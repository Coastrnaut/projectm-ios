# Tasks: SHD-001 Procedural Material Catalog

**Input**: Design documents from `specs/039-shd-001-procedural-material-catalog/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/material-catalog.md,
quickstart.md

**Tests**: Requested by the spec (SHD-001-R8, R11-R14) and the owner's rule 7 budgets: a unit test
about 1-2 s and at most 10 s, the package suite under 1 minute, GPU tests at 64 × 64.

**Format**: `[ID] [P?] [Story] Description`. `{device}` = needs D1-D3 and a person; left open by
this row.

## Phase 1: Setup

- [ ] SHD-001-T01 Add the `ParameterGraph` package dependency, the `ProceduralMaterials` target (dependencies Compositor, ParameterGraph), the `ProceduralMaterialsTests` test target (adds FlashSafety, AnalysisFeatures) and the target in the `Compositor` library product in `Packages/Compositor/Package.swift`, with header comments

## Phase 2: Foundational (blocks every story)

- [ ] SHD-001-T02 [P] `MaterialKind` (cases gradient, plasma, noiseFlow, tunnel, starfield; ID `material.<raw value>`) and `MaterialDefinition` (kind, id, displayName, summary, group, parameters ≤ 8 with parameter *i* = uniform slot *i*, fragmentFunction `mat_<name>`, speed and audioReactivity IDs) in `Packages/Compositor/Sources/ProceduralMaterials/MaterialDefinition.swift`
- [ ] SHD-001-T03 `ProceduralMaterialCatalog` with the 28 parameters exactly as the data-model table (IDs, names, kinds, ranges, defaults, units, policies), `materials`, `definition(_:)`, `material(withID:)` (nil for unknown IDs), `descriptors`, `retiredIDs` (empty), `makeRegistry()`, `defaultValues(for:)` in `Packages/Compositor/Sources/ProceduralMaterials/ProceduralMaterialCatalog.swift`
- [ ] SHD-001-T04 [P] `MaterialParameterValues` (defaults at init; `set` clamps continuous, clamps and snaps integers to the step, clamps colors, refuses non-finite, unknown ID, wrong kind and unknown enum case with `MaterialParameterError` leaving the stored value; `slot(i)` as `SIMD4<Float>`) in `Packages/Compositor/Sources/ProceduralMaterials/MaterialParameterValues.swift`
- [ ] SHD-001-T05 [P] `MaterialMotion` (dt clamped to 0…0.1 s, NaN → 0; band level = mean of finite bands clamped 0…1, 0 with none; level slew "rise ≤ 4·dt, fall ≤ 1·dt"; `phase += dt · speed · (1 + reactivity · level)`; `reset()`) in `Packages/Compositor/Sources/ProceduralMaterials/MaterialMotion.swift`
- [ ] SHD-001-T06 [P] GPU test rig (device skip, picture texture, render one layer frame directly, half-float read-back, 17 flash-area levels) in `Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialGPURig.swift`

## Phase 3: User Story 1 - Built-in materials ready to use (P1) MVP

**Goal**: every material lists with documented defaults and loads into a valid first frame.
**Independent test**: `MaterialCatalogTests` and `MaterialRenderTests.testEveryMaterialLoadsAtDefaults`.

- [ ] SHD-001-T07 [P] [US1] Catalog tests: 5 materials in order, IDs `material.<name>` unique and well formed, parameter IDs prefixed by their material, registry validates (S2), defaults inside bounds, every material has `speed` and `audioReactivity`, ≤ 8 parameters, `material(withID:)` nil for unknown and look-alike IDs, `defaultValues` equals descriptor defaults, documented defaults match the data-model table, every speed bounded to |speed| ≤ 1, brightness and contrast ≤ 1 and color defaults inside 0…1 (R9) in `Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialCatalogTests.swift`
- [ ] SHD-001-T08 [US1] The shader constant `ProceduralMaterialShaders.source` (full-screen vertex `mat_fullscreen`, fragments `mat_gradient`, `mat_plasma`, `mat_noiseFlow`, `mat_tunnel`, `mat_starfield`; 144-byte uniforms; output clamped to 0…1, alpha 1, non-finite → 0) and `makeLibrary(device:)`, the module's only library compile, in `Packages/Compositor/Sources/ProceduralMaterials/ProceduralMaterialShaders.swift`
- [ ] SHD-001-T09 [US1] `ProceduralMaterialLayer` (CMP-001 `LayerSource`, fallback transparent, library compiled once per layer, pipeline for rgba16Float, `render` advances motion then one clear-and-draw with `setFragmentBytes`) and `ProceduralMaterialCatalog.makeLayer(_:)`, `init?(materialID:)` in `Packages/Compositor/Sources/ProceduralMaterials/ProceduralMaterialLayer.swift`
- [ ] SHD-001-T10 [US1] Render tests: every material prepares and draws a non-blank, finite, opaque, premultiplied-valid 64 × 64 frame at defaults (S1); also through the `Compositor` with outcome `.rendered`; 1 × 1 and 97 × 13 sizes draw; bands holding NaN, −1 and 5 still give a valid picture; deterministic: two layers over the same 120-frame sequence with bands are bit-identical (S4) in `Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialRenderTests.swift`
- [ ] SHD-001-T11 [US1] Golden signatures per material (64 × 64, frame 30 at 60 Hz, no music: mean and peak linear RGB and pixels (32,32), (8,8), (56,16), (16,56); tolerance 0.02) (S7) in `Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialRenderTests.swift`

## Phase 4: User Story 2 - Adjustable within safe bounds (P1)

**Goal**: parameters clamp, refuse bad values and never break the picture.
**Independent test**: `MaterialParameterValuesTests`, `MaterialRenderTests.testExtremesStayValid`.

- [ ] SHD-001-T12 [P] [US2] Values tests: defaults, clamping above/below, integer snapping, color clamping, non-finite / unknown / wrong-kind refused with the stored value kept, slot encoding in `Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialParameterValuesTests.swift`
- [ ] SHD-001-T13 [US2] Layer `set(_:for:)`, `update(from: ParameterStore)` (copies the store's values for this material's IDs) and a test that a changed value changes the next frame; extremes test: all minimums, all maximums, full music, 30 frames, every pixel finite and valid (S6) in `Packages/Compositor/Sources/ProceduralMaterials/ProceduralMaterialLayer.swift` and `Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialRenderTests.swift`

## Phase 5: User Story 3 - Materials never flash on their own (P1)

**Goal**: defaults stay inside the Reduce flashing envelope; extremes inside the always-on budget.
**Independent test**: `MaterialMotionTests`, `MaterialFlashSafetyTests`.

- [ ] SHD-001-T14 [P] [US3] Motion tests: phase accumulation, dt clamp and NaN, band level (NaN ignored, clamping, empty → 0), rise/fall slew limits, speed multiplier ≤ 2, reset in `Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialMotionTests.swift`
- [ ] SHD-001-T15 [US3] Flash tests: per material, 120 frames at 60 Hz at defaults (no music, and steady music at 0.6): every one of the 17 areas ≤ 2 transitions per window for luminance and redness under the Reduce flashing thresholds, and through the `Compositor` with Reduce flashing on the guard's gain stays 1 (S5); at extreme speeds with bands at full level: ≤ 6 transitions per window (S6); music changes motion only: with speed 0, frames drawn with bands at full level equal frames drawn without music (R10) in `Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialFlashSafetyTests.swift`

## Phase 6: User Story 4 - No external code (P1)

**Goal**: the acceptance's "no external code", enforced.
**Independent test**: `MaterialSourceSafetyTests`.

- [ ] SHD-001-T16 [P] [US4] Source scan of `Packages/Compositor/Sources/ProceduralMaterials/*.swift`: exactly one `makeLibrary(` whose source argument is `ProceduralMaterialShaders.source` (or `Self.source` inside that type), no `contentsOf`, `URL(`, `URLSession`, `Bundle`, `FileManager`, `makeDefaultLibrary`, `dlopen`, `dlsym`; the shader source contains no `#include` other than `<metal_stdlib>` in `Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialSourceSafetyTests.swift`
- [ ] SHD-001-T17 [US4] ADR for the shader-library and safety decision (constant source compiled at prepare; no external code; flash safety by bounds plus the composite guard; future `.metal` move; SHD-002/SHD-011 must keep the rule) at the next free number, plus its row in `docs/adr/README.md`

## Phase 7: Polish

- [ ] SHD-001-T18 Gates: `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `swift test --package-path Packages/Compositor` (host), the Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`), and `xcodebuild test -scheme Compositor` on a fresh iOS 27.2 simulator (deleted afterwards; PosterBoard reports counted); spec status and test counts recorded
- [ ] SHD-001-T19 {device} Per-material GPU frame cost at full screen on D1, D2 and D3 (median and 95th percentile over 600 frames at defaults), recorded in `docs/test-reports/performance.md` (S8; R16)

## Dependencies

- T01 → T02-T06 → stories. T03 needs T02. T08 → T09 → T10, T11, T13, T15.
- US2 (T12) and US3 (T14) CPU tests need only Phase 2; US4 (T16) needs T08-T09 to exist.
- T18 after all; T19 after integration, on devices.

## Parallel examples

- Phase 2: T02, T04, T05, T06 in different files.
- After T09: T07, T12, T14, T16 (CPU tests) beside T10/T11 (GPU tests).

## Implementation strategy

MVP = Phases 1-3 (catalog plus layers loading at defaults: the acceptance's first half). Then US4
(the acceptance's second half), US2, US3, polish. One commit per completed group.
