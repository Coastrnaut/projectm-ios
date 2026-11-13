# Implementation Plan: FILE-012 No-Telemetry Verification

**Branch**: `feature/file-012` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

## Summary

Three layers of evidence that normal use makes no application-initiated network request, each honest
about its limits:

1. **Binary scan** (`scripts/check_network_symbols.py`): every Mach-O image in the built app, every
   architecture, `otool -L` for linked libraries and `nm -m -u` for imported symbols with their source
   library. Forbidden frameworks and symbols fail; Network-framework imports pass only in the image
   that defines the OSC transport and only against an API allowlist; StoreKit linkage is reported as
   allowed. Run in CI on the Debug generic-iOS app.
2. **Runtime observer** (`scripts/observe_app_network.py`): wraps an `xcodebuild test-without-building`
   command, samples `lsof -i` for every app process in the given simulator, streams the simulator's
   Network/CFNetwork log events for the app process, optionally sends one probe datagram to the OSC
   port, and classifies everything against `none` or `osc:<port>`.
3. **UI sessions** (`NoTelemetryUITests`): normal use with OSC off; a separate test that turns OSC on in
   Settings. Each test under 30 s.

Plus the report `docs/test-reports/no-telemetry.md` and a FILE-012 paragraph in
`docs/release/app-privacy.md`.

## Technical Context

**Language/Version**: Python 3 (standard library only) for scripts; Swift 6 (XCUITest) for UI tests.
**Primary Dependencies**: macOS command-line tools `nm`, `otool`, `lipo`, `xcrun swift-demangle`,
`lsof`, `ps`, `xcrun simctl spawn <udid> log stream`.
**Testing**: `scripts/test_scripts.py` (rule tests on any OS from recorded tool output; a macOS-only
positive control compiles a tiny C file calling `socket`/`connect` with `clang` and scans it);
XCUITest on an own iOS 27.2 simulator.
**Target Platform**: Mac host (scripts), iOS Simulator (observation), CI macOS job (scan).
**Constraints**: owner rule 7 (unit tests about 1-2 s, UI tests < 30 s); owner rule 8 (no Simulator
panel tool); no app behaviour change (FILE-012-R11).

## Constitution Check

- Public APIs only (I): no app code changes; scripts use developer tools on the Mac only. PASS.
- FR-068 / ADR-0008: the scan enforces the same policy on binaries; the Python observer sends one UDP
  datagram on the Mac's loopback in the OSC run. That is test harness code on the host, not app code,
  and `check_compliance.py` scans app and package sources only. PASS.
- Evidence (X): simulator observations are labelled as simulator results; the device check stays a
  `{device}` task. PASS.
- Signing: untouched. PASS.

## Research decisions

- **D1 — lsof sees simulator app sockets.** Simulator apps are Mac processes sharing the Mac's network
  stack. Verified 2026-11-13 on the FILE12 iPhone 17 simulator (iOS 27.2): the OSC listener appeared as
  `UDP *:47129` in `lsof -a -i -n -P -p <pid>`, and a datagram sent from the Mac produced
  `UDP 127.0.0.1:47129->127.0.0.1:55802`; with OSC off the same command listed nothing (exit 1).
- **D2 — the unified log records connections the sampler can miss.** `xcrun simctl spawn <udid> log
  stream --style ndjson --level debug --predicate 'process == "projectM-iOS" AND (subsystem BEGINSWITH
  "com.apple.network" OR subsystem BEGINSWITH "com.apple.CFNetwork")'` delivered `[L1]` listener and
  `[C1 … udp, server …]` connection events for the probe; with OSC off it delivered only launch
  bookkeeping: `nw_activity` events (category `activity`, app-launch duration reports) and
  `networkd_settings_read_from_file_locked`. These two are ignored; every other event counts.
- **D3 — packaging differs by configuration.** Debug: Swift packages are embedded frameworks
  (`PerformanceControl_…_PackageProduct.framework` links Network.framework), the app code is in
  `projectM-iOS.debug.dylib`. Release: packages are linked statically into `projectM-iOS`, which then
  links Network.framework itself. So the allowed image is found by content: the image that defines
  `NetworkDatagramTransport` symbols.
- **D4 — Network API allowlist.** Debug imports (demangled) include `NWConnection.__allocating_init(host:
  port:using:)` and `NWConnection.send(…)` from the DEBUG-only `OSCLoopbackSender`; the Release build
  has neither (verified with `nm` on the Release simulator build). The scan allows the outbound pair
  only in an image that also defines `OSCLoopbackSender` (DEBUG), and `--release` fails if any image
  defines it. Every other Network symbol must match a listener-side allowlist (NWListener, NWParameters,
  NWEndpoint, NWInterface, NWError, IPv4/IPv6Address, NWConnection receive/start/cancel/state/endpoint);
  any C-level `_nw_*` import fails.
- **D5 — vendored code.** ANGLE (`libEGL`, `libGLESv2`) and projectM (`projectM-4`) import no socket,
  resolver or URL symbols in the Debug simulator build (survey 2026-11-13); the scan keeps checking.
