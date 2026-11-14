# Tasks: SHD-004 Shader Variant Switching

**Input**: Design documents from `specs/231-shd-004-shader-variant-switching/`
**Tests**: requested by the spec (acceptance is test-proven: validator, GPU goldens, scene round trip, UI).

## Phase 1: Setup

- [X] SHD-004-T01 Create simulator "SHD4 iPhone 17" (iOS 27.2), run `xcodegen generate`, confirm `Build` symlink and preset submodules in the worktree — Verified 2026-11-14: simulator SHD4 iPhone 17 created, xcodegen generate, Build symlink and preset submodules present

## Phase 2: Foundational (blocks all stories)

- [X] SHD-004-T02 Add `ShaderGPUFamily` (`apple7`, `apple8`, `apple9`) and `ShaderVariantSpec` in `Packages/Compositor/Sources/ShaderParameterMetadata/ShaderVariantMetadata.swift`; read the optional `variants` key ("2–4 entries", "starts with the document's `variant`", "`variants[0].id` = `variant`", "label 1–64 characters", "`requires` not allowed on `variants[0]`") in `ShaderMetadataValidator.swift`; new errors in `ShaderMetadataError.swift` — Verified 2026-11-14: `swift test --filter ShaderVariantMetadataTests|ShaderMetadataValidatorTests` (9 tests pass)

## Phase 3: User Story 1 - Alternative precompiled implementations (P1) 🎯 MVP

**Goal**: materials declare variants; checks reject bad lists. **Independent test**: validator and catalog tests.

- [X] SHD-004-T03 [P] [US1] Validator tests, one per invalid class (count, duplicate, default mismatch, prefix, unknown family, default requirement, unknown key) in `Packages/Compositor/Tests/ShaderParameterMetadataTests/ShaderVariantMetadataTests.swift` — Verified 2026-11-14: `ShaderVariantMetadataTests` 3 tests pass, 9 invalid classes each with its own error
- [ ] SHD-004-T04 [US1] Variant lists for Plasma (`plasmaDetailed` "Detailed", requires `apple9`) and Noise Flow (`noiseFlowLite` "Low cost") in `MaterialParameterMetadata.swift`; `MaterialDefinition.variants`, `defaultVariant`, `variant(_:)`, `fragmentFunction(for:)` in `MaterialDefinition.swift`
- [ ] SHD-004-T05 [US1] Fragment functions `mat_plasmaDetailed` and `mat_noiseFlowLite` in `ProceduralMaterialShaders.swift` (SHD-001 safety rules, `mat_finish`)
- [ ] SHD-004-T06 [US1] Catalog tests: expected variants per material; every variant's `mat_<id>` passes SHD-003's slot check against `ProceduralMaterialShaders.source` (runs where Metal is available, as `MaterialMetadataTests` does) in `Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialVariantCatalogTests.swift`

## Phase 4: User Story 2 - Switching keeps the scene (P1)

**Goal**: runtime switch without rebuild. **Independent test**: GPU switch test, goldens per variant, scene round trip.

- [ ] SHD-004-T07 [US2] `MaterialGPUCapabilities`, `MaterialVariantNotice`, `MaterialVariantResolution.resolve` (plain Swift) in `Packages/Compositor/Sources/ProceduralMaterials/MaterialVariants.swift`; `MaterialGPUCapabilities(device:)` via `supportsFamily` in `ProceduralMaterialShaders.swift`
- [ ] SHD-004-T08 [US2] `ProceduralMaterialLayer`: `init(_:variant:capabilities:)`, `selectedVariant`, `select(variant:)`, pipeline cache built in `prepare`, `resolution`, render draws the resolved pipeline
- [ ] SHD-004-T09 [P] [US2] Resolution unit tests (CPU: default, supported, unsupported, unknown, pipeline unavailable — the spec's pipeline-failure edge case) in `ProceduralMaterialsTests/MaterialVariantResolutionTests.swift`
- [ ] SHD-004-T10 [US2] GPU tests: golden signature per non-default variant (differs from Standard), switching keeps every parameter value and the motion phase, switching back draws Standard again, no rebuild in `ProceduralMaterialsTests/MaterialVariantSwitchTests.swift`; flash-safety and extremes extended to the new variants
- [ ] SHD-004-T11 [US2] SceneFormat: `SceneLayer.materialVariant` (layer key `materialVariant`, written only when non-nil), decode (material only; non-text → `droppedField`), `SceneLiveState.materialVariants`, capture
- [ ] SHD-004-T12 [US2] Scene tests: byte-equal apart from `materialVariant`; default restores original bytes; decode → live state → capture round trip in `Packages/SceneFormat/Tests/SceneFormatTests/SceneMaterialVariantTests.swift`
- [ ] SHD-004-T13 [US2] RenderGoldens: `GoldenLayerFactory` draws the stored variant

## Phase 5: User Story 3 - Unsupported variant falls back (P1)

**Goal**: fallback with notice, choice kept. **Independent test**: injected capability GPU test, scene warning.

- [ ] SHD-004-T14 [US3] GPU test: capability without `apple9` + Detailed selected → Standard's picture (signature), notice `unsupported(plasmaDetailed, apple9)`, `selectedVariant` still Detailed; unknown variant → Standard with `unknownVariant` in `MaterialVariantSwitchTests.swift`
- [ ] SHD-004-T15 [US3] `SceneIssue.Code.unknownMaterialVariant` (warning; SCN-012 unknown content, no action) in `SceneIssue.swift`, `SceneRepair.swift`, `SceneValidation.swift`; test in `SceneMaterialVariantTests.swift`

## Phase 6: User Story 4 - Inspector picker (P2)

- [ ] SHD-004-T16 [US4] `MaterialInspectorModel.variants(for:)` / note; `LayerInspectorRow.materialVariant`; `MaterialVariantPicker` in `MaterialParametersSection.swift` (identifier `materialVariant`, disabled while not drawn; note `materialVariantNote`)
- [ ] SHD-004-T17 [US4] App unit test in `Apps/projectM-iOS/Tests/MaterialInspectorTests.swift` and UI test in `Apps/projectM-iOS/UITests/MaterialInspectorUITests.swift` (picker for the seeded Plasma layer, Standard, disabled; under 30 s)

## Phase 7: Polish

- [ ] SHD-004-T18 Linux shape build of Compositor and SceneFormat with the CI `-D*_NO_*` flags; type-check budget build of the app
- [ ] SHD-004-T19 `MaterialSourceSafetyTests` still pass (SHD-004-R9: one library, from the module constant); repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`), privacy manifest and network symbols on the Debug app; PosterBoard counts; delete simulator and derived data
- [ ] SHD-004-T20 {device} On D3 (iPad A16, family 8) a Plasma layer with Detailed reports the unsupported notice and draws Standard; on D2 (M5) Detailed draws (Debug build; GPU test bundle on device)

## Dependencies

T02 → US1 (T03-T06) → US2 (T07-T13) → US3 (T14-T15) → US4 (T16-T17) → T18-T19. T03, T09 parallel with their stories' implementation.

## Implementation strategy

MVP = US1 + US2 (switch keeps scene); US3 completes the acceptance; US4 surfaces it.
