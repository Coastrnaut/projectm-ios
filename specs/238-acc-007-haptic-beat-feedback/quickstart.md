# Quickstart: ACC-007 Haptic Beat Feedback

1. `swift test --package-path Packages/PerformanceControl --filter HapticPulseGateTests` (gate, mapping).
2. App unit tests: `-only-testing:projectM-iOSTests/HapticBeatAcceptanceTests` and `LibraryBackupAppTests`.
3. UI test: `-only-testing:projectM-iOSUITests/HapticBeatUITests`.
4. Device (D1, `{device}`): play music with In-App Playback, Settings → Haptics → Haptic beat pulses on, Beats;
   feel taps on the beat; switch to Kicks and Downbeats; Strict profile → no taps; Low Power Mode → no taps;
   switch off → no taps.
