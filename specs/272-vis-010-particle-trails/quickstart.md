# Quickstart: VIS-010 Particle Trails

1. `swift test --package-path Packages/VisualGenerators --filter ParticleTrail` — model, fixture, decay, cap, flash and GPU render tests.
2. `swift build --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL` — Linux shape.
3. RenderGoldens `ParticleTrailGolden` on the macOS host and the iOS Simulator.
4. App: `ParticleTrailAppTests`, `SettingsTests`, `LibraryBackupAppTests`, UI test `ParticleTrailUITests` on "VIS10 iPhone 17".
5. `{device}` D1: choose Particle Fountain, Trails Long, check the streaks and frame rate.
