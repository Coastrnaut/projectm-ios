# Research: PERF-011 Background resource release

Findings come from reading the repository at `e679131`. Statements about platform behavior that
were not observed on a device are marked as assumptions.

## PERF-011 research 1: which signals mean "cannot present"

- **Decision**: background and device lock, from the four notifications `LifecycleObserver`
  already maps (`didEnterBackground`, `willEnterForeground`, `protectedDataWillBecomeUnavailable`,
  `protectedDataDidBecomeAvailable`). The inactive scene phase does not count.
- **Rationale**: these are the events FR-050 and FR-054 already use, so the visualization and the
  resources change state together. In the inactive state the app is still on screen.
- **Alternatives**: SwiftUI `scenePhase == .background` as a second source (rejected: two sources
  for one fact can disagree in order); stopping on inactive (rejected: freezes a visible picture).

## PERF-011 research 2: unlock while backgrounded

- **Decision**: two independent flags; foreground clears both.
- **Rationale**: HEAD's single `suspended` flag is cleared by `.unlock` even when the app is still
  in the background, which resumes the display link there. With System/App Capture the process
  stays alive in the background (ADR-0001 ruling 17), so this path is reachable.
- **Alternatives**: require an unlock before resuming (rejected: a missed unlock signal would
  leave the app suspended in the foreground).

## PERF-011 research 3: what the renderer releases

- **Decision**: display link, EGL window surface, Reduce-flashing target. Keep context, engine,
  preset and textures.
- **Rationale**: the window surface is destroyed and recreated today on every size change
  (`layoutSurface`), so the recreate path is already exercised on devices by rotation. Recreating
  the engine would recompile shaders (about a second for heavy presets, feature 002 performance
  notes) and restart the preset.
- **Assumption (device check S8)**: the layer keeps its last presented contents after the EGL
  surface is destroyed, so the app switcher card is not blank.
- **Alternatives**: pause the link only (HEAD; rejected: holds full-screen drawables); destroy the
  engine too (rejected above).

## PERF-011 research 4: stopping the warm-up

- **Decision**: synchronous, restartable `stop()` with safe points between engine calls.
- **Rationale**: after it returns no GPU command can be issued from the warm-up thread. The
  existing `deinit` already waits the same way. The wait is one engine call at most.
- **Assumption**: the system does not permit GPU work from a background app for long; whether a
  command issued in the grace period fails is not relied on, because none is issued.
- **Alternatives**: asynchronous stop (rejected: work may still run after the transition);
  lowering thread priority (rejected: still works and still holds memory).

## PERF-011 research 5: where the code lives

- **Decision**: new pure-Swift package `PresentationLifecycle`; see plan, Structure Decision.

## PERF-011 research 6: measurement hooks

- **Decision**: one signpost event per transition through the existing `OSSignposter`
  (`DiagnosticsLog`), carrying the state and the active counts. No MetricKit and no Metal counter
  code is added now.
- **Rationale**: the roadmap's hint says "where appropriate". Signposts appear in Instruments next
  to the GPU and memory tracks used for S7. MetricKit delivers daily aggregates and would need a
  subscriber and storage, which this feature does not need to prove its criterion.
