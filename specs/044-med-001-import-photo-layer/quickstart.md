# Quickstart: MED-001 Import Photo Layer

## Prerequisites

- The Mac Studio (Xcode 27.2), `python3 scripts/verify_environment.py` exit 0, the engine and ANGLE
  xcframeworks built (`SETUP.md`), `xcodegen generate`.
- A dedicated simulator: `xcrun simctl create "MED iPhone 17" "iPhone 17"
  com.apple.CoreSimulator.SimRuntime.iOS-27-2`.

## 1. Package (host, then Linux shape)

```bash
swift test --package-path Packages/Compositor --filter 'Image'
swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL \
  -Xswiftc -DANALYSIS_NO_ACCELERATE --filter 'ImageGeometry'
```

Expected: decode of a solid sRGB 188 fixture reads back linear 0.5029 ± 2/255 at 64 × 64; the
stored copy of a JPEG with GPS/EXIF has no `{GPS}`, `{Exif}`, `{TIFF}`, `{IPTC}`; oversized,
too-many-pixel, non-image and corrupt data throw their typed errors.

## 2. App unit and UI tests (simulator)

```bash
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath .autonomous/derived-data-med-001 \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/PhotoLayerUITests \
  -only-testing:projectM-iOSUITests/CameraUITests -only-testing:projectM-iOSUITests/SettingsUITests
```

Expected: PhotoStoreTests pass; PhotoLayerUITests seeds a fixture, shows "Photo 64 × 48", survives a
relaunch, and Remove Photo returns to "No photo". `PresetTests.testBundledIncludedScopeMatchesRelease1_0`
fails in a worktree without preset submodules (known).

## 3. Privacy checks

```bash
python3 scripts/check_compliance.py
python3 scripts/check_privacy_manifest.py .autonomous/derived-data-med-001/Build/Products/Debug-iphonesimulator/projectM-iOS.app
plutil -p .autonomous/derived-data-med-001/Build/Products/Debug-iphonesimulator/projectM-iOS.app/Info.plist | grep -c NSPhotoLibrary   # 0
```

## 4. Device (owner, `{device}`)

On D1 and D3: Settings › Photo › Choose from Photos… with full and with limited library access (no
permission prompt appears in either), Choose from Files… from On My iPhone and iCloud Drive, a HEIC
photo and a large panorama; relaunch; Remove Photo. Record in
`docs/test-reports/photo-layer.md`.
