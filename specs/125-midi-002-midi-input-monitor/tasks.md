# Tasks: MIDI-002 MIDI Input Monitor

**Input**: `specs/125-midi-002-midi-input-monitor/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MIDI-002-S1 to S7). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, UI test under 30 s. `{device}` tasks are the final device
stage and stay open until a person runs them.

## Phase 1: Setup

- [X] MIDI-002-T01 Run `xcodegen generate`, initialize the preset submodules if missing, create the simulator "MIDI2 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run (owner rule 5) — Verified 2026-11-14: `xcodegen generate`; preset submodules initialized; simulator 7BE84A91 "MIDI2 iPhone 17" created from the iOS 27.2 runtime; PosterBoard reports 25 before

## Phase 2: Foundational (blocks every story)

- [X] MIDI-002-T02 [P] `MIDIEvent`, `MIDIEventKind` (noteOn, noteOff, polyPressure, controlChange, programChange, channelPressure, pitchBend, systemExclusive, timeCode, songPosition, songSelect, tuneRequest, clock, start, continue, stop, activeSensing, reset), `MIDIControlKey`, `normalizedValue` (value / 127 for 7-bit kinds, value / 16383 for pitch bend), `MIDIEventSink`, `MIDIEventCollector` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIEvent.swift` (data-model: "note on with velocity 0 is stored as `noteOff` with value 0"; no source field) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl --filter "MIDIMessageDecoding|MIDIEventRing"` (12 tests, 0 failures, 0.004 s) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE` (12 tests, 0 failures)
- [X] MIDI-002-T03 [P] `MIDIUMPDecoder` (types 0x1, 0x2, 0x3 SysEx7 length across packets; others skipped by word count) in `MIDI/MIDIUMPDecoder.swift` (research MIDI-002-D1) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl --filter "MIDIMessageDecoding|MIDIEventRing"` (12 tests, 0 failures, 0.004 s) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE` (12 tests, 0 failures)
- [X] MIDI-002-T04 [P] `MIDIByteStreamParser` (running status, interleaved real-time, system common cancels running status, SysEx length until F7 or next status, stray data ignored) in `MIDI/MIDIByteStreamParser.swift` (research MIDI-002-D2) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl --filter "MIDIMessageDecoding|MIDIEventRing"` (12 tests, 0 failures, 0.004 s) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE` (12 tests, 0 failures)
- [X] MIDI-002-T05 [P] `MIDIEventRing` (512 preallocated events, `Atomic` indices, drop newest counted, clock and active sensing counted not stored, `drain`, `discardAll`, `storageAddress` for tests) in `MIDI/MIDIEventRing.swift` (research MIDI-002-D3) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl --filter "MIDIMessageDecoding|MIDIEventRing"` (12 tests, 0 failures, 0.004 s) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE` (12 tests, 0 failures)
- [X] MIDI-002-T06 Package tests `Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIMessageDecodingTests.swift` and `MIDIEventRingTests.swift`: decoder tables (each type, 0/127, bend 0/8192/16383, note on velocity 0, running status, SysEx in one and several packets, real-time interleaved, stray data, unknown UMP types), control key and normalized value (R14), ring overflow and counters, fixed storage over 10,000 messages through decode-into-ring (MIDI-002-R3-R5, S3, S4); host and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE` — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl --filter "MIDIMessageDecoding|MIDIEventRing"` (12 tests, 0 failures, 0.004 s) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE` (12 tests, 0 failures)

## Phase 3: User Story 1 - I see what my controller sends (P1) — MVP

**Independent test**: inject a control change and a note through the scripted input; the monitor shows the expected texts.

- [X] MIDI-002-T07 [US1] `MIDIInputProvider`, `MIDIInputState`, `MIDIInputService` (idempotent start/stop, sources, unavailable) and `UnavailableMIDIInputProvider` in `MIDI/MIDIInputService.swift`; `ScriptedMIDIInputProvider` in `MIDI/ScriptedMIDIInputProvider.swift` (contract C3) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl` (148 tests, 0 failures, 13.8 s of tests; MIDI tests 38, 0.56 s; new: MIDIInputServiceTests 5, MIDIEventTextTests 3) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDI` (38 tests, 0 failures)
- [X] MIDI-002-T08 [P] [US1] `MIDIEventText` (type, "Ch n", number "CC 7" / "60 C4" / "Program 5", value, spoken label; middle C 60 = C4, sharps only) in `MIDI/MIDIEventText.swift` — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl` (148 tests, 0 failures, 13.8 s of tests; MIDI tests 38, 0.56 s; new: MIDIInputServiceTests 5, MIDIEventTextTests 3) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDI` (38 tests, 0 failures)
- [X] MIDI-002-T09 [US1] Package tests `MIDIInputServiceTests.swift` (lifecycle, connected sources, delivery only while open and connected, unavailable and the Linux `UnavailableMIDIInputProvider` (R11), stop discards) and `MIDIEventTextTests.swift` (every kind's texts) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl` (148 tests, 0 failures, 13.8 s of tests; MIDI tests 38, 0.56 s; new: MIDIInputServiceTests 5, MIDIEventTextTests 3) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDI` (38 tests, 0 failures)
- [X] MIDI-002-T10 [US1] `CoreMIDIInputProvider` (`#if canImport(CoreMIDI)`) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDISystem/CoreMIDIInputProvider.swift`: own client, `MIDIInputPortCreateWithProtocol(._1_0)`, connect exactly the requested IDs (MIDI-001 identity rule), `connRefCon` nil, in-place event-list walk, host time → ns, decode into the ring; `MIDIInputService.system()` — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl` (148 tests, 0 failures, 13.8 s of tests; MIDI tests 38, 0.56 s; new: MIDIInputServiceTests 5, MIDIEventTextTests 3) and the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDI` (38 tests, 0 failures); compiles on the macOS host with no warnings; `testSystemReceiveBlockWalksAnEventListInPlace` decodes a two-packet `MIDIEventList` built with `MIDIEventListInit/Add` through the receive block (host time → ns, closed → nothing); behaviour with hardware is the device task T20
- [ ] MIDI-002-T11 [US1] App `Apps/projectM-iOS/Coordinators/MIDIInputCoordinator.swift` (clients, receiving iff a client and discovery listening, sources from the list, CADisplayLink drain ≤ 30 Hz) and list observers in `MIDIDiscoveryCoordinator.swift`; `AppCoordinator.midiInput` (DEBUG: `UITestFakeMIDI.inputProvider` when `-uitestFakeMIDI`)
- [ ] MIDI-002-T12 [US1] `Apps/projectM-iOS/Coordinators/MIDIMonitorCoordinator.swift` (entries ≤ 64 newest first, time text "12.40 s", counters, status text) and `Apps/projectM-iOS/Views/MIDIMonitorView.swift`; a "MIDI Monitor" row in `Views/MIDISettingsSection.swift`
- [ ] MIDI-002-T13 [US1] App tests `Apps/projectM-iOS/Tests/MIDIMonitorCoordinatorTests.swift`: the acceptance (injected CC and notes render the expected texts, S1), 64 cap, receiving only while listening and open (R1), sources follow plug and unplug (R2), the "MIDI Monitor" row and the listening-off text (R15)
- [ ] MIDI-002-T14 [US1] DEBUG stand-in (`UITestFakeMIDI.inputProvider`, "Send CC" / "Send Note" on the monitor) and UI test `Apps/projectM-iOS/UITests/MIDIMonitorUITests.swift` (S6, under 30 s)

