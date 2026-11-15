# Quickstart: SHD-007 Particle Emitter Editor

## Package (host, about a few seconds)

```bash
swift test --package-path Packages/VisualGenerators --filter 'ParticleEmitter'
swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL --filter 'ParticleEmitter'   # Linux shape
```

Expected: the 10 s seeded run spawns exactly ⌊rate·10⌋ at 60 Hz and jittery frames, ages at death within
[min, max + 1/60], no particle outside bounds, pool 512, seeds reproduce/differ; the render golden matches.

## App (iOS 27.2 simulator)

```bash
xcodebuild build-for-testing -scheme projectM-iOS -destination 'platform=iOS Simulator,name=SHD7 iPhone 17' ...
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/ParticleEmitterEditorTests \
  -only-testing:projectM-iOSTests/SettingsTests -only-testing:projectM-iOSTests/LibraryBackupAppTests \
  -only-testing:projectM-iOSUITests/ParticleEmitterEditorUITests
```

## Manual (device, `{device}`)

Settings › Particle emitter: turn on "Use on Particle Fountain", choose Circle, raise the rate to 120, set Box +
Bounce; pick the Particle Fountain visual and check the particles stay inside the box at a steady frame rate.
