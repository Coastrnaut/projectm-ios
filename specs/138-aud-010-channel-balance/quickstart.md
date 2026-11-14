# Quickstart: AUD-010 Channel Balance

## Host (no simulator)

```bash
swift test --package-path Packages/AudioCore --filter MonitorBalanceTests
swift test --package-path Packages/AudioCore -Xswiftc -DAUDIOCORE_NO_AVFAUDIO --filter MonitorBalanceTests
swift test --package-path Packages/CaptureKit --filter PlaybackBalanceTests
```

Expected: the law at −1, −0.5, 0, 0.5, 1; analysis PCM identical at −1/0/+1; heard channel levels
follow the law; a mid-play change causes no discard.

## Simulator ("AUD10 iPhone 17", iOS 27.2)

`xcodegen generate`, then `build-for-testing` and `test-without-building` with
`-only-testing:projectM-iOSTests/PlaybackBalanceSettingTests` and
`-only-testing:projectM-iOSUITests/PlaybackBalanceUITests`.

Expected: persistence, detent, text and availability tests pass; the UI test finds Balance enabled
under In-App Playback, moves it, and resets it with Center.

## Device `{device}`

Play a stereo track on headphones and AirPods: full left silences the right ear; an interruption and
a route change keep the balance; the visuals do not change with the balance.
