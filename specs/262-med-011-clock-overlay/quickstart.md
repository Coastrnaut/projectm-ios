# Quickstart: MED-011 Clock Overlay

1. Package: `swift test --package-path Packages/Compositor --filter 'Clock'` (formatter, DST, layer pixels, caching).
2. App unit tests: `-only-testing:projectM-iOSTests/ClockOverlayStoreTests`, `SettingsTests`, `LibraryBackupAppTests`.
3. UI test: `-only-testing:projectM-iOSUITests/ClockOverlayUITests` (fixed clock, Text visual, `clockProbe`).
4. Device `{device}` (D1, D3): Settings › Clock › Show Clock on, Text or Photo visual; the clock reads the status
   bar's time, changes at the minute, shows in a recording; 12-hour with seconds updates every second.
