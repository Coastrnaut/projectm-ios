# Quickstart: ACC-009 One-Handed Performance Mode

1. `swift test --package-path Packages/ShowControl --filter OneHandedLayoutTests` (phone-size table, sets, pad stability).
2. App unit tests: `-only-testing:projectM-iOSTests/OneHandedAppTests` and `LibraryBackupAppTests`.
3. UI tests on "ACC9 iPhone 17" and the small iPhone: `-only-testing:projectM-iOSUITests/OneHandedUITests`.
4. QA-009: `-only-testing:projectM-iOSUITests/PrimaryScreensAccessibilityUITests/testOneHandedControlsStandard` and `…AX5`.
5. Device (D1, `{device}`): Settings → One-handed layout → Right hand; hold the phone in the right hand and reach every critical action with the thumb in portrait and landscape, with and without the performance pad; repeat with Left hand.
