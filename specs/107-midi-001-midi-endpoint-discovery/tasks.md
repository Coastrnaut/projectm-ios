# Tasks: MIDI-001 MIDI Endpoint Discovery

**Input**: `specs/107-midi-001-midi-endpoint-discovery/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MIDI-001-S1 to S7). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, UI test under 30 s. `{device}` tasks are the final device
stage and stay open until a person runs them.

## Phase 1: Setup

- [X] MIDI-001-T01 Run `xcodegen generate`, initialize the preset submodules if missing, create the simulator "MIDI1 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run (owner rule 5) — Verified 2026-11-14: `xcodegen generate`; preset submodules initialized; simulator 67EC99E8 "MIDI1 iPhone 17" created from the iOS 27.2 runtime; PosterBoard reports 25 before

## Phase 2: Foundational (blocks every story)

- [X] MIDI-001-T02 [P] Pure model in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIEndpoint.swift`: `MIDIEndpointDirection`, `MIDIEndpointTransport` (`local`, `bluetooth`, `network`), `MIDIEndpointRecord`, `MIDIEndpointID` (`unique(Int32)` | `fallback(hash:ordinal:)`, `isFallback`, `description` "midi:<n>" / "midi-fb:<16 hex>-<ordinal>"), `MIDIEndpoint` (name "MIDI input"/"MIDI output" when the display name is empty), `MIDIEndpointList` (drops `network`; order inputs, then outputs, by case-insensitive name, then ID description; `displayNames` " (2)", " (3)" per direction and name in list order) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl` (128 tests, 0 failures, 10.0 s of tests; MIDI tests 18, 0.02 s) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDI` (18 tests, 0 failures) (MIDIEndpointModelTests: order, network hidden, placeholders, display names)
- [X] MIDI-001-T03 [P] Stable-ID rule `MIDIEndpointIdentity.assign(_:)` and FNV-1a 64 over "direction|device|entity|endpoint" in `MIDI/MIDIEndpointIdentity.swift` (research MIDI-001-D2: a zero or shared system number moves every endpoint sharing it to the fallback; identical fallbacks get ordinals 0, 1, … in enumeration order) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl` (128 tests, 0 failures, 10.0 s of tests; MIDI tests 18, 0.02 s) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDI` (18 tests, 0 failures) (MIDIEndpointModelTests: system, zero, shared number, FNV-1a reference values)
- [X] MIDI-001-T04 [P] `MIDIEndpointChange` and `MIDIEndpointDiff.changes(from:to:)` in `MIDI/MIDIEndpointDiff.swift` (order: disappeared in old-list order, appeared, renamed, online changed in new-list order; appeared/disappeared exclude other changes) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl` (128 tests, 0 failures, 10.0 s of tests; MIDI tests 18, 0.02 s) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDI` (18 tests, 0 failures) (MIDIEndpointModelTests.testDiffTable, 7 rows)
- [X] MIDI-001-T05 [P] `MIDIRefreshCoalescer`, `MIDIRefreshScheduler` (`.serialQueue()`, utility QoS) and `ManualMIDIScheduler` in `MIDI/MIDIRefreshCoalescer.swift` — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl` (128 tests, 0 failures, 10.0 s of tests; MIDI tests 18, 0.02 s) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDI` (18 tests, 0 failures) (MIDIEndpointModelTests.testTenSignalsInOneBurstScheduleOneRefresh)
- [X] MIDI-001-T06 `MIDIEndpointProvider`, `MIDIProviderStartResult`, `MIDIDiscoveryState`, `MIDIDiscoveryUpdate`, `MIDIEndpointDiscovery` (contract C2: generations, initial refresh with `isInitial`, coalesced refreshes, stop clears) in `MIDI/MIDIEndpointDiscovery.swift`; `ScriptedMIDIEndpointProvider` (contract C1) in `MIDI/ScriptedMIDIEndpointProvider.swift` — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl` (128 tests, 0 failures, 10.0 s of tests; MIDI tests 18, 0.02 s) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDI` (18 tests, 0 failures) (MIDIEndpointDiscoveryTests 10/10)
- [X] MIDI-001-T07 Package tests `Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIEndpointModelTests.swift`: ID rule (system, zero, shared number, identical names distinct, deterministic hash), ordering and display names, diff table (appeared, disappeared, renamed, online, renamed+online, unchanged), coalescer (ten signals → one schedule) (MIDI-001-R3-R6, S2, S3, S5); host and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE` — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl` (128 tests, 0 failures, 10.0 s of tests; MIDI tests 18, 0.02 s) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDI` (18 tests, 0 failures)

## Phase 3: User Story 1 - I see my MIDI controller when I plug it in (P1) — MVP

**Independent test**: with the scripted provider, plug, unplug and replug: the list follows and IDs are stable.

- [X] MIDI-001-T08 [US1] Acceptance tests `MIDIEndpointDiscoveryTests.swift`: appear/disappear/replug with stable IDs (S1), two identical controllers distinct (S2), burst of ten signals → one refresh and one update (S3), offline/online keeps the ID (S4), stop clears and ignores a pending refresh, unavailable start, network endpoints hidden, updates delivered on the scheduler (never inline from the provider signal) (MIDI-001-R12) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl` (128 tests, 0 failures, 10.0 s of tests; MIDI tests 18, 0.02 s) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDI` (18 tests, 0 failures) (MIDIEndpointDiscoveryTests 10/10, each < 0.01 s)
- [X] MIDI-001-T09 [US1] `CoreMIDIEndpointProvider` (`#if canImport(CoreMIDI)`) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDISystem/CoreMIDIEndpointProvider.swift`: one `MIDIClientCreateWithBlock` client created on first start and kept; forwards setup/added/removed/property notifications only while started; reads unique ID, display name, name, offline, entity/device (none = virtual) and driver owner (RTP → `network`, Bluetooth → `bluetooth`); no ports, no network session, no Bluetooth UI; `MIDIEndpointDiscovery.system()` — Verified 2026-11-14: compiles on the macOS host with no warnings; CoreMIDIEndpointProviderSmokeTests (host read builds a well-formed list); iOS compile in the app build (T16); behaviour with hardware is the device task T18
- [ ] MIDI-001-T10 [US1] App: `AppSettings.midiEnabled` (`settings.midi.enabled`, default false, in the settings key list); `MIDIDiscoveryCoordinator` (contract C3) in `Apps/projectM-iOS/Coordinators/MIDIDiscoveryCoordinator.swift`; `AnnouncementKind.midi`; `AppCoordinator.midi` created with the system discovery (DEBUG: `UITestFakeMIDI.discoveryIfRequested()`), `sceneBecame(active:)` forwarded
- [ ] MIDI-001-T11 [US1] Settings: `Apps/projectM-iOS/Views/MIDISettingsSection.swift` (contract C4) mounted by one line in `SettingsView` (optional `midi`) and passed where Settings is created
- [ ] MIDI-001-T12 [US1] App unit tests `Apps/projectM-iOS/Tests/MIDIDiscoveryCoordinatorTests.swift`: off by default, runs only when enabled and active, background clears, status texts, row detail and label, announcement texts (one device with input and output counted once, several, both kinds, initial silent) (MIDI-001-R11), only the toggle key stored
- [ ] MIDI-001-T13 [US1] DEBUG `Apps/projectM-iOS/Debug/UITestFakeMIDI.swift` (`-uitestFakeMIDI`: scripted provider with the virtual output "Fake Synth"; Plug/Unplug Fake Keys buttons) and UI test `Apps/projectM-iOS/UITests/MIDIDiscoveryUITests.swift`: open Settings, toggle on, "Fake Synth" listed, Plug → "Fake Keys" Input and Output rows, Unplug → gone (S6, under 30 s)

