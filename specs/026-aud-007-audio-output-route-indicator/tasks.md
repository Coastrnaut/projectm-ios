# Tasks: AUD-007 Audio output route indicator

**Input**: `specs/026-aud-007-audio-output-route-indicator/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: test-first (Constitution X). Every new test is short (owner rule 7: about 1-2 s each, a
package suite under 1 minute, the UI test under 30 s) and uses representative cases, never a
cross-product. Routes are injected; no wall-clock assertions; no main-actor mutation in
`setUp`/`tearDown`; SwiftUI types only inside `#if canImport(SwiftUI)`.

**Format**: `- [ ] AUD-007-Tnn [P?] [Story?] Description`. `{device}` = needs a physical device.

## Phase 1: Setup

- [ ] AUD-007-T01 Confirm the baseline before any change: `swift test` for `Packages/CaptureKit` and `Packages/CaptureUI` on the host, `python3 scripts/test_scripts.py`, `scripts/check_compliance.py`, `scripts/validate_docs.py`. Record the counts. Evidence: command output.

## Phase 2: Foundational (tests first)

- [ ] AUD-007-T02 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/AudioRouteTests.swift` (Foundation only, Linux): the port-type table of contracts/route-model.md (each raw string → kind, unknown output → `other`, unknown input → `otherInput`); reason raw values 0-4, 6-8 and an unknown value → `.unknown`; `pausesInAppPlayback` true only for `oldDeviceUnavailable`; change summaries for wired in, wired out, Bluetooth in and out, AirPlay, category change (nil), unchanged (nil), no outputs left, a lost port under a reason other than `oldDeviceUnavailable` (switched, not lost); `AudioRouteContext.make` over the context table. Evidence: red, then green in T06.
- [ ] AUD-007-T03 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/AudioRouteMonitorTests.swift` (Linux; a fake provider): `refresh()` reads the route without a change; `routeDidChange(reason:)` records previous and current, increases `sequence`, calls `onChange` once per change; a sequence speaker → headphones → speaker → AirPods → speaker produces the expected summaries. Evidence: red, then green in T07.
- [ ] AUD-007-T04 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/SystemAudioRouteTests.swift` (inside `#if os(iOS) && canImport(AVFAudio)`): every `AVAudioSession.Port` constant of contracts/route-model.md maps to its kind; every `AVAudioSession.RouteChangeReason` maps to the same raw value; `AudioSessionSignal.parse` gives `.outputRouteLost` exactly when `pausesInAppPlayback` (every reason); an `AudioRouteObserver` on a private center turns a posted route change into a monitor change with its reason; with an offline `AVInAppPlaybackBackend` started on the same private center, posting `oldDeviceUnavailable` both holds the backend (event `.outputRouteLost`, AUD-014-R14) and yields a `.lost` summary whose explanation context pauses. Evidence: red, then green in T08 (simulator).
- [ ] AUD-007-T05 Record the red run: `swift test --package-path Packages/CaptureKit --filter AudioRoute` fails to compile before T06-T08. Evidence: log excerpt in this task.

## Phase 3: User Story 1 + 2 - Show the route, explain a change (P1) 🎯 MVP

**Goal**: the indicator and the explanation for In-App Playback. **Independent test**: T02, T03, T09, T13.

