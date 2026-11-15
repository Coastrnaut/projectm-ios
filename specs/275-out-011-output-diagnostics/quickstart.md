# Quickstart: OUT-011 Output Connection Diagnostics

## A. Automated (Mac, simulator "OUT11 iPhone 17")

1. `swift test --package-path Packages/PresentationLifecycle --filter OutputDiagnosticsTests`
2. App tests: `-only-testing:projectM-iOSTests/OutputDiagnosticsAppTests` — connect (values), disconnect
   (`.disconnected`, no old value in rows or probe), reconnect at 1280 × 720 (new values).
3. UI test: `-only-testing:projectM-iOSUITests/OutputDiagnosticsUITests` — connect the fake display, read the panel,
   disconnect, see "No external display connected".

## B. Device `{device}` (OUT-011-T12)

On D1 with a real HDMI display (Lightning/USB-C adapter): open Settings › Output Diagnostics, note the values
against the display's specification, unplug the cable while the panel is open: it must show "No external display
connected" at once; plug in again: fresh values. Record in `docs/test-reports/`.
