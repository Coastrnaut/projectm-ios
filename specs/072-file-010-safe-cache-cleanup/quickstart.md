# Quickstart: FILE-010 Safe Cache Cleanup

## Package (host; the injected-file-system tests are the Linux shape)

```bash
swift test --package-path Packages/LocalPortability --filter CacheCleanupTests
```

Expect: every test passes in about 1-2 s or less.

## App unit and UI tests (own simulator)

```bash
xcrun simctl create "FILE10 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=<udid>" \
  -derivedDataPath .autonomous/derived-data-file-010 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/CacheCleanupUITests \
  -only-testing:projectM-iOSUITests/StorageUsageUITests -only-testing:projectM-iOSUITests/SettingsUITests
```

Expect: `CacheCleanupAcceptanceTests` (FILE-010-S1, S2) and `CacheCleanupUITests` (S4) pass.

## By hand (simulator or device)

1. Launch with `-uitestStorageFixture`, open Settings › Storage.
2. Tap Clear Caches…: the alert states the size and what is kept. Cancel: sizes unchanged.
3. Tap Clear Caches… › Clear: Recordings, Shares and exports and Caches show Zero KB; the others keep
   their values.

## Device (`{device}`, D1)

After a session with several preset switches (shader cache) and a shared recording, Clear Caches frees
the Caches size shown, the app still plays, and the current scene and show load after relaunch.
