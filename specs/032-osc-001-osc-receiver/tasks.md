# Tasks: OSC-001 OSC Receiver

**Input**: `specs/032-osc-001-osc-receiver/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: test-first. No wall-clock assertions: expectations with generous ceilings. Each unit test
runs in about a second or less on the host, the package suite in under a minute, the UI test in
under 30 s (owner rule 7). Logs go to `.build/scratch/`. Device-only checks are tagged `{device}`
and are not run by this row.

Format: `- [ ] OSC-001-Tnn [P?] [Story?] description`. A task is ticked only when verified, with
" — Verified 2026-11-13: <how>".

## Phase 1: Setup

- [ ] OSC-001-T01 Record the baseline before any change: `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `swift test --package-path Packages/PerformanceControl`; note results here.
- [ ] OSC-001-T02 Add the `ParameterGraph` dependency (`.package(path: "../ParameterGraph")`) to the `PerformanceControl` target and the test target in `Packages/PerformanceControl/Package.swift`; update its header comment (OSC rows, the `OSCTransport/` folder rule).

## Phase 2: Foundational — decoder, scope, catalog, dispatcher (tests first)

- [ ] OSC-001-T03 [P] [US4] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCDecoderTests.swift`: round trip of float and int messages (C1.3); each rejection reason of OSC-001-R9 — "more than 1,472 bytes" → `oversized`, empty, length not a multiple of 4, unterminated address, non-zero padding, address not starting with `/`, address over 255 bytes or with bytes outside 0x21-0x7E, missing `,`, more than 16 arguments, unsupported tag (`s`), truncated argument, trailing bytes, `#bundle` → `bundleUnsupported`; a zero-argument message; a fixed-seed SplitMix64 fuzz of 20,000 packets (random, mutated, truncated) with no crash and every accepted packet re-encoding to the same bytes (C1.4), asserting no timing.
- [ ] OSC-001-T04 [P] [US4] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCPeerAddressTests.swift`: local = 127.0.0.1, 10.1.2.3, 172.16.0.1, 172.31.255.255, 192.168.1.20, 169.254.3.4, `::1`, `fe80::1`, `fd12::1`, `::ffff:192.168.1.2`; not local = 8.8.8.8, 172.32.0.1, 100.64.0.1, 2001:db8::1, `::ffff:8.8.8.8`, a 15-byte IPv6. Also `OSCPort.parse`: "9000" → 9000, " 1024 " → 1024, "65535" → 65535; "80", "1023", "65536", "", "9a", "-1", "99999999999999999999" → nil. And `OSCPeerTable` (OSC-001-R5): admitting a ninth peer evicts the least recently admitted; re-admitting a known peer evicts nothing.
- [ ] OSC-001-T05 [P] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCDispatcherTests.swift`: catalog registry validates; `/projectm/test ,f 0.42` → applied 0.42 (Float precision); `,i 1` → 1; float 7 → 1 and −3 → 0 (clamped); NaN → `refusedByStore`, value unchanged; unknown address → `unknownAddress`; two arguments → `wrongArguments`; a route to a parameter whose policy has `allowsExternalControl: false` → `notExternallyControllable`, value unchanged; malformed → `rejected` and counted by reason; counters add up.
- [ ] OSC-001-T06 Record the red run (T03-T05 fail to compile against missing symbols) in `.build/scratch/osc001-red.log`.
- [ ] OSC-001-T07 Implement `Sources/PerformanceControl/OSC/OSCMessage.swift`, `OSCDecoder.swift`, `OSCEncoder.swift` (research OSC-001-D3; limits 1,472 / 255 / 16); T03 passes.
- [ ] OSC-001-T08 Implement `Sources/PerformanceControl/OSC/OSCPeerAddress.swift` (with `OSCPeerTable`, capacity 8) and `OSCPort.swift` (range 1024-65535, default 9000); T04 passes.
- [ ] OSC-001-T09 Implement `Sources/PerformanceControl/OSC/OSCReceiverCatalog.swift` (`osc.receiver.testValue`, continuous 0…1 default 0, external control allowed, address `/projectm/test`) and `OSCDispatcher.swift` (policy check, counters in a `Mutex`); T05 passes.

