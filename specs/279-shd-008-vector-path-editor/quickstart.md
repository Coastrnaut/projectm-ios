# Quickstart: SHD-008 Vector Path Editor

1. Pure: `swift test --package-path Packages/VisualGenerators --filter VectorPath` — validation families,
   draft editing, emitter spawns inside a concave path over a seeded 10 s run.
2. Scene: `swift test --package-path Packages/SceneFormat --filter ScenePathMask` — round trip bytes,
   invalid path dropped with a warning.
3. GPU: `swift test --package-path Packages/Compositor --filter LayerPathMask` — coverage counts.
4. App: build-for-testing on "SHD8 iPhone 17", run `VectorPathEditorTests` and
   `VectorPathEditorUITests` (draw a bow-tie → "crosses itself" message, Close disabled; start over, draw
   a triangle, Close → closed).
5. Device `{device}`: draw a path mask on D1 and look at the layer edge while rotating the device.
