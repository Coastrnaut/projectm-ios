# Quickstart: validating MOD-001

Prerequisites: the Mac Studio toolchain (`python3 scripts/verify_environment.py` exits 0) or any
host with Swift 6 for the package tests.

## A. Model and validation (any host, including Linux)

```bash
swift test --package-path Packages/ParameterGraph
```

Expected: every test passes in a few seconds. Covers MOD-001-S1 (duplicate IDs named with both
registrations), S2 (one fixture per malformed-descriptor kind), S4 (deterministic enumeration) and
S5 (clamping, rejection, round trips).

## B. App catalog and drift (any host)

```bash
swift test --package-path Packages/VisualGenerators --filter VisualParameterCatalogTests
```

Expected: the catalog validates; all 14 defaults are finite and in range; every range, default and
enum case equals the configuration types' values (MOD-001-S3, S4).

## C. App settings stay inside the catalog (macOS, simulator)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,name=MOD iPhone 17' \
  -only-testing:projectM-iOSTests/ParameterCatalogAppTests \
  -only-testing:projectM-iOSTests/SettingsTests \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 > .build/scratch/app-tests.log 2>&1
grep -E "Executed|error:|failed" .build/scratch/app-tests.log
```

Expected: both classes pass; `SettingsTests` unchanged (MOD-001-S6).

## D. Repository checks

```bash
python3 scripts/validate_docs.py && python3 scripts/check_compliance.py && python3 scripts/test_scripts.py
```

No device step: this row has no device-only behavior.
