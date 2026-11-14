# Quickstart: ANL-010 Spectral Centroid

All checks run on the Mac Studio; no device needed (synthetic PCM is the evidence).

1. Package tests (host, then the Linux shape):

   ```bash
   swift test --package-path Packages/AnalysisFeatures --filter SpectralCentroidTests
   swift test --package-path Packages/AnalysisFeatures -Xswiftc -DANALYSIS_NO_ACCELERATE
   swift test --package-path Packages/ParameterGraph
   ```

   Expected: the tone ladder 100…6,400 Hz reads strictly increasing centroids within 1 % (prints a
   table), noise ≈ 11 kHz within 5 %, two tones Σa²f/Σa², silence 0 with no signal, held values
   after a tone; `audio.centroid` round-trips and compiles to opcode 15.

2. Dependants: build and test VisualGenerators, PerformanceControl, Compositor, SceneFormat,
   RenderGoldens and ShowControl (`swift test --package-path Packages/<name>`).

3. App unit tests on a private simulator:

   ```bash
   xcrun simctl create "ANL10 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
   xcodegen generate
   xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
     -destination "platform=iOS Simulator,id=<udid>" -only-testing:projectM-iOSTests \
     -derivedDataPath .autonomous/derived-data-anl-010 CODE_SIGNING_ALLOWED=NO \
     -test-timeouts-enabled YES -default-test-execution-time-allowance 180
   xcrun simctl delete <udid>
   ```

   Expected: `AudioFeatureBindingAppTests.testCentroidBindsAndDrivesTheGlow` passes with the rest.

4. Repository checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
   `check_permission_catalog.py`, `test_scripts.py`.
