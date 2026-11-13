# Quickstart: OSC-002 OSC Message Parser

## A. Host (macOS) and Linux

```bash
swift test --package-path Packages/PerformanceControl --filter 'OSC'
swift test --package-path Packages/PerformanceControl
```

Expected: every OSC decoder, packet decoder, dispatcher, receiver and loopback test passes; the
fuzz test (`testStructureAwareFuzz…`) runs in about 1 s or less; the whole suite in under 1 minute.

## B. Simulator (once)

```bash
cd Packages/PerformanceControl
xcodebuild test -scheme PerformanceControl -destination id=<udid> CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180
```

## C. Repository checks

```bash
python3 scripts/check_compliance.py
python3 scripts/validate_docs.py
```

## D. Manual, optional (device LAN)

Covered by OSC-001's open `{device}` task: a controller on the same Wi-Fi sending a bundle that
holds `/projectm/test 0.42` changes the test value in Settings. Not required for this row.
