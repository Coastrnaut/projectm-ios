# Quickstart: validating ANL-003

1. `swift test --package-path Packages/AnalysisFeatures --filter BandSmootherTests` (and again with
   `-Xswiftc -DANALYSIS_NO_ACCELERATE`): step crossings, independence, instant, resets
   (contract C1).
2. `swift test --package-path Packages/VisualGenerators --filter BandSmoothingPipelineTests` (and
   with `-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`): the tone on/off fixture
   through the real band path (spec User Story 2, scenario 5).
3. App, on the row's simulator "ANL3 iPhone 17" (iOS 27.2): `xcodegen generate`, then
   `xcodebuild test` with `-only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/NativeVisualUITests
   -only-testing:projectM-iOSUITests/OscilloscopeUITests -only-testing:projectM-iOSUITests/SpectralSmoothingUITests`,
   `CODE_SIGNING_ALLOWED=NO`, test time-outs on; output to a log file.
4. Manual look (optional): choose Circular Spectrum, Attack 25 ms, Release 500 ms; bars rise
   quickly and fall slowly. Instant/Instant looks as before.
5. Scripts: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
   `check_permission_catalog.py`, `test_scripts.py` (the allowed-keys test).
