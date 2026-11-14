# Quickstart: SHD-004 Shader Variant Switching

1. Metadata and catalog (CPU): `swift test --package-path Packages/Compositor --filter 'ShaderVariant|MaterialVariant|MaterialMetadata|MaterialCatalog'`
   — every document validates with the expected variants; each invalid class fails with its own error.
2. GPU (host): `swift test --package-path Packages/Compositor --filter MaterialVariantSwitchTests` and
   `--filter MaterialRenderTests` — goldens per variant, switching keeps values and motion, injected
   capability without family 9 falls back to Standard with the notice.
3. Scene: `swift test --package-path Packages/SceneFormat --filter SceneMaterialVariantTests` — byte-equal
   apart from `materialVariant`; round trip through live state; `unknownMaterialVariant` warning.
4. Linux shape: `swift build --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE` builds; CPU tests pass.
5. App (simulator "SHD4 iPhone 17"): `MaterialInspectorTests` (variant options) and the UI test
   `MaterialInspectorUITests` (picker shown for the seeded Plasma layer, disabled).
6. `{device}` D2 and D3: RendererLab/automation not required; run the GPU test bundle on device is not
   possible, so on D3 (family 8) confirm in a Debug build that a Plasma layer with Detailed reports the
   unsupported notice and draws Standard, and on D2 that Detailed draws.
