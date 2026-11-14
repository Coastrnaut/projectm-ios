# Implementation Plan: XFADE Cue Transitions On Screen

**Spec**: [spec.md](spec.md) · **Date**: 2026-11-14

## Summary

Add a frozen-frame output transition to the CMP-001 `Compositor` (CMP-014's clock, weights and mix formula,
PERF-004 textures) and replace the app's recording driver with a stage that freezes the shown compositor's
frame before a cue applies and starts the transition on the compositor shown after it.

## Technical Context

Swift 6, Metal, iOS 26+. Packages: `Compositor` (new `OutputTransition.swift`; a small hook block in
`Compositor.swift`). App: `CueTransition.swift` (`CueTransitionStage`), the four compositor hosts expose their
command queue, `AppCoordinator+Show.swift` wiring, a DEBUG seed and probe. No new settings keys, no networking,
no scene format change, no new default (no ADR).

## Constitution Check

Public APIs only (Metal events, blits, render passes). Local only. Safety: the flash guard measures every
shown frame including blends; Reduce Motion is a cut. Pass.

## Design

### Compositor (package)

- `FrozenOutputFrame` (public, final class): a pooled `rgba16Float` copy of a shown frame, the Metal event its
  copy signals, the copy's command buffer (the fence when never used) and its pool; released once (explicitly
  or in `deinit`).
- `OutputTransitionPass` (internal): the frozen frame, the `SceneTransitionClock`, the resolved spec, the pooled
  blend target, a lazily built mix pipeline (self-contained shader: full-screen triangle and
  `outgoing × w.x + incoming × w.y`, the bus's formula), counters.
- `Compositor`:
  - `freezeShownFrame(commandBuffer:) -> FrozenOutputFrame?` copies `shownComposite` (blit), signals the event and
    makes the copy's command buffer the compositor's pool fence.
  - `beginOutputTransition(from:spec:reduceMotion:)`: an instant resolved spec releases the frame and ends any
    transition; otherwise it replaces any running one (restart) and resets trails.
  - `endOutputTransition()`, `isOutputTransitioning`, `outputTransitionBlendedFrames`, `outputTransitionProgress`,
    `holdsOutputTransitionTextures`.
  - In `encodeFrame`, only on the `composite(into:)` path: after the trails step and before `shownComposite`, the
    shown texture becomes the pass's result. `encodeScene` (the bus) is unchanged. `deinit` releases.

### App

- `CompositorVisualHost` protocol (`compositor`, `queue`), adopted by Camera, Photo, Video and Text hosts
  (`queue` becomes internal).
- `CueTransitionStage` replaces `CueTransitionRecorder` (keeps `last`, `lastSceneID`): `driveTransition` freezes the
  shown host's frame for a non-instant spec; `sceneApplied()` begins the transition on the host shown then, or drops
  the frame (outcome unsupported). `probe` text for DEBUG.
- `AppCoordinator+Show.swift`: `shownCompositorHost`, the stage's host provider, `sceneApplied()` after
  `applyShowScene` in the show's `applyScene` closure.
- DEBUG: `-uitestShowTransitionSeed` (two Text cues; cue 2 a 2 s linear crossfade) in `UITestShowFixture`, and a
  `cueTransitionProbe` text in the `-uitestDiagnostics` block of `VisualizerView` (one line).

## Tests

- Compositor `OutputTransitionTests` (GPU, 64 × 64, injected 60 Hz): red/blue crossfade at 0, 0.5, 1 s; easeIn;
  dip to black; cut byte-identical; Reduce Motion; restart from the blended frame; 20 transitions without leaks;
  strobing transitions lower the guard gain; capture and `encodeOutput` see the blend; cross-compositor freeze.
- App `CueTransitionStageTests`: ShowCoordinator + stage + two test hosts; 59 blended frames; cut and unsupported.
- UI `CueTransitionUITests.testACueCrossfadeShowsOnScreen` (< 30 s).

## Budgets

Unit tests ≤ 2 s each, package suite run filtered, UI test < 30 s, type-check limits 300/150 ms.