## Phase 4: User Story 2 - I see music apps on the same device (P2)

- [ ] MIDI-001-T14 [US2] Virtual and rename coverage: discovery test for a virtual endpoint marked virtual and a rename keeping the ID (one `renamed` change); coordinator row detail "Output, Virtual" (in the T08/T12 files)

## Phase 5: User Story 3 - Nothing happens until I ask, and nothing leaves the device (P1)

- [ ] MIDI-001-T15 [US3] Guards: `scripts/check_compliance.py` rejects `MIDINetworkSession|MIDINetworkHost|MIDINetworkConnection|CABTMIDICentralViewController|CABTMIDILocalPeripheralViewController`; `scripts/check_network_symbols.py` rejects imported `MIDINetwork` symbols; `ALLOWED_KEYS` gains `settings.midi.enabled`; `check_status_events.py` `CHECKED` gains the two MIDI app files; rule tests in `scripts/test_scripts.py`
- [ ] MIDI-001-T16 [US3] Run the app's tests on the own simulator (projectM-iOSTests, OSCReceiverUITests, MIDIDiscoveryUITests), then `python3 scripts/check_network_symbols.py <built app>` and `python3 scripts/check_privacy_manifest.py` (S7); delete the simulator; count PosterBoard reports after

## Phase 6: Polish

- [ ] MIDI-001-T17 Run `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`; update the package note in `Packages/PerformanceControl/Package.swift`, the spec status and the roadmap row's status
- [ ] MIDI-001-T18 `{device}` On D1 or D2 with a class-compliant USB MIDI controller: listening on, plug → listed within 1 s as Input and Output, unplug → gone, replug → same rows; record the transport the system reports (S8)

## Dependencies

T01 → T02-T05 (parallel) → T06 → T07, T08, T09 → T10 → T11-T13 → T14 → T15 → T16 → T17; T18 after merge on a device.
US1 is the MVP; US2 and US3 add coverage and guards on the same code.

## Parallel examples

- T02, T03, T04, T05: separate files, no shared state.
- T09 (system provider) alongside T08 (tests against the scripted provider).
- T15 (scripts) alongside T11-T13 (app).
