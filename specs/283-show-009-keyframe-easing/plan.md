# Implementation Plan: SHOW-009 Keyframe Easing

**Branch**: `feature/show-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

**Model (ShowControl, Linux).** `ShowKeyframeInterpolation` grows from SHOW-008's three cases to five, in picker
order: `linear`, `stepped` (SHOW-008's former `hold`, same behavior), `hold` (a cut: flat into and out of the key),
`ease` (SHOW-008 smoothstep, unchanged) and `cubic` (monotone cubic Hermite, research D2). `ShowKeyframeTrack.value(at:)`
keeps SHOW-008's structure (exact at keys, segment-relative fraction from integer nanoseconds); the segment rule moves
to one function: the arriving key's Hold wins, then the left key's mode. Cubic numbers use `MonotoneCubic` (new,
`ShowControl/MonotoneCubic.swift`): Fritsch–Butland tangents at inner keys of a Cubic run, zero at run ends and
extrema, Hermite evaluation, clamped to the segment's key range (D2, D3). Cubic colours use the two-key shape (D4).

**Storage (ShowControl).** `StoredKeyframe` writes `interpolation` with the SHOW-008 name (`linear`, `hold` for
Stepped, `ease`; Hold → `hold`, Cubic → `ease`) and `easing` only for Hold and Cubic; reads `easing` first, then
`interpolation`, missing → Linear (D5). Shows without the new modes keep their bytes.

**App.** `ShowKeyframeCoordinator.addKeyframeAtPlayhead` keeps the mode of a keyframe it replaces. The editor's
segmented picker lists the five modes with a description line (`ShowKeyframeInterpolation.summary`). Row text already
uses `displayName`. SHOW-008 tests that meant the old `hold` now say `stepped` (same behavior).

**Acceptance proof.** `ShowKeyframeEasingTests` (package): two-key reference midpoints for all five modes, Cubic
quarter points vs 3u² − 2u³ within 1e-9, a three-key Cubic value vs the closed-form Hermite reference, Hold vs
Stepped on three keys, exact keys for every mode, no overshoot on a dense sample, storage round trip and old
documents. `ShowKeyframeEasingAcceptanceTests` (app): a playing show on a `ShowManualClock` applies the Cubic midpoint
and the Hold cut. `ShowKeyframeEasingUITests` (< 30 s): pick Cubic, the row reads "…, Cubic".

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: Foundation, SwiftUI; ShowControl, ParameterGraph (unchanged dependencies)
**Storage**: `show.json` keyframes gain an optional `easing` field; no UserDefaults key
**Testing**: ShowControl package tests (host; Linux in CI); app acceptance tests; one UI test < 30 s on
"SHOW9 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+ app; ShowControl also Linux
**Performance Goals**: evaluation stays O(log k) per track plus O(1) for the two tangents of a Cubic segment
**Constraints**: type-check budget; short tests (owner rule 7); no edits to `AppCoordinator`, `SettingsView`,
`Compositor` or `VisualizerView`
**Scale/Scope**: ≤ 16 tracks × 256 keyframes (SHOW-008)

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: SwiftUI and Foundation only |
| VI Modular boundaries | Pass: curve math in ShowControl (pure, Linux); UI in the app |
| VII Real-time audio safety | Pass: nothing on the audio thread; evaluation is O(1) extra per segment on the main actor |
| X Evidence-based quality | Pass: pure tests against closed-form references; simulator UI test is behavior only; `{device}` task open |
| Privacy (no network, no new key) | Pass |

Post-design re-check: unchanged (no new dependency, no new key, no network).

## Project Structure

```text
specs/283-show-009-keyframe-easing/  plan.md research.md data-model.md quickstart.md contracts/keyframe-easing.md tasks.md
Packages/ShowControl/Sources/ShowControl/ShowKeyframes.swift          # five modes, segment rule
Packages/ShowControl/Sources/ShowControl/MonotoneCubic.swift          # new: tangents, Hermite
Packages/ShowControl/Sources/ShowControl/ShowKeyframesDocument.swift  # easing field, missing → linear
Packages/ShowControl/Tests/ShowControlTests/ShowKeyframeEasingTests.swift   # new
Packages/ShowControl/Tests/ShowControlTests/ShowKeyframeTrackTests.swift    # .hold → .stepped
Apps/projectM-iOS/Coordinators/ShowKeyframeCoordinator.swift          # keep mode on replace
Apps/projectM-iOS/Views/ShowKeyframeTracksView.swift                  # picker + description
Apps/projectM-iOS/Tests/ShowKeyframeEasingAcceptanceTests.swift       # new
Apps/projectM-iOS/Tests/ShowKeyframeAcceptanceTests.swift             # .hold → .stepped
Apps/projectM-iOS/UITests/ShowKeyframeEasingUITests.swift             # new
```

## Complexity Tracking

None.
