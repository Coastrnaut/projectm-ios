# Implementation Plan: MIDI-009 MIDI Feedback

**Branch**: `feature/midi-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/269-midi-009-midi-feedback/spec.md`

## Summary

A `cc:` mapping can opt in to feedback (`;fb=1`). While the shared MIDI input is receiving, every 30 Hz drain tick
reads the base value of each feedback mapping's parameter, converts it back to a 7- or 14-bit controller value (nearest
mapped value, research MIDI-009-D2), and a pure, clock-injected engine decides what to send: only changes, at most 30
per second per control (coalesced), at most 16 messages per tick round-robin, nothing for 100 ms after the controller
itself set the value, and incoming bytes that echo what was just sent are dropped (D3, D4). Messages go through an
output protocol; the real one is a CoreMIDI output port sending MIDI 1.0 Universal MIDI Packets to destinations paired
with the listened inputs (D5, D6). Same split as MIDI-001 to MIDI-013: pure logic in
`Packages/PerformanceControl/Sources/PerformanceControl/MIDI/`, CoreMIDI in `MIDISystem/`, a thin app layer.

Package (PerformanceControl):

- `MIDIMappingOptions.feedback` (`fb=1` segment after `hires=1`; summary ", feedback") (D1).
- New `MIDIFeedback.swift`: `MIDIFeedbackMessage`, `MIDIFeedbackQuantizer` (parameter value → controller value by a
  binary search over the forward mapping, D2), `MIDIFeedbackEngine` (rate limit, coalescing, per-tick cap, echo
  window, echo filter, resync and panic absorb, D3, D4) and `MIDIFeedbackRouting` (paired destinations, D5).
- New `MIDIFeedbackOutput.swift`: the `MIDIFeedbackOutput` protocol, `RecordingMIDIFeedbackOutput` (mock, tests and the
  DEBUG stand-in) and `MIDIFeedbackUMP` (MIDI 1.0 channel voice words, type 0x2).
- New `MIDISystem/CoreMIDIFeedbackOutput.swift` (`#if canImport(CoreMIDI)`): own client and `MIDIOutputPortCreate`
  port, created on the first send; `MIDISendEventList` with `MIDIEventListInit`/`MIDIEventListAdd` (D6).

App:

- `MIDIInputCoordinator`: tick observers, called after each drain (also an empty one) (D7).
- `MIDIMappingCoordinator`: an engine, an output and a `feedbackValues` closure; `receive` filters echoes first and
  reports applied values; `panic` absorbs.
- New `MIDIMappingCoordinator+Feedback.swift`: `setFeedback(_:for:)` (saves, announces), `feedbackTick()`
  (configure, destinations, values, send).
- `AppCoordinator`: one line wiring `feedbackValues` to the native host's base glow values.
- `MIDIMappingOptionsView`: a "Send feedback" switch (`midiFeedback`).
- `scripts/check_status_events.py`: the new coordinator file is checked.
- ADR-0080 records the output decision (amends ADR-0038's "no messages are sent" scope).

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/midi-feedback.md](contracts/midi-feedback.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PerformanceControl (MIDI-002 events, MIDI-003 bindings, MIDI-004 options, MIDI-005 14-bit),
ParameterGraph, CoreMIDI (public; output port and `MIDISendEventList`), SwiftUI. No new package or network API.

**Storage**: the existing `settings.midi.mappings` lines gain an optional `fb=1` segment. No new UserDefaults key.

**Testing**: package `MIDIFeedbackTests` (one change → one CC; 1000 rapid changes within the bound and the final value
delivered; incoming value → no echo; loopback over 3000 ticks; 14-bit MSB/LSB; inverse with Invert and curves, flat
piecewise; per-tick cap and round-robin; routing; option and profile round trip; UMP words); app
`MIDIFeedbackCoordinatorTests` (mock destination receives feedback; controller input not echoed; panic; switch saves and
announces); UI `MIDIFeedbackUITests` (switch on, row summary ", feedback"; under 30 s).

**Target Platform**: iOS 26.5+ / iPadOS (app); package also macOS host and Linux.

**Performance Goals**: per tick O(feedback bindings ≤ 64 × 14 search steps); at most 16 messages per tick.

**Constraints**: owner rule 7 test budgets; Xcode 26 type-check budget; no network MIDI.

**Scale/Scope**: at most 64 feedback controls.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: CoreMIDI output port and `MIDISendEventList` are public; no `MIDINetwork*`. |
| VI Modular boundaries | Pass: logic in the package behind an output protocol; CoreMIDI in `MIDISystem/`; wiring in the app. |
| VII Real-time audio safety | Pass: nothing on the audio path; feedback runs on the main actor at 30 Hz. |
| X Evidence-based quality | Pass: acceptance proven by package and app tests with a mock output; a physical motorised or LED controller is a `{device}` task. |
| Accessibility | Pass: a labelled switch with a footer; announcements on the `.midi` lane. |
| Privacy | Pass: no new key, no logging; only mapped control values are sent to local destinations the user connected. |

Post-design re-check: unchanged, no violations.

## Project Structure

```text
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIFeedback.swift              (new)
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIFeedbackOutput.swift        (new)
Packages/PerformanceControl/Sources/PerformanceControl/MIDISystem/CoreMIDIFeedbackOutput.swift (new)
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIMappingOptions.swift        (feedback)
Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIFeedbackTests.swift           (new)
Apps/projectM-iOS/Coordinators/MIDIInputCoordinator.swift                                   (tick observers)
Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator.swift                                 (properties, receive, panic)
Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+Feedback.swift                        (new)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                                         (feedbackValues wiring)
Apps/projectM-iOS/Views/MIDIMappingOptionsView.swift                                        (switch)
Apps/projectM-iOS/Tests/MIDIFeedbackCoordinatorTests.swift                                  (new)
Apps/projectM-iOS/UITests/MIDIFeedbackUITests.swift                                         (new)
scripts/check_status_events.py                                                              (new file checked)
docs/adr/0080-midi-feedback-output.md                                                       (new)
```

## Complexity Tracking

None.
