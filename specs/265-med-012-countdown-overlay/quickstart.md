# Quickstart: MED-012 Countdown Overlay

1. `swift test --package-path Packages/Compositor --filter "Countdown"` — format, timer, layer redraws.
2. `swift test --package-path Packages/SceneFormat --filter SceneCountdownTests` — scene round trip.
3. App unit tests `-only-testing:projectM-iOSTests/CountdownOverlayTests` plus `SettingsTests` and
   `LibraryBackupAppTests` on the iOS 27.2 simulator.
4. UI test `-only-testing:projectM-iOSUITests/CountdownOverlayUITests` (fixed clock: Start shows "05:00").
5. Device `{device}`: Text visual, Show Countdown, 0:10, Start — it reaches "00:00" once and holds; a
   recording contains it.