- **D6 — what the layers cannot see.** System daemons acting for the app (storekitd, crash reporting,
  push, App Store) run in other processes; Foundation APIs that accept a URL (`Data(contentsOf:)`,
  AVFoundation players) could reach the network with a remote URL without importing a networking
  symbol; raw sockets shorter than one sample in an image the scan passed are impossible (no socket
  imports). The report states these limits.

## Design

### `scripts/check_network_symbols.py`

```
python3 scripts/check_network_symbols.py <App.app> [--release] [--json <out>]
```

- `macho_images(app)`: every regular file in the bundle whose first 4 bytes are a Mach-O or fat magic.
- Per image and architecture (`lipo -archs`): `otool -L -arch <a>` → libraries; `nm -m -u -arch <a>`
  → (symbol, library); `nm -U -arch <a>` defined names to find `NetworkDatagramTransport` and
  `OSCLoopbackSender`. Network Swift symbols are demangled in one `xcrun swift-demangle --simplified`
  call.
- Pure functions (tested on any OS): `parse_otool_libraries`, `parse_nm_imports`, `classify_library`,
  `classify_import`, `network_api_name`, `evaluate_image` → findings `{image, arch, kind, name, rule,
  verdict}`; `summarize` → violations, allowed list.
- Exit 0 with a summary (`check_network_symbols: OK (<n> images, allowed: …)`), 1 with each violation.

### `scripts/observe_app_network.py`

```
python3 scripts/observe_app_network.py --udid <udid> --executable projectM-iOS \
    --expect none|osc:<port> [--probe] --report <out.json> [--interval 0.2] -- <command…>
```

- Starts the log stream (waits for its "Filtering the log data" line), a sampler thread (`ps -axo
  pid=,command=` → processes whose path is inside `Devices/<udid>/data/Containers/Bundle/Application/`
  and ends with `/<exe>.app/<exe>`; then `lsof -a -i -n -P -F pftPn -p <pids>`), and the command.
- `--probe` with `osc:<port>`: once a UDP listener on the port is seen, sends one datagram (an OSC
  message to `/file012/probe`, which no binding uses) from `127.0.0.1` and records its source port.
- After the command exits: stops the stream, classifies, writes the report, prints a summary, exits
  non-zero if the command failed, the observation failed (no app process seen, log stream never
  ready, probe not seen when requested) or anything unexpected was seen.
- Pure functions (tested on any OS): `parse_lsof_fields`, `app_pids_from_ps`, `classify_sockets`,
  `classify_log_events`, `evaluate`.

### UI tests: `Apps/projectM-iOS/UITests/NoTelemetryUITests.swift`

- `testNoticeChooserAndInAppPlayback`: fresh notice → acknowledge → In-App Playback → controls.
- `testVisualsWithSeededPhotoVideoAndText`: seeds photo, video, text; Settings rows Photo, Video, Text,
  Circular Spectrum, Linear Spectrum, projectM.
- `testSaveFrameAndShortRecording`: Photo visual, Save Frame → PNG (`-uitestCaptureDirectory`), Record
  about 2 s and stop (`-uitestRecordingDirectory`).
- `testShowCuesAndStorageCleanup`: `-uitestShowSeed`, steps cues; Settings › Storage › Clear Caches…
  (Clear when offered).
- `testUserEnabledOSCListensOnly` (run separately under `osc:47131`): OSC off → on in Settings →
  "Listening on port 47131" → holds about 3 s for the probe → off → "Off".

Two observer runs: the four normal-use tests under `--expect none`; the OSC test under
`--expect osc:47131 --probe`.

### CI

After "Build projectM-iOS (generic iOS, unsigned; T080)": `python3 scripts/check_network_symbols.py
"$RUNNER_TEMP/dd-app/Build/Products/Debug-iphoneos/projectM-iOS.app"`.

## Project Structure

```
scripts/check_network_symbols.py         new
scripts/observe_app_network.py           new
scripts/test_scripts.py                  + tests for both
Apps/projectM-iOS/UITests/NoTelemetryUITests.swift   new
.github/workflows/ios-ci.yml             + one step
docs/test-reports/no-telemetry.md        new
docs/release/app-privacy.md              + FILE-012 paragraph
specs/076-file-012-no-telemetry-verification/   spec, plan, tasks, quickstart
```

## Quickstart

```bash
python3 scripts/check_network_symbols.py <derived>/Build/Products/Debug-iphonesimulator/projectM-iOS.app
python3 scripts/check_network_symbols.py <derived>/Build/Products/Release-iphoneos/projectM-iOS.app --release
python3 scripts/observe_app_network.py --udid <udid> --executable projectM-iOS --expect none \
  --report <out>/none.json -- xcodebuild test-without-building … \
  -only-testing:projectM-iOSUITests/NoTelemetryUITests/testNoticeChooserAndInAppPlayback …
python3 scripts/observe_app_network.py --udid <udid> --executable projectM-iOS --expect osc:47131 \
  --probe --report <out>/osc.json -- xcodebuild test-without-building … \
  -only-testing:projectM-iOSUITests/NoTelemetryUITests/testUserEnabledOSCListensOnly
```

Device (`{device}` FILE-012-T11): on D1, Settings › Privacy & Security › App Privacy Report on, run the
quickstart's session by hand (OSC off), then read the app's "App Network Activity" (expected: none);
or, with a Mac proxy configured by the owner, the proxy's log for the session.
