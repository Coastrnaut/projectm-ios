# Quickstart: validating FX-001 Bloom

Run from the repository root (or the feature worktree). Simulator: iOS 27.2 "iPhone Air",
`77E17861-E687-4274-8A84-14224F32BE3E` on the build Mac; CI picks its own.

## 1. Package tests (host)

```bash
swift test --package-path Packages/VisualGenerators                          # CPU + GPU (host Metal)
swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL # Linux shape on the Mac
```

Expected: all pass. With Metal: `BloomRenderTests` (black, bright patch halo, below threshold,
gradient, intensity 0, determinism, both pixel formats), `EffectChainRenderTests` (including the app format, `bgra8Unorm_srgb`) and
`BloomFlashSafetyRenderTests` (generator → bloom with Reduce flashing on, measured mean luminance)
run on the host GPU. Without Metal they compile out; the CPU tests (`BloomParametersTests`,
`BloomPlanTests`, `EffectChainDescriptionTests`, `BloomLuminanceModelTests`,
`FlashSafetyLimiterTests`) run everywhere.

## 2. Package tests on the simulator

```bash
cd Packages/VisualGenerators && xcodebuild test -scheme VisualGenerators \
  -destination 'id=<udid>' -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO > ../../.build/scratch/fx-sim.log 2>&1
grep -E ": error: |Executed [0-9]+ tests|\*\* TEST|skipped" ../../.build/scratch/fx-sim.log
```

Expected: `** TEST SUCCEEDED **`; GPU tests run on the simulator's Metal device or are reported
skipped (`XCTSkip`) where none exists (CI).

## 3. App

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'id=<udid>' \
  -derivedDataPath .build/dd -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO -only-testing:projectM-iOSTests \
  -only-testing:projectM-iOSUITests/GlowUITests -only-testing:projectM-iOSUITests/NativeVisualUITests \
  -only-testing:projectM-iOSUITests/SettingsUITests -only-testing:projectM-iOSUITests/VisualizerUITests
```

Expected: all pass except the known environmental `PresetTests.testBundledIncludedScopeMatchesRelease1_0`.
`GlowUITests`: Glow off by default, controls appear when on, values persist across relaunch with one
source start, forced failure (`-uitestGlowFailure`) keeps the circular spectrum with the notice.

## 4. Manual look (simulator)

Choose Circular Spectrum, turn Glow on, play the reference track, then
`xcrun simctl io <udid> screenshot .build/scratch/fx-001-bloom.png`. A simulator screenshot is not
evidence of device behavior (Constitution X).

## 5. Device GPU `{device}` (final phase only)

On D1, D2, D3 with the reference track: Glow on at default and at maximum radius; frame rate from
the performance overlay against Glow off; appearance after rotation; Reduce flashing on. Not run in
this row.
