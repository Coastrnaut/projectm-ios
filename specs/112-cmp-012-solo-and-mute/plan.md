# Implementation Plan: CMP-012 Solo and Mute

**Branch**: `feature/cmp-012` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/112-cmp-012-solo-and-mute/spec.md`

## Summary

Solo and mute are a plain-Swift value, `LayerSoloMute`, kept **beside** the `LayerStack`, never in
it: four sets (soloed layers, muted layers, soloed groups, muted groups) and one pure rule that says
whether the overlay lets a stack entry through. The compositor holds one overlay
(`setSoloMute(_:)`, between frames) and resolves it to one flag per layer record at `apply` and at
`setSoloMute`; the per-frame "is this layer visible" test gains one `&& !hidden`. Every layer still
renders every frame, so nothing is prepared or released by a solo or mute change. Scenes, autosave,
undo, show cues and archives store documents built from the stack (or from the app's
`SceneInputs`), so they cannot see the overlay.

In `Packages/Compositor`:

- `LayerSoloMute.swift` (new, target `Compositor`, plain Swift, builds on Linux): `LayerSoloMute`
  (`setSolo`/`setMute` for a layer or a group, `isSoloed`/`isMuted`, `clear()`, `isEmpty`,
  `isSoloActive(in:)`, `lets(_:in:)`, `hiddenLayers(in:)`, `visibleLayers(in:)` (the full effective
  rule including group on/off and opacity 0, for UI and tests), `pruned(to:)`).
- `Compositor.swift` (focused, additive): `LayerRecord.overlayHidden`; `soloMute` (read-only) and
  `setSoloMute(_:)`; `refreshOverlay()` called at the end of `apply` and by `setSoloMute`;
  `isVisible(_:)` also requires `!overlayHidden`; diagnostics `isHiddenBySoloMute(layer:)` and
  `soloMuteHiddenLayers` (count in the last frame). CMP-011's isolation decision already uses
  `isVisible`, so it considers only drawn layers (R9). No shader change, no new pass.
- `LayerStack.swift`: header comment only (the "solo/mute will add fields" note now points to the
  overlay). No API change.

In `Packages/SceneFormat`: no source change. Tests prove the documents cannot carry the overlay
(encode before/during/after; `SceneHistory.record` suppresses; `SceneLiveState` capture unchanged).

No UI, no launch argument (spec Clarifications). No ADR: no default is overridden and no saved
format changes; the decisions are in the spec's Clarifications and [research.md](research.md).
Report: `docs/test-reports/solo-and-mute.md`.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/solo-and-mute.md](contracts/solo-and-mute.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26).

**Primary Dependencies**: none new (Metal, existing pipelines).

**Storage**: none. The overlay is never stored.

**Testing**: `Packages/Compositor`: `LayerSoloMuteTests` (CPU, Linux shape: the rule, union,
precedence, groups, stale IDs, equality of the stack unaffected); `LayerSoloMuteCompositeTests` (GPU
read-back: the acceptance with scene bytes and saved flags, mute, multi-solo, solo plus mute, group
cases, bit-identical restore, no preparation or allocation, opt-in GPU time bench `CMP012_BENCH=1`).
`Packages/SceneFormat`: `SceneSoloMuteTests` (document bytes, history suppression, live-state
capture). Regression: Compositor, SceneFormat, RenderGoldens, ImportFuzz, ShowControl, SceneArchive,
app unit tests (own simulator); Linux shape of Compositor and SceneFormat.

**Target Platform**: iOS 26+ (app), macOS host and Linux for the plain-Swift parts.

**Performance Goals**: no added pass; the overlay is resolved once per change, not per frame; a
hidden layer costs its render work (as at opacity 0) and saves its composite draw. GPU time recorded
on the Mac (CMP-012-S6), not device evidence.

**Constraints**: owner rule 7 (unit ~1-2 s, suite < 1 min); no wall-clock assertions; no per-frame
allocation (the per-record flag is a stored Bool); additive edits to shared Compositor files
(ACC-003, FILE-004 and a test-budget agent run in parallel); no C stdio globals; no main-actor
mutation in setUp/tearDown.

**Scale/Scope**: S. One model file, a small compositor change, tests, a report.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | No new API use | Pass |
| VI Modular boundaries | Model in `Compositor` beside the stack; no layer source or SceneFormat source change | Pass |
| VII Real-time audio safety | No audio code touched | Pass |
| X Evidence | CPU rule tests + GPU read-back on the Mac; GPU time labelled not device evidence | Pass |
| Accessibility / flashing | Solo and mute only remove light; the flash guard still runs on the finished composite with its history kept | Pass |
| Privacy, no networking, no telemetry | Nothing stored or logged | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/112-cmp-012-solo-and-mute/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/solo-and-mute.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/LayerSoloMute.swift                    (new)
Packages/Compositor/Sources/Compositor/Compositor.swift                       (overlay flag per record)
Packages/Compositor/Sources/Compositor/LayerStack.swift                       (header comment)
Packages/Compositor/Tests/CompositorTests/LayerSoloMuteTests.swift            (new)
Packages/Compositor/Tests/CompositorTests/LayerSoloMuteCompositeTests.swift   (new)
Packages/SceneFormat/Tests/SceneFormatTests/SceneSoloMuteTests.swift          (new)
docs/test-reports/solo-and-mute.md                                            (new)
```

**Structure Decision**: existing packages only; no new target.

## Complexity Tracking

None.
