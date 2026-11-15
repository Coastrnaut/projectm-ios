# Implementation Plan: SHOW-013 Auto Scene Rotation

**Branch**: `feature/show-013` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

**Model (ShowControl, Linux).** `SceneRotation.swift`: `SceneRotationSettings` (mode timer/bars, interval 15–600 s,
bars 1–64, optional folder, disabled scene IDs; Codable with every field optional on decode, clamped), the pure
`SceneRotationPlan` (collection from a `ShowCueList` and a folder via `SceneFolderTree.subtree`; `pick(current:seed:step:)`
→ `.scene(id)` or `.idle(.noScenes | .oneScene)`, drawn with MOD-008's `SteppedRandom.level(seed:step:)` over the enabled
scenes minus the current one, research D1) and `SceneRotationSchedule.deadline(after:settings:barLine:reduceFlashing:)`
(timer: start + interval; bars: the Nth bar line strictly after start from an injected `barLine` closure, then later bar
lines until the 4 s / 15 s minimum gap; no bar line → timer, D2). Foundation and ParameterGraph only (already a
dependency).

**Coordinator (app).** `SceneRotationCoordinator` (main actor, `@Observable`): owns the stored settings
(`settings.show.rotation`, JSON data), session on/off, seed and step; reads an injected nanosecond clock
(`MonotonicClock`, the tempo's clock), SHOW-011's `TempoSnapshot` (bar line = `nextBoundary(after:beats: 4)`), Reduce
flashing and a hold closure (SHOW-002's holds plus "a timed cue counts down unheld", D3). `tick()` arms, holds and fires;
a due pick goes to the scene's first cue with `show.timedGo(to:)` (timer) or `show.stepNow(.go)` (bars, already on the
bar). `sceneChanged()` (chained onto `ShowCoordinator.cueStarted` after SHOW-002's driver) rearms from now. A main-actor
task ticks every 250 ms (or sooner at the deadline) only while rotation is on (D4); tests call `tick()`.

**UI.** `SceneRotationSection` in Settings › tail sections after SHOW-003's quantize section: Rotate scenes toggle,
Collection picker (All scenes / folder paths), Change picker (Timer / Bars), interval or bars picker, status line
(`sceneRotation.status`), and a "Scenes in rotation" navigation list with one toggle per scene (`sceneRotation.scene.<n>`).
DEBUG: `-uitestSceneRotation <seconds>` turns rotation on at launch with that interval (no minimum) and seed 1, for the
UI test only (D5).

**Acceptance proof.** `SceneRotationTests` (package): 1000 seeded steps with two disabled scenes → 0 disabled picks, 0
immediate repeats, identical sequence for the same seed, every enabled scene reached; one enabled → idle one scene; zero
→ idle no scenes; folder collection; schedule timer, bars at 120 BPM (8th bar line), no tempo fallback, minimum gap with
and without Reduce flashing; settings decode defaults and clamps. `SceneRotationAcceptanceTests` (app): a real
`ShowCoordinator` with a temporary `ShowStore`, five stored scenes, injected clock: no switch at 29 s, a real scene
switch (applied scene changes, `applyScene` called) at 30 s; a manual Go restarts the interval; holds and a running
countdown pause it; disabled scenes never applied over 50 rotations; settings stored in the one key. `SceneRotationUITests`
(< 30 s): seeded show, `-uitestSceneRotation 2` → the applied scene changes twice by itself, never to the same scene.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: Foundation, SwiftUI; ShowControl, ParameterGraph (`SteppedRandom`), PerformanceControl
(`TempoSnapshot`), AudioCore (`MonotonicClock`)
**Storage**: one UserDefaults key `settings.show.rotation` (JSON; excluded from backups, erased with Settings)
**Testing**: ShowControl package tests (host; Linux in CI); app acceptance tests; one UI test < 30 s on
"SHOW13 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+ app; ShowControl also Linux
**Performance Goals**: a pick is O(scenes) (≤ 256); a 250 ms main-actor tick only while rotation is on
**Constraints**: type-check budget; short tests (owner rule 7); small edits to shared files (`AppCoordinator.swift`,
`AppCoordinator+Show.swift`, `SettingsView.swift`, `VisualizerView.swift`)

## Constitution Check

- I (public APIs only): Foundation, SwiftUI. Pass.
- VI (modular boundaries): plan and schedule pure in ShowControl (no new dependency); timing, tempo and the step path in
  the app. Pass.
- VII (real-time audio safety): reads the published tempo snapshot on the main actor. Pass.
- VIII (projectM fidelity): no engine change. Pass.
- Photosensitivity (FR-072): switches use the cue path's transition with Reduce flashing applied; bars mode keeps ≥ 4 s
  (≥ 15 s with Reduce flashing) between switches. Pass.
- Privacy / local-first: no network; one device preference key, never backed up. Pass.
- Accessibility: standard controls with labels; the status line is a text element; switches announce through the cue lane.
- X (evidence): injected clocks; simulator proves behavior only; `{device}` task open.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/ShowControl/Sources/ShowControl/SceneRotation.swift                # model (new)
Packages/ShowControl/Tests/ShowControlTests/SceneRotationTests.swift        # new
Apps/projectM-iOS/Coordinators/SceneRotationCoordinator.swift               # new
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                         # lazy `sceneRotation` (edit)
Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift                    # wiring (edit)
Apps/projectM-iOS/Coordinators/AppSettings.swift                            # key in allKeys (edit)
Apps/projectM-iOS/Views/SceneRotationSection.swift                          # new
Apps/projectM-iOS/Views/SettingsView.swift, VisualizerView.swift            # pass the coordinator (edit)
Apps/projectM-iOS/Tests/SceneRotationAcceptanceTests.swift                  # new
Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift                         # excluded key (edit)
Apps/projectM-iOS/UITests/SceneRotationUITests.swift                        # new
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, LibraryErasePolicy.swift   # key lists (edit)
scripts/run_device_tests.py                                                 # ALLOWED_KEYS (edit)
```

## Complexity Tracking

None.
