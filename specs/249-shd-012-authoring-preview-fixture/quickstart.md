# Quickstart: SHD-012 Authoring Preview Fixture

1. Package tests (host GPU + trajectory):
   `swift test --package-path Packages/Compositor --filter AuthoringPreviewTests`
2. Linux shape: `swift build --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`
   and the same flags with `swift test --filter AuthoringPreviewTrajectoryTests`.
3. App: `xcodegen generate`, build-for-testing on the "SHD12 iPhone 17" simulator, then
   `-only-testing:projectM-iOSTests/FixturePreviewStoreTests` and
   `-only-testing:projectM-iOSUITests/FixturePreviewUITests`.
4. By hand (device, `{device}`): Settings › Noise editor › Play fixture; the loop plays, the warp jumps on each
   kick, Play again shows the same run digest.
