# Quickstart: MED-005 Video Reverse Playback

## Package (Mac host; the pure tests also run in the Linux shape)

```bash
swift test --package-path Packages/Compositor --filter 'VideoReverse'
```

Expect: `VideoReverseTests` (plan limits and budget for each device class, selection order and
wrap, region, builder decimation and peak, cancel) and `VideoReverseLayerTests` (12-picture fixture
read back 11…0 then 11 through the real compositor; an over-limit clip and a corrupt clip report
their reason and forward continues).

## App (iOS 27.2 simulator)

```bash
xcodegen generate
xcodebuild build-for-testing -scheme projectM-iOS -destination 'platform=iOS Simulator,name=MED5 iPhone 17' ...
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/VideoReverseAppTests \
  -only-testing:projectM-iOSTests/SettingsTests -only-testing:projectM-iOSTests/LibraryBackupAppTests \
  -only-testing:projectM-iOSUITests/VideoReverseUITests
```

Expect: storage, coordinator and message tests pass; the UI test turns Reverse on for the seeded
counter clip and the `videoReverse` probe reports `playing` with the shown picture index going down.

## Device (`{device}`)

On D1 and D3, import a 30 s 1080p clip, turn Reverse on: it plays backwards after preparation,
memory stays within the device class budget (Xcode memory gauge), and a 2-minute clip shows the
30-second message while it keeps playing forward.
