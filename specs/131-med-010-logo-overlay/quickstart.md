# Quickstart: MED-010 Logo Overlay

## Package checks (Mac host, < 1 min each)

```bash
swift test --package-path Packages/Compositor --filter 'Logo|PremultipliedLinear|ImageImport'
swift test --package-path Packages/SceneFormat --filter SceneLogo
swift test --package-path Packages/SceneArchive
swift test --package-path Packages/LibraryBackup
# Linux shape of the pure parts
swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL \
  -Xswiftc -DANALYSIS_NO_ACCELERATE --filter 'LogoPlacement|PremultipliedLinear'
```

Expected: S1-S2 (`LogoLayerTests`), placement S4, premultiplication.

## App checks (own simulator, iOS 27.2)

```bash
xcrun simctl create "MED10 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination "id=<udid>" \
  -derivedDataPath .autonomous/derived-data-med-010 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/PhotoLayerUITests \
  -only-testing:projectM-iOSUITests/LogoOverlayUITests
```

Expected: `LogoStoreTests` (S1, S5, S6), `LogoArchiveTests` (S3), `LogoOverlayUITests` (S7).

## Device (S8, `{device}`)

On D1: Settings → Logo → Choose from Photos, pick a transparent PNG; choose Photo visual; check
clean edges in each corner; repeat from Files.
