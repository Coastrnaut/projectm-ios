# Quickstart: VIS-011 Fluid Ink

1. `swift test --package-path Packages/VisualGenerators --filter FluidInk` — solver stability, frame-rate equality,
   allocation, GPU stability and flash tests (about 5 s). `VIS011_LONG=1` adds the long sweeps.
2. `swift test --package-path Packages/RenderGoldens --filter FluidInkGolden` — the golden on the macOS host; the same
   test on "VIS11 iPhone 17" with `xcodebuild test`.
3. App: `FluidInkAppTests` and `FluidInkUITests` on "VIS11 iPhone 17" (iOS 27.2).
4. `{device}` D1: choose Fluid Ink with music; ink follows onsets, the frame rate holds, nothing flashes with Reduce
   flashing on.
