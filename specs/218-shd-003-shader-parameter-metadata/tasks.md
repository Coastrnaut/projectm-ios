# Tasks: SHD-003 Shader Parameter Metadata

**Input**: Design documents from `specs/218-shd-003-shader-parameter-metadata/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/shader-parameter-metadata.md

Tests are requested by the spec (S1-S6). Paths are relative to the repository root.

## Phase 1: Setup

- [ ] SHD-003-T01 Add target `ShaderParameterMetadata` (depends on ParameterGraph) and test target `ShaderParameterMetadataTests` to `Packages/Compositor/Package.swift`; make `ProceduralMaterials` depend on it and add it to the library product

## Phase 2: Foundational (metadata reader and validator)

- [ ] SHD-003-T02 [P] Typed errors with path text (contract M1 list) in `Packages/Compositor/Sources/ShaderParameterMetadata/ShaderMetadataError.swift`
- [ ] SHD-003-T03 Strict JSON value and reader (unknown keys, missing keys, keys not allowed for a kind, wrong types, `schema` exactly 1) in `Packages/Compositor/Sources/ShaderParameterMetadata/ShaderMetadataDocument.swift`
- [ ] SHD-003-T04 Validator per data-model.md ("1-64 characters" labels, "1-8 parameter objects", "min < max", "step > 0 and ≤ max − min", default in range and on step, "2-16" enum cases with unique IDs, colors "4 numbers in 0…1", slot equals position, required `speed`/`audioReactivity` when asked) producing `ValidatedShaderMetadata` in `Packages/Compositor/Sources/ShaderParameterMetadata/ShaderMetadataValidator.swift`
- [ ] SHD-003-T05 [P] Shader slot scanner and check (undeclared read, vector read on non-color, component read on color) in `Packages/Compositor/Sources/ShaderParameterMetadata/ShaderSlotUsage.swift`

## Phase 3: User Story 1 — checked data per variant (P1) 🎯 MVP

**Independent test**: five bundled documents validate; each invalid class fails with its own error.

- [ ] SHD-003-T06 [P] [US1] Parser/validator tests: valid document; at least 12 invalid classes each with its error case and a message naming parameter and key, in `Packages/Compositor/Tests/ShaderParameterMetadataTests/ShaderMetadataValidatorTests.swift`
- [ ] SHD-003-T07 [P] [US1] Slot scanner tests (reads, swizzles, missing function, mismatches) in `Packages/Compositor/Tests/ShaderParameterMetadataTests/ShaderSlotUsageTests.swift`
- [ ] SHD-003-T08 [US1] Five material documents (SHD-001 values, plus Gradient `shape` enum slot 5) in `Packages/Compositor/Sources/ProceduralMaterials/MaterialParameterMetadata.swift`
- [ ] SHD-003-T09 [US1] Gradient Shape in the shader (`linear` unchanged; `radial` per research D4) in `Packages/Compositor/Sources/ProceduralMaterials/ProceduralMaterialShaders.swift`; slot check of every document against the source in a test `Packages/Compositor/Tests/ProceduralMaterialsTests/MaterialMetadataTests.swift`

## Phase 4: User Story 2 — registered in the catalog (P1)

**Independent test**: registry of 29 parameters validates with SHD-001 values plus Shape.

- [ ] SHD-003-T10 [US2] Descriptor mapping (R5) in `Packages/Compositor/Sources/ShaderParameterMetadata/ShaderMetadataDescriptors.swift`
- [ ] SHD-003-T11 [US2] Build `ProceduralMaterialCatalog.materials` from validated metadata in `Packages/Compositor/Sources/ProceduralMaterials/ProceduralMaterialCatalog.swift`; slot check in `ProceduralMaterialLayer.prepare`
- [ ] SHD-003-T12 [US2] Update `MaterialCatalogTests.swift` (29 parameters, Shape documented, enum allowed) and `MaterialRenderTests.swift` (extremes with enums; GPU golden for Radial; Linear golden unchanged) in `Packages/Compositor/Tests/ProceduralMaterialsTests/`

## Phase 5: User Story 3 — inspector builds controls (P1)

**Independent test**: control list equals metadata; app shows the generated controls.

- [ ] SHD-003-T13 [US3] Generic control builder (R7) in `Packages/Compositor/Sources/ShaderParameterMetadata/ShaderParameterControls.swift` with tests in `Packages/Compositor/Tests/ShaderParameterMetadataTests/ShaderParameterControlsTests.swift`
- [ ] SHD-003-T14 [US3] App model: material layer → controls with display and spoken text (UIX-003 formatter) in `Apps/projectM-iOS/Coordinators/MaterialInspectorModel.swift`
- [ ] SHD-003-T15 [US3] Generic SwiftUI section (slider, stepper, picker, toggle, color well; disabled when read-only; identifiers `materialControl.<id>`) in `Apps/projectM-iOS/Views/MaterialParametersSection.swift`, one line in `Apps/projectM-iOS/Views/LayerDetailView.swift`
- [ ] SHD-003-T16 [US3] App unit test: for every material the control list equals the metadata (kinds, labels, ranges, steps, options, order) and accessibility values are the spoken text, in `Apps/projectM-iOS/Tests/MaterialInspectorTests.swift`
- [ ] SHD-003-T17 [US3] UI test on "SHD3 iPhone 17": seeded Plasma layer shows its five generated controls, disabled, in `Apps/projectM-iOS/UITests/MaterialInspectorUITests.swift`

## Phase 6: Polish

- [ ] SHD-003-T18 Linux shape build of Compositor (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) and type-check budget check of new app files
- [ ] SHD-003-T19 Repo checks (compliance, docs, motion, permission catalog, status events, script tests); LibraryBackupAppTests key test; spec status
- [ ] SHD-003-T20 {device} On D1, open the seeded material layer and read the Material settings controls with VoiceOver

## Dependencies

T01 → T02-T05 → US1 (T06-T09) → US2 (T10-T12) → US3 (T13-T17) → T18-T19. T20 after merge.

## Parallel examples

T02 and T05; T06 and T07; T14 and T13's tests once T13's API exists.

## Implementation strategy

MVP = US1 + US2 (validated data drives the catalog); then US3 delivers the acceptance in the app.
