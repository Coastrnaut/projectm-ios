# Quickstart: SHOW-011 Tap Tempo checks

Run from the repository root on the Mac Studio. Budgets: owner rule 7.

## 1. Package tests (host, Linux shape)

```bash
swift test --package-path Packages/PerformanceControl
swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE
```

Expected: every test passes, each in about a second or less, the suite in under a minute.
Covers SHOW-011-S1 to S5.

## 2. Package tests on a simulator

```bash
cd Packages/PerformanceControl && xcodebuild test -scheme PerformanceControl \
  -destination 'id=<iOS 27.2 iPhone 17 UDID>' -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO > ../../.build/scratch/pc-sim.log 2>&1
grep -E "Executed|TEST (SUCCEEDED|FAILED)" ../../.build/scratch/pc-sim.log
```

## 3. App

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'id=<UDID>' \
  -only-testing:projectM-iOSTests/TempoCoordinatorTests -only-testing:projectM-iOSUITests/TapTempoUITests \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO \
  > .build/scratch/app.log 2>&1
```

Expected: the UI test taps Tap four times (synthetic 500 ms clock), reads "120 BPM, manual",
resets and reads a non-manual state, in under 30 s (SHOW-011-S6).

## 4. Device `{device}`

On D1, tap along with music and check the readout follows; reset with music playing shows
"Detected" once ANL-005 is confident. Not required for this row and not claimed.