## Phase 4: User Story 2 - I can pause and clear while I check (P2)

- [ ] MIDI-002-T15 [US2] Pause/resume and clear in `MIDIMonitorCoordinator` and the view; tests in `MIDIMonitorCoordinatorTests.swift` (R9, S5)

## Phase 5: User Story 3 - Nothing about my devices is recorded (P1)

- [ ] MIDI-002-T16 [US3] Privacy scan test in `MIDIMonitorCoordinatorTests.swift` (research MIDI-002-D6: entries, dumps, counters, status, input state, UserDefaults, process log; S2); close and reopen is empty (R8)
- [ ] MIDI-002-T17 [US3] `scripts/check_status_events.py` `CHECKED` gains `Coordinators/MIDIMonitorCoordinator.swift`, `Coordinators/MIDIInputCoordinator.swift`, `Views/MIDIMonitorView.swift` (R10)
- [ ] MIDI-002-T18 [US3] Run the app's tests on the own simulator (projectM-iOSTests, MIDIDiscoveryUITests, MIDIMonitorUITests), then `check_network_symbols.py` and `check_privacy_manifest.py` on the built app (S7); type-check budget with `-warn-long-function-bodies=300`; delete the simulator; count PosterBoard reports after

## Phase 6: Polish

- [ ] MIDI-002-T19 Amend ADR-0038 (Decision 7: receiving), update the package note in `Packages/PerformanceControl/Package.swift` and the spec status; run `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`
- [ ] MIDI-002-T20 `{device}` On D1 or D2 with a class-compliant USB MIDI controller: monitor shows fader moves as control changes and keys as note on/off with the right numbers; closing stops receiving; reopen is empty (S8)

## Dependencies

T01 → T02-T05 (parallel) → T06 → T07, T08 → T09, T10 → T11 → T12 → T13, T14 → T15 → T16, T17 → T18 → T19; T20 after merge on a device.
US1 is the MVP; US2 and US3 add behaviour and proof on the same code.

## Parallel examples

- T02, T03, T04, T05: separate files.
- T08 (texts) alongside T07 (service).
- T17 (script) alongside T15-T16.

## Analysis (speckit-analyze, 2026-11-14)

Findings applied: R15 moved after R14 in the spec (numbering order); R14 (control key, normalized
value) added to T06; R11's unavailable provider added to T09; R15 (monitor row, listening-off text)
added to T13. No constitution conflict; every requirement R1-R15 and criterion S1-S8 has a task.

## Implementation strategy

Package core first (Linux-testable), then the app path with the scripted provider, then the UI test;
the system provider compiles in the app build and is exercised only on a device (T20).