## Phase 3: User Story 1 + 2 — listen, apply, disable (P1)

- [ ] OSC-001-T10 [P] [US1] [US2] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCReceiverTests.swift` with a fake transport (Linux-safe): off by default; start → `starting(p)`, ready → `listening(p)`; a datagram → test value changes; stop → `stopping` then `off` only after `cancelled`; a datagram after stop is not applied (fake delivers nothing; dispatcher counters unchanged); a stale `ready` from the cancelled generation does not change state; start while listening on another port cancels the old transport first; failure → `failed(p, .portInUse)` and no retry (fake records exactly one start); no transport → `failed(p, .unavailable)`; `stop()` from `off` is a no-op.
- [ ] OSC-001-T11 [US1] Implement `Sources/PerformanceControl/OSC/OSCDatagramTransport.swift` (protocol, `OSCTransportEvent`, `OSCListenerFailure`, `OSCReceiverState`) and `OSCReceiver.swift` (generation counter, `Mutex` state, handlers on the transport queue); T10 passes.
- [ ] OSC-001-T12 [US1] [US2] [US4] Implement `Sources/PerformanceControl/OSCTransport/NetworkDatagramTransport.swift` under `#if canImport(Network)`: UDP `NWListener` on the port (0 = any), `acceptLocalOnly = true`, `prohibitedInterfaceTypes = [.cellular]`, private serial queue, per-peer `NWConnection` checked with `OSCPeerAddress.isLocal` before any read, at most 8 peers through `OSCPeerTable` (evicted peer cancelled), datagrams over 1,472 bytes reported as `oversized` without copying, error mapping (EADDRINUSE → portInUse, DNS-SD −65570 → localNetworkDenied), `stop()` cancels the listener and every connection and reports `cancelled` once; `OSCReceiver.system()`.
- [ ] OSC-001-T13 [US1] [US2] Implement `Sources/PerformanceControl/OSCTransport/OSCLoopbackSender.swift` under `#if DEBUG && canImport(Network)`: internal, host fixed to 127.0.0.1, sends one datagram and calls back when sent (research OSC-001-D6).
- [ ] OSC-001-T14 [US1] [US2] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCLoopbackIntegrationTests.swift` (`#if canImport(Network)`; `XCTSkip` with the reason if the sandbox refuses loopback): start `OSCReceiver.system()` on port 0, wait for `listening(q)`, send `/projectm/test ,f 0.42` → test value 0.42 (expectation, 5 s ceiling); stop → `off`; send 0.9 → value stays 0.42 (inverted expectation, 0.5 s); a new receiver binds port q → `listening(q)`; stop. Every state handler and the test-value observer run off the main thread (OSC-001-R14).
- [ ] OSC-001-T15 Run the package suite on the macOS host; record count and per-test durations; check the fuzz test is under 1 s.

## Phase 4: User Story 1-3 in the app (P1/P2)

