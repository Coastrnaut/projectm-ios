# Quickstart: validating MOD-002

Prerequisites: the Mac Studio toolchain (`python3 scripts/verify_environment.py` exits 0) or any
host with Swift 6 for the package tests.

## A. Binding model (any host, including Linux)

```bash
swift test --package-path Packages/ParameterGraph
```

Expected: every test passes in a few seconds. Covers MOD-002-S1 (band level drives a test opacity;
unbind restores the manual value), S2 (one fixture per refusal reason), S3 (exact endpoints, mix
modes clamped, envelope at one time constant within 1 %, identical repeated runs).

## B. App catalog compatibility and the bloom update (macOS host)

```bash
swift test --package-path Packages/VisualGenerators --filter 'VisualParameterBindingTests|BloomRenderTests'
```

Expected: every modulatable catalog parameter accepts a full-range band binding; manual-only ones
are refused; an intensity-only change leaves the bloom plan unchanged.

## C. Simulator: host-level test and the UI test (macOS)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,name=MOD2 iPhone 17' \
  -derivedDataPath .autonomous/derived-data-mod-002 CODE_SIGNING_ALLOWED=NO \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/AudioFeatureBindingUITests \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 > .build/scratch/mod002-app.log 2>&1
grep -E "Executed|error:|failed" .build/scratch/mod002-app.log
```

Expected: `AudioFeatureBindingAppTests` and the existing app tests pass (the known worktree failure
`PresetTests.testBundledIncludedScopeMatchesRelease1_0` aside); the UI test sees at least two
different effective glow intensities, then "unbound" with effective = manual, in under 30 s
(MOD-002-S4). Simulator results are not device evidence.

## D. Repository checks

```bash
python3 scripts/validate_docs.py && python3 scripts/check_compliance.py && python3 scripts/test_scripts.py
```

No device step: this row has no device-only behavior.
