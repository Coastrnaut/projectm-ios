# Implementation Plan: SHOW-008 Keyframe Tracks

**Branch**: `feature/show-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

**Model (ShowControl, Linux).** `ShowKeyframes.swift`: `ShowKeyframeColor` (sRGB components 0…1 with alpha, linear-light
conversion), `ShowKeyframeValue` (number or colour), `ShowKeyframeInterpolation` (hold, linear, ease),
`ShowKeyframe` (whole-millisecond time, value, interpolation), `ShowKeyframeTrack` (ID, parameter ID, keyframes in time
order, one kind) and `ShowKeyframeTracks` (≤ 16 tracks, one per parameter). `value(at:)` is a pure function of a
timeline time: exact stored sample at a keyframe time, segment-relative interpolation between (research D1, D2).
Edits: `setKeyframe` (replaces at the same time), `removeKeyframe`, `setInterpolation`, `addTrack`, `removeTrack`.
`ShowCueList.tracks` holds them; `show.json` gains an optional `tracks` list written only when non-empty, read
leniently with two counted warnings (`droppedKeyframeTracks`, `droppedKeyframes`); no version bump (D3).

**Live layer (app).** `ShowKeyframeCoordinator` (observable): the available targets (the four glow parameters from
the MOD-001 registry with their ranges and steps, and Visual Colour), `sample()` (timeline time from SHOW-007's
transport → `ShowKeyframeTracks.values(at:)` → clamp numbers to the registry range → `ShowTrackOutput`), applying it
through `apply` only when it changed (D4). A main-actor loop samples at display rate (1/60 s) while the show plays and
tracks exist, at 4 Hz otherwise (paused or Standby: the output does not change, so nothing applies); the transport
calls `positionJumped` after every seek and the show's step path after every step, so a jump is sampled at once (D5).
Edits go through `ShowCoordinator.setKeyframeTracks` (refused while locked, saved at once) and resample.

**Output (app).** `AppCoordinator` keeps `showTrackOutput`; the native host's external values become the track
numbers overlaid by MIDI/OSC live values (`hostExternalValues`), so MOD-002 bindings and ACC-012's clamp follow as
before; `effectiveSpectrumPalette` returns a one-colour palette for Visual Colour unless ACC-003's colour-blind-safe
switch is on (D6).

**UI.** `ShowKeyframeTracksView` (Settings → Show → Keyframe Tracks…): the playhead time, Add Track… (a dialog of the
targets not used yet), per track a section with its keyframes ("0:30, 0.90, Linear"), Add Keyframe at Playhead and
Delete Track; a keyframe opens `ShowKeyframeEditView` (ACC-005 slider or the system colour picker, interpolation
picker, Delete Keyframe). Edits hidden while locked (SCN-015-R6).

**Acceptance proof.** `ShowKeyframeTrackTests` (package): exact values at every keyframe time (numbers and colours),
midpoints, hold, before/after, round trip and lenient read. `ShowKeyframeAcceptanceTests` (app): the transport on a
`ShowManualClock`, a recorder of applied outputs: seek to a keyframe time applies that exact value once; repeat →
none; playing across keys twice gives the same sequence; lock refuses edits. `ShowKeyframeUITests` (< 30 s).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: Foundation, SwiftUI; ShowControl, ParameterGraph, VisualParameters, VisualGenerators
**Storage**: `show.json` optional `tracks` field; no UserDefaults key
**Testing**: ShowControl package tests (host; Linux in CI); app acceptance tests; one UI test < 30 s on
"SHOW8 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+ app; ShowControl also Linux
**Performance Goals**: evaluation O(log k) per track (binary search), ≤ 16 tracks × 256 keyframes; sampling at 60 Hz
only while playing with tracks
**Constraints**: type-check budget; short tests (owner rule 7); shared files (`AppCoordinator`, `ShowEditorView`)
get small edits
**Scale/Scope**: 5 targets in this version

## Constitution Check

- I (public APIs only): Foundation, SwiftUI (`ColorPicker`). Pass.
- VI (modular boundaries): tracks and evaluation in ShowControl (pure, Linux); sampling and output in the app. Pass.
- VII (real-time audio safety): no audio-thread work. Pass.
- VIII (projectM fidelity): no engine change. Pass.
- Privacy / local-first: no network, no new key; tracks live in the local show file. Pass.
- Accessibility (FR-070, ACC-005): labelled rows, accessible slider, colour picker labelled. Pass.
- Safety (ACC-012): numbers enter the host before MOD-002 and the clamp; colours go through the palette path, whose
  frames the flash limiter already covers. Pass.
- X (evidence): injected clocks, output recorder, no wall-clock assertions; simulator proves behavior only.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/ShowControl/Sources/ShowControl/ShowKeyframes.swift               # model + evaluation (new)
Packages/ShowControl/Sources/ShowControl/ShowKeyframesDocument.swift       # show.json `tracks` coding (new)
Packages/ShowControl/Sources/ShowControl/ShowCueList.swift                 # `tracks` field
Packages/ShowControl/Sources/ShowControl/ShowDocument.swift                # write/read `tracks`, warnings
Packages/ShowControl/Tests/ShowControlTests/ShowKeyframeTrackTests.swift   # new
Apps/projectM-iOS/Coordinators/ShowKeyframeCoordinator.swift               # new
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift                       # setKeyframeTracks (edit)
Apps/projectM-iOS/Coordinators/ShowTransportCoordinator.swift              # positionJumped hook
Apps/projectM-iOS/Coordinators/AppCoordinator(+Show).swift                 # lazy var, output, palette
Apps/projectM-iOS/Views/ShowKeyframeTracksView.swift                       # new; ShowEditorView one link
Apps/projectM-iOS/Tests/ShowKeyframeAcceptanceTests.swift                  # new
Apps/projectM-iOS/UITests/ShowKeyframeUITests.swift                        # new
```
