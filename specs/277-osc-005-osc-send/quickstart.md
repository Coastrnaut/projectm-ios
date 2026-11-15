# Quickstart: OSC-005 OSC Send

1. Package: `swift test --package-path Packages/PerformanceControl --filter 'OSCSend'` — encoder round trip and properties, destination rules, rate cap, beat gate, sender disable; real UDP loopback on the macOS host (`OSCSendLoopbackTests`).
2. App (simulator "OSC5 iPhone 17", iOS 27.2): `xcodegen generate`, `build-for-testing`, then `test-without-building -only-testing:projectM-iOSTests/OSCSendCoordinatorTests -only-testing:projectM-iOSUITests/OSCSendUITests` (see contracts/osc-send.md S3).
3. Repo checks: `check_compliance`, `validate_docs`, `check_permission_catalog`, `check_status_events`, `test_scripts`; `check_network_symbols.py` on the Debug app.
4. `{device}` D1 on Wi-Fi with a Mac on the same network running an OSC monitor (e.g. `oscdump 9001` or Protokol) on port 9001: turn on OSC receiver, Settings › OSC › Send OSC, enter the Mac's 192.168.x.y and 9001, turn on Send OSC and Beats; tap a tempo; start In-App Playback, apply a show cue. Expected: `/projectm/status started`, `/projectm/scene`, `/projectm/beat n` once per beat; turning Send OSC off stops all traffic in the monitor.
