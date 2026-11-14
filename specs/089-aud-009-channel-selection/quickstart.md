# Quickstart: AUD-009 Channel Selection

1. Packages (host, then the Linux shapes):
   - `swift test --package-path Packages/AudioCore --filter ChannelSelection`
   - `swift test --package-path Packages/AudioCore -Xswiftc -DAUDIOCORE_NO_AVFAUDIO --filter ChannelSelection`
   - `swift test --package-path Packages/VisualGenerators --filter ChannelSelectionBand`
   - `swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter ChannelSelectionBand`
   Expected: the left-only fixture gives Mix −6.02, Left 0, Right silent, Mid −3.01, Side −3.01 dB.
2. App: `xcodegen generate`, then `xcodebuild test` on "AUD9 iPhone 17" (iOS 27.2) with
   `-only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/ChannelSelectionUITests` (and
   the neighbouring Settings, InputTrim and NativeVisual UI suites).
3. Scripts: `check_compliance.py`, `validate_docs.py`, `test_scripts.py` (the allowed-key check),
   `check_privacy_manifest.py <Debug .app>`.
4. `{device}`: on D1, with a stereo-panned track in In-App Playback, Left/Right visibly follow each
   side; routes and interruptions with a mode set behave as with Mix.
