# Quickstart: validating PERF-004 Texture Pool

## A. Package (Mac host; budgets: unit ≤ 10 s, suite < 1 min)

```bash
swift test --package-path Packages/Compositor --filter 'TexturePool'
swift test --package-path Packages/Compositor          # whole package, CMP tests unchanged
swift test --package-path Packages/Compositor --scratch-path .build/linuxshape \
  -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
```

Expected: `TexturePoolSwitchTests.testHundredSceneSwitchesKeepLiveTexturesBounded` passes and
prints the plateau (live textures and bytes, hits, misses); the core tests pass in both shapes.

## B. Simulator (once; own simulator, deleted afterwards)

```bash
xcrun simctl create "PERF4 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
cd Packages/Compositor && xcodebuild test -scheme Compositor -destination 'platform=iOS Simulator,id=<udid>' \
  -derivedDataPath ../../.autonomous/derived-data-perf-004 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'platform=iOS Simulator,id=<udid>' \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/CameraUITests \
  -only-testing:projectM-iOSUITests/PhotoLayerUITests -only-testing:projectM-iOSUITests/NativeVisualUITests \
  -derivedDataPath .autonomous/derived-data-perf-004 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180
```

Count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before and after (owner rule 5).

## C. Devices (owner, last stage; `{device}` tasks)

On D1 (iPhone 15, iOS 27) and D3 (iPad A16, iPadOS 26.5), Debug build from Xcode: switch Camera →
Photo → Spectrum → Camera and edit nothing else, 100 visual switches (25 cycles), with Xcode's
memory report or a Metal capture showing `MTLDevice.currentAllocatedSize`. Expected: GPU memory
plateaus after the first cycle (S6). Simulator numbers are never device evidence.