- [ ] AUD-007-T06 [US1] Implement `Packages/CaptureKit/Sources/CaptureKit/Route/AudioRoute.swift` (data-model.md: `RoutePortKind`, `RoutePort`, `AudioRoute`, `AudioRouteChangeReason` with `pausesInAppPlayback`, `AudioRouteChange.summary`, `RouteChangeSummary`, `AudioRouteContext.make`). Evidence: T02 green on the host and with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`.
- [ ] AUD-007-T07 [US1] Implement `Packages/CaptureKit/Sources/CaptureKit/Route/AudioRouteMonitor.swift` (`AudioRouteProviding`, `AudioRouteMonitor`, @MainActor, @Observable). Evidence: T03 green, host and Linux mode.
- [ ] AUD-007-T08 [US2] Implement `Packages/CaptureKit/Sources/CaptureKit/Route/SystemAudioRoute.swift` (iOS: `SystemAudioRouteProvider`, `AudioRoute(AVAudioSessionRouteDescription)`, `AudioRouteObserver`) and make `AudioSessionSignal.parse` use `pausesInAppPlayback` (AUD-007-R9, behavior-identical). Evidence: T04 green on the iOS 27.2 simulator; full CaptureKit suite green (QA-007 `AudioSourceContractTests` included).
- [ ] AUD-007-T09 [P] [US2] Write `Packages/CaptureUI/Tests/CaptureUITests/RouteStringsTests.swift` (contracts/ui-strings.md): indicator text and VoiceOver label for speaker, named Bluetooth, two ports, none, empty names (generic); every explanation row (playing, held by the user, paused by unplug, microphone, none left); announcement nil exactly for the "— paused" row; the wording rule over every kind's generic name and every template (no mode label, no "capture", no output "from/receiving/listening"); a `ViewRenderTests`-style smoke render of `AudioRouteIndicator` inside `#if canImport(SwiftUI)`. Evidence: red, then green in T10.
- [ ] AUD-007-T10 [US2] Implement the route strings in `Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift` and the view `Packages/CaptureUI/Sources/CaptureUI/AudioRouteIndicator.swift` (identifier `routeIndicator`, label per contract, icon hidden from VoiceOver). Evidence: T09 green on the host and the simulator.
- [ ] AUD-007-T11 [US2] Write `Apps/projectM-iOS/Tests/RouteCoordinatorTests.swift`: with a fake provider and a recorded announcer, a wired-in change sets "Now playing through Headphones" and announces it; an unplug while playing sets "Headphones disconnected — paused" and announces nothing; a change with no context sets nothing; a category change sets nothing. Evidence: red, then green in T12.
- [ ] AUD-007-T12 [US1] Implement `Apps/projectM-iOS/Coordinators/RouteCoordinator.swift` (monitor, observer, explanation with a 4 s expiry, announcer) and wire it: `AppCoordinator.swift` (`routes`, `routeContext`), `ControlsOverlay.swift` (indicator next to the source indicator in both layouts, only with a context), `VisualizerView.swift` (explanation capsule `routeExplanation` above the source indicator; refresh when the active mode or state changes). Evidence: T11 green; app builds with no new warnings.
- [ ] AUD-007-T13 [US2] Add the Debug hook `Apps/projectM-iOS/Debug/UITestRoutePanel.swift` (`-uitestFakeRoutes`: fake provider at the built-in speaker; buttons `route:wiredIn`, `route:wiredOut`, `route:bluetoothIn`, `route:bluetoothOut` that set the fake route and post the real route-change notification with the reason) and write `Apps/projectM-iOS/UITests/RouteIndicatorUITests.swift` (one test, under 30 s, fast waits from `UITestWaits.swift`): In-App Playback (reference track) → "Audio output: Speaker" → wired in → "Audio output: Headphones" and "Now playing through Headphones" → wired out → "Audio output: Speaker", "Headphones disconnected — paused", source indicator ends in "Paused". Evidence: the UI test passes on the iOS 27.2 simulator; `StatusUITests` still pass.

## Phase 4: User Story 3 - Microphone input (P2)

- [ ] AUD-007-T14 [US3] Confirm Microphone mode through T02 (context), T09 (input strings) and T11-T12 wiring (input direction). Evidence: test names.

## Phase 5: Polish & cross-cutting

- [ ] AUD-007-T15 Run `scripts/check_compliance.py`, `scripts/test_scripts.py`, `scripts/validate_docs.py`; CaptureKit and CaptureUI on the host, in Linux mode (route filters) and on the iOS 27.2 simulator; report each new test's duration; count new PosterBoard reports. Evidence: command output.
- [ ] AUD-007-T16 {device} Device acceptance on D1 (quickstart "Device", steps 1-7): plug/unplug wired headphones and connect/disconnect Bluetooth headphones during In-App Playback; the indicator changes within 1 s with the explanation, AUD-014 pauses on unplug, no capture source is named; Microphone mode shows the headset input. Record in `docs/test-reports/route-indicator.md`. Evidence: the report.

## Dependencies

T01 → T02-T04 (parallel) → T05 → T06 → T07 → T08; T09 → T10 (needs T06); T11 → T12 (needs T07, T10); T13 needs T12; T14 after T12; T15 last on the Mac; T16 in the final device phase.

## Parallel example

T02, T03, T04 and T09 are separate test files and can be written together.

## Implementation strategy

MVP is Phase 3 (In-App Playback indicator and explanations); Microphone input (Phase 4) reuses the same code with the input direction. Device acceptance (T16) is deferred to the final device phase.
