# Quickstart: validating VIS-001 Circular Spectrum

Run from the repository root (or the feature worktree). Simulator: iOS 27.2 "iPhone Air",
`77E17861-E687-4274-8A84-14224F32BE3E` on the build Mac; CI picks its own.

## 1. Package tests (host, any OS)

```bash
swift test --package-path Packages/VisualGenerators   # geometry matrix, limiter, buffer, band feed, render (macOS GPU)
swift test --package-path Packages/AudioCore           # tap capacity on AudioAnalyzer
swift test --package-path Packages/CaptureKit          # CaptureManager.analysisTap
```

Expected: all pass; on macOS the render test runs on the host GPU; on Linux the Metal file and its
test compile out. The geometry test prints the acceptance matrix (bar count, band, size, offset:
expected angle, measured angle).

## 2. Package tests on the simulator

```bash
cd Packages/VisualGenerators && xcodebuild test -scheme VisualGenerators \
  -destination 'id=<udid>' -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO > ../../.build/scratch/vg-sim.log 2>&1
grep -E ": error: |Executed [0-9]+ tests|\*\* TEST|skipped" ../../.build/scratch/vg-sim.log
```

Expected: `** TEST SUCCEEDED **`; the render test runs on the simulator's Metal device (host GPU) or
is reported skipped with a message when the simulator has none (CI).

## 3. App

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'id=<udid>' \
  -derivedDataPath .build/dd -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO -only-testing:projectM-iOSTests \
  -only-testing:projectM-iOSUITests/NativeVisualUITests -only-testing:projectM-iOSUITests/VisualizerUITests \
  -only-testing:projectM-iOSUITests/SettingsUITests -only-testing:projectM-iOSUITests/StatusUITests
```

Expected: all pass except the known environmental `PresetTests.testBundledIncludedScopeMatchesRelease1_0`
(needs the full preset library). `NativeVisualUITests` covers: default projectM; choosing Circular
Spectrum; persistence across relaunch; rotation to landscape and back with one source start;
switching back to projectM; the forced-failure notice (`-uitestNativeVisualFailure`).

## 4. Manual look (simulator)

Launch with `-autostart inAppPlayback` (DEBUG), open Settings → Visual → Circular Spectrum, then
`xcrun simctl io <udid> screenshot .build/scratch/vis-001-circular-spectrum.png`. A simulator
screenshot is not evidence of device behavior (Constitution X).

## 5. Device GPU `{device}` (final phase only)

On D1, D2, D3: choose Circular Spectrum with the reference track, rotate, lock/unlock, background
and return, toggle Reduce flashing; record frame rate from the performance overlay. Not run in this
row.
