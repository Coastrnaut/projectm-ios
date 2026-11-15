# Tasks: SHD-006 Noise Editor

**Input**: Design documents from `specs/245-shd-006-noise-editor/`
**Tests**: requested by the spec (acceptance is test-proven: GPU determinism, exact digests, goldens, UI test).

## Phase 1: Setup

- [ ] SHD-006-T01 Create simulator "SHD6 iPhone 17" (iOS 27.2), run `xcodegen generate`, confirm `Build` symlink and preset submodules in the worktree

## Phase 2: Foundational (blocks all stories)

- [ ] SHD-006-T02 ADR: material parameter cap 8 → 16 in `docs/adr/`; `ShaderMetadataReader.maximumParameters`, its error text, `MaterialDefinition.maximumParameterCount`, `MatUniforms`/`MaterialUniforms` 16 slots (272 bytes); validator test refuses 17
- [ ] SHD-006-T03 Noise Flow metadata: `octaves` 1…8, new `seed`, `lacunarity`, `gain`, `warpAmount`, `warpFrequency` (slots 6-10) in `MaterialParameterMetadata.swift`; catalog and metadata tests updated (parameter counts, data-model table)

## Phase 3: User Story 2 - A fixed seed gives a stable reference texture (P1) 🎯 acceptance

**Goal**: deterministic seeded noise on GPU and CPU. **Independent test**: `MaterialNoiseTests`, `NoiseTextureReferenceTests`.

- [ ] SHD-006-T04 [US2] Shader: `mat_nhash`, `mat_snoise`, `mat_sfbm` (contract N2) and `mat_noiseFlow` / `mat_noiseFlowLite` reading slots 6-10 in `ProceduralMaterialShaders.swift`; Noise Flow golden re-recorded in `MaterialRenderTests`
- [ ] SHD-006-T05 [P] [US2] `NoiseTextureReference.swift` (settings from values, hash, noise, fBm, warp, Low cost) and `NoiseSeedSequence`; `NoiseTextureReferenceTests` (hash exact values, seeds give distinct fields, warp 0 = unwarped, seed sequence deterministic and never repeats the current seed)
- [ ] SHD-006-T06 [US2] `MaterialNoiseTests` (GPU): two renders byte-identical; FNV-1a digest per GPU class for three settings (host and simulator recorded); tolerant golden signatures; two seeds differ in ≥ 25 % of pixels; GPU vs CPU reference within 2/255 at sample pixels; extremes valid

## Phase 4: User Story 3 - Each control does what it says (P2)

- [ ] SHD-006-T07 [US3] Monotonic tests: CPU reference high-frequency energy strictly increases with octaves 1/2/4/8, lacunarity 1.5/2.5/3.5, gain 0.3/0.5/0.7; warp distance with warp 0/1/2/4; warp frequency changes the field; GPU octaves energy increases (in `NoiseTextureReferenceTests` and `MaterialNoiseTests`)

## Phase 5: User Story 1 - Shape a noise texture and see it (P1)

- [ ] SHD-006-T08 [US1] `MaterialPreviewRenderer` (one still frame → `RGBA8Image`) in ProceduralMaterials (depends on FrameCapture); test in `MaterialNoiseTests`
- [ ] SHD-006-T09 [US1] `NoiseEditorStore` (values, clamping, lenient load, save to `settings.noiseEditor.values`, randomize, reset) and the key in `ALLOWED_KEYS`, `LibrarySettingsPolicy.includedKeys`, the UI-test reset and `LibraryBackupAppTests`
- [ ] SHD-006-T10 [US1] `NoiseEditorView.swift` (link section, preview image, Randomize seed, Reset, generic metadata controls write-enabled) and the link in `SettingsView.mediaSections`
- [ ] SHD-006-T11 [P] [US1] App unit tests `Apps/projectM-iOS/Tests/NoiseEditorTests.swift`: persistence round trip, damaged data, clamping, randomize sequence, preview image size
- [ ] SHD-006-T12 [US1] UI test `Apps/projectM-iOS/UITests/NoiseEditorUITests.swift`: open the editor, step Octaves to 4, Randomize seed changes the seed (under 30 s)

## Phase 6: Polish

- [ ] SHD-006-T13 Linux shape (Compositor `-DCOMPOSITOR_NO_METAL`), package suites, iOS simulator run of ProceduralMaterialsTests, type-check budget, repo checks, privacy manifest and network symbols on the Debug app; spec status
- [ ] SHD-006-T14 {device} Look at the Noise editor preview on D1 (seed, octaves, warp)
