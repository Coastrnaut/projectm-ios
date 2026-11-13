# Quickstart: SCN-002 Scene Autosave

## Prerequisites

`xcodegen generate`; the engine and ANGLE xcframeworks built; `git submodule update --init --depth 1
Vendor/presets/*`; a dedicated simulator (`xcrun simctl create "SCN2 iPhone 17" "iPhone 17"
com.apple.CoreSimulator.SimRuntime.iOS-27-2`).

## A. Package (any host)

```bash
swift test --package-path Packages/SceneFormat --filter SceneJSONTests
swift test --package-path Packages/SceneFormat -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter SceneJSONTests
```

Expected: the parse test passes (bounded parse, canonical round trip).

## B. App unit tests (simulator)

```bash
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'platform=iOS Simulator,id=<udid>' \
  -derivedDataPath .autonomous/derived-data-scn-002 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests > build/scn002-unit.log 2>&1
```

Expected: `SceneAutosaveStoreTests`, `SceneAutosaveDebouncerTests`, `SceneAutosaveCaptureTests`,
`SceneAutosaveCoordinatorTests` pass: debounce with a fake clock, injected failure before the rename
keeps the old file, truncated main → backup, both damaged → nothing and an event, crash leftovers,
capture → save → load → live state equal, unknown content kept.

## C. Kill and relaunch (simulator UI test, SCN-002-S1)

`-only-testing:projectM-iOSUITests/SceneAutosaveUITests`: Circular Spectrum, 16 bars, close Settings
(committed); reopen, 32 bars, kill before the commit; relaunch → 16 bars, `restored=main`.

## D. Device `{device}` (D1, owner)

Install a Debug build; choose Circular Spectrum, 16 bars, close Settings; reopen Settings, choose 32
bars and at once swipe the app away in the app switcher; relaunch: the bar count is one of the two
committed values (the app switcher passes through the background, which commits, so 32 is expected),
never the default 64, and the visual draws.
