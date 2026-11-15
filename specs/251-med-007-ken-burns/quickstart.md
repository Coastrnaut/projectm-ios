# Quickstart: MED-007 validation

1. `swift test --package-path Packages/Compositor --filter KenBurns` — the model (exact ends, monotonic edges,
   validation, presets) and, with Metal, the GPU read-back acceptance (`KenBurnsLayerTests`: start frame equals the
   CPU crop of the start rectangle within 1/255; the end frame equals the zoomed end rectangle; Reduce Motion;
   caching while moving and holding).
2. Linux shape: `swift build --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`.
3. `swift test --package-path Packages/SceneFormat --filter KenBurns` — the scene field round trip.
4. App: build-for-testing on "MED7 iPhone 17", then `test-without-building -only-testing:projectM-iOSTests/KenBurnsAppTests`
   (store, scene capture/restore, slideshow dwell, Reduce Motion on the layer), `LibraryBackupAppTests`, `SettingsTests`.
5. UI: `-only-testing:projectM-iOSUITests/KenBurnsUITests` — Settings › Photo, Ken Burns on, Zoom out chosen.
6. Repo checks from AGENT_RULES.md.
7. `{device}` on D1: a photo with Zoom in over 10 s looks smooth; a slideshow restarts the movement at every slide.