- [ ] OSC-001-T16 [US1] [US3] Extend `Apps/projectM-iOS/Coordinators/AppSettings.swift`: `oscEnabled` (`settings.osc.enabled`, absent → off) and `oscPort` (`settings.osc.port`, absent or outside 1024-65535 → 9000); add both keys to `allKeys` and the header; extend `Apps/projectM-iOS/Tests/SettingsTests.swift` (defaults, persistence, invalid stored port → 9000).
- [ ] OSC-001-T17 [US1] [US2] [US3] Add `Apps/projectM-iOS/Coordinators/OSCReceiverCoordinator.swift` (main actor, `@Observable`): owns an `OSCReceiver`, listens iff enabled ∧ scene active, `setEnabled`, `submitPort` (refuses with "Use a port from 1024 to 65535.", keeps the stored port), status texts ("Off", "Starting…", "Listening on port N", "Port N is in use. Choose another port.", "Local network access is off for projectM in Settings › Privacy & Security › Local Network.", "OSC isn't available on this device."), test value hopped to the main actor; write `Apps/projectM-iOS/Tests/OSCReceiverCoordinatorTests.swift` with a fake transport (off by default, enable starts, scene inactive stops, port change restarts, invalid port refused, status texts).
- [ ] OSC-001-T18 [US1] Wire it: `AppCoordinator` owns `osc` (built from `settings`), forwards `sceneBecame(active:)`; `VisualizerView` passes it to `SettingsView`.
- [ ] OSC-001-T19 [US1] [US5] Add the "OSC receiver" section to `Apps/projectM-iOS/Views/SettingsView.swift`: toggle `oscReceiverToggle`, port field `oscPortField` (number pad, applied on submit or focus loss), `oscPortError`, status `oscStatus`, test value `oscTestValue` ("Test value 0.42"), footer explaining local network only and foreground only; accessibility labels and values.
- [ ] OSC-001-T20 [US1] Add `NSLocalNetworkUsageDescription` to the app's `info.properties` in `project.yml` ("When you turn on OSC receiver in Settings, projectM listens on your local network for OSC control messages. It never connects to the internet."); no `NSBonjourServices`.
- [ ] OSC-001-T21 [US1] [US2] [US3] Write `Apps/projectM-iOS/UITests/OSCReceiverUITests.swift` (< 30 s; `-uitestDiagnostics -autostart inAppPlayback`, `Self.noStore`, `-settings.osc.enabled NO`, `-settings.osc.port 47123`): open Settings, scroll to the toggle with held drags, toggle reads off, turn on → status "Listening on port 47123", enter 80 → `oscPortError` shown and port stays 47123, turn off → "Off". The launch argument fixes the start state; the fresh-install default (OSC-001-S4) is proved by T16's unit test of empty defaults.
- [ ] OSC-001-T22 Run `projectM-iOSTests` (OSC coordinator, settings) and the UI test on a private iOS 27.2 simulator; record counts and durations; count PosterBoard reports before and after.

## Phase 5: Privacy, compliance and polish

- [ ] OSC-001-T23 Update `docs/privacy-policy.md` (new "OSC control on your local network" section, Permissions, What is stored, No analytics/network wording, FR-063 coverage row) and `docs/release/app-privacy.md` (OSC-001 reasoning: "Data Not Collected" stays; owner confirms in App Store Connect).
- [ ] OSC-001-T24 Run `python3 scripts/check_compliance.py` (Network framework only in `OSCTransport/`), `python3 scripts/validate_docs.py`, `python3 scripts/test_scripts.py`; `swift build -c release --package-path Packages/PerformanceControl` and confirm with `nm` that no `OSCLoopbackSender` symbol is in the release objects (OSC-001-S5).
- [ ] OSC-001-T25 Check OSC-001-R7: `rg` shows `OSCReceiverCatalog`/`osc.receiver` used only by PerformanceControl and the OSC coordinator and Settings, and `osc.receiver.testValue` is not in `VisualParameterCatalog`. Write `docs/test-reports/osc-receiver.md` (what was verified, counts, durations, what is pending) and update the roadmap row status in `docs/FEATURE_ROADMAP_AUTONOMOUS.md` only if other rows record status there.
- [ ] OSC-001-T26 `{device}` On D1 on Wi-Fi, a controller on another computer sends `/projectm/test ,f 0.42` to port 9000 → "Test value 0.42"; Local Network permission prompt appears on first enable; turning OSC off stops changes (quickstart D; OSC-001-S7). Owner, last stage.

## Dependencies

- T01-T02 → T03-T05 (parallel) → T06 → T07-T09 → T10-T11 → T12-T14 → T15.
- T16-T21 need T11 (and T12 for the real transport). T22 after T16-T21. T23-T25 last. T26 after
  the feature is integrated, by the owner.

## Parallel examples

- T03, T04, T05 (different test files).
- T19 and T20 after T17.

## Implementation strategy

MVP = Phases 1-3 (the acceptance criterion proved on the host over loopback). Phase 4 makes it
reachable in the app; Phase 5 is required before it ships (privacy policy, compliance).
