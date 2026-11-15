# Quickstart: SHD-006 Noise Editor

1. `swift test --package-path Packages/Compositor --filter NoiseTextureReferenceTests` — CPU reference: hash, seeds, monotonic controls, seed sequence (also in the Linux shape with `-Xswiftc -DCOMPOSITOR_NO_METAL`).
2. `swift test --package-path Packages/Compositor --filter MaterialNoiseTests` — GPU: two renders bit-identical, exact digest for this GPU class, goldens, seeds differ, CPU vs GPU, octaves energy.
3. `swift test --package-path Packages/Compositor --filter "MaterialMetadataTests|MaterialCatalogTests|ShaderMetadataValidatorTests|MaterialRenderTests"` — metadata, cap, goldens.
4. App: Settings › Noise editor › step Octaves, tap Randomize seed; the preview redraws (`NoiseEditorUITests`).
