# Tasks: SHD-006 Noise Editor

**Input**: Design documents from `specs/245-shd-006-noise-editor/`
**Tests**: requested by the spec (acceptance is test-proven: GPU determinism, exact digests, goldens, UI test).

## Phase 1: Setup

- [X] SHD-006-T01 Create simulator "SHD6 iPhone 17" (iOS 27.2), run `xcodegen generate`, confirm `Build` symlink and preset submodules in the worktree — Verified 2026-11-14: simulator SHD6 iPhone 17 (iOS 27.2) created, xcodegen generate, Build symlink present, preset submodules initialised

## Phase 2: Foundational (blocks all stories)

- [X] SHD-006-T02 ADR: material parameter cap 8 → 16 in `docs/adr/`; `ShaderMetadataReader.maximumParameters`, its error text, `MaterialDefinition.maximumParameterCount`, `MatUniforms`/`MaterialUniforms` 16 slots (272 bytes); validator test refuses 17 — Verified 2026-11-14: ADR-0064; `ShaderMetadataValidatorTests.testListMistakes` (16 pass, 17 refused); ProceduralMaterialsTests 64 pass on the host GPU (all other materials' goldens unchanged)
- [X] SHD-006-T03 Noise Flow metadata: `octaves` 1…8, new `seed`, `lacunarity`, `gain`, `warpAmount`, `warpFrequency` (slots 6-10) in `MaterialParameterMetadata.swift`; catalog and metadata tests updated (parameter counts, data-model table) — Verified 2026-11-14: `MaterialCatalogTests` (34 parameters, data-model table), `MaterialMetadataTests` (slot check of both variants), `MaterialParameterValuesTests` (octaves clamp to 8)

## Phase 3: User Story 2 - A fixed seed gives a stable reference texture (P1) 🎯 acceptance

**Goal**: deterministic seeded noise on GPU and CPU. **Independent test**: `MaterialNoiseTests`, `NoiseTextureReferenceTests`.

- [X] SHD-006-T04 [US2] Shader: `mat_nhash`, `mat_snoise`, `mat_sfbm` (contract N2) and `mat_noiseFlow` / `mat_noiseFlowLite` reading slots 6-10 in `ProceduralMaterialShaders.swift`; Noise Flow golden re-recorded in `MaterialRenderTests` — Verified 2026-11-14: Noise Flow and Low cost goldens re-recorded and passing (`MaterialRenderTests.testGoldenSignatures`, `MaterialVariantSwitchTests.testEachVariantMatchesItsGolden`); `MaterialFlashSafetyTests` and `testExtremesStayValid` pass
- [X] SHD-006-T05 [P] [US2] `NoiseTextureReference.swift` (settings from values, hash, noise, fBm, warp, Low cost) and `NoiseSeedSequence`; `NoiseTextureReferenceTests` (hash exact values, seeds give distinct fields, warp 0 = unwarped, seed sequence deterministic and never repeats the current seed) — Verified 2026-11-14: `NoiseTextureReferenceTests` 7 tests pass in 0.17 s on the host and in the Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`)
- [X] SHD-006-T06 [US2] `MaterialNoiseTests` (GPU): two renders byte-identical; FNV-1a digest per GPU class for three settings (host and simulator recorded); tolerant golden signatures; two seeds differ in ≥ 25 % of pixels; GPU vs CPU reference within 2/255 at sample pixels; extremes valid — Verified 2026-11-14: `MaterialNoiseTests` 7 tests pass on the host GPU ("Apple M5 Max", `swift test`) and on the iOS 27.2 simulator ("Apple iOS simulator GPU", `xcodebuild test -scheme Compositor`), each a separate process matching the stored FNV-1a digests of three settings; renders twice byte-identical; seeds 1 and 2 differ; GPU vs CPU within 2/255; goldens ±0.02

## Phase 4: User Story 3 - Each control does what it says (P2)

- [X] SHD-006-T07 [US3] Monotonic tests: CPU reference high-frequency energy strictly increases with octaves 1/2/4/8, lacunarity 1.5/2.5/3.5, gain 0.3/0.5/0.7; warp distance with warp 0/1/2/4; warp frequency changes the field; GPU octaves energy increases (in `NoiseTextureReferenceTests` and `MaterialNoiseTests`) — Verified 2026-11-14: `NoiseTextureReferenceTests.testOctavesLacunarityAndGainAddFinerDetail`, `testWarpAmountAndFrequency`, `MaterialNoiseTests.testMoreOctavesAddDetailOnTheGPU` pass

## Phase 5: User Story 1 - Shape a noise texture and see it (P1)

- [X] SHD-006-T08 [US1] `MaterialPreviewRenderer` (one still frame → `RGBA8Image`) in ProceduralMaterials (depends on FrameCapture); test in `MaterialNoiseTests` — Verified 2026-11-14: `MaterialNoiseTests.testPreviewIsTheSamePictureAsOpaqueSRGB` on the host GPU
- [X] SHD-006-T09 [US1] `NoiseEditorStore` (values, clamping, lenient load, save to `settings.noiseEditor.values`, randomize, reset) and the key in `ALLOWED_KEYS`, `LibrarySettingsPolicy.includedKeys`, the UI-test reset and `LibraryBackupAppTests` — Verified 2026-11-14: `NoiseEditorTests` (5) and `LibraryBackupAppTests`, `LibraryEraseAppTests` pass on SHD6 iPhone 17 (iOS 27.2); key added to `ALLOWED_KEYS`, `LibrarySettingsPolicy.includedKeys`, the UI-test reset and the backup test's app keys
- [X] SHD-006-T10 [US1] `NoiseEditorView.swift` (link section, preview image, Randomize seed, Reset, generic metadata controls write-enabled) and the link in `SettingsView.mediaSections` — Verified 2026-11-14: app builds for testing with the type-check flags (no long-body or long-expression warnings in the touched files); `NoiseEditorUITests` opens the screen; generic steppers gained an adjustable action (VoiceOver swipe)
- [X] SHD-006-T11 [P] [US1] App unit tests `Apps/projectM-iOS/Tests/NoiseEditorTests.swift`: persistence round trip, damaged data, clamping, randomize sequence, preview image size — Verified 2026-11-14: `NoiseEditorTests` 5 tests pass in 0.17 s on SHD6 iPhone 17; `MaterialInspectorTests` updated (34 controls, octaves clamp 8) and pass
- [X] SHD-006-T12 [US1] UI test `Apps/projectM-iOS/UITests/NoiseEditorUITests.swift`: open the editor, Randomize seed changes the seed, drag Lacunarity and read it back (under 30 s; XCUITest on iOS has no stepper increment for a combined element) — Verified 2026-11-14: `NoiseEditorUITests.testRandomizeSeedAndDragLacunarity` passed in 26.6 s on SHD6 iPhone 17 (Randomize seed changes the previewed seed; Lacunarity drag reads back > 2.5)

## Phase 6: Polish

- [ ] SHD-006-T13 Linux shape (Compositor `-DCOMPOSITOR_NO_METAL`), package suites (Compositor incl. MaterialFlashSafetyTests, SceneFormat), iOS simulator run of ProceduralMaterialsTests, type-check budget, repo checks, privacy manifest and network symbols on the Debug app; spec status
- [ ] SHD-006-T14 {device} Look at the Noise editor preview on D1 (seed, octaves, warp)

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1 → T03; R2 → T04-T05; R3 → T06; R4 → T07; R5 → T02-T03; R6 → T08, T10, T12; R7 → T09, T11; R8 → T03,
T13. S1 → T06, T13 (simulator digest); S2 → T06; S3 → T07; S4 → T12; S5 → T13. Fixes applied: T13 also runs the
SceneFormat suite (scenes storing Noise Flow values keep loading, R8) and the material flash-safety tests (new
octave range at extremes); T06 records the simulator's digest in the same table. No constitution conflicts; no
unmapped tasks.
