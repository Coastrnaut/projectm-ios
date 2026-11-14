# Research: CMP-014 Compositor Transition Bus

## D1 Two scene outputs

- **Decision**: a scene output is one `Compositor`; the bus holds two during a transition, sharing the
  app's texture pool.
- **Rationale**: the compositor already owns everything a scene needs (stack, pictures, caching,
  health). Two compositors need no change to the layer contract.
- **Alternatives**: two layer stacks inside one compositor (a large change to `Compositor.swift`, which
  ACC-005 and FILE-005 may touch in parallel); a frozen snapshot of the outgoing scene (shows a still
  frame, not a live scene).

## D2 Where the flash guard runs

- **Decision**: the bus owns one `CompositeFlashGuard`; scenes contribute only their composites
  (`encodeScene`).
- **Rationale**: one guard sees every shown frame with a continuous history, so neither a blend nor a
  cut between scenes bypasses FX-019. Per-scene guards would each see only their own scene; switching
  to an incoming scene whose guard never saw the blend could jump past the envelope.
- **Alternatives**: a second guard after the per-scene guards (two gains, and a settle step at the end
  to keep exact ends).

## D3 Exact ends

- **Decision**: no mix pass at progress 0 or ≥ 1; the scene's own composite feeds the same guard and
  output shader.
- **Rationale**: byte identity by construction rather than by arithmetic (a mix with weights 1 and 0
  would also be exact in float, but skipping it is cheaper and obviously exact).

## D4 Clock

- **Decision**: integer nanoseconds of summed frame durations, each clamped to 0.1 s
  (`LayerFrameClock.maxFrameDuration`), first frame after start or resume adds 0; progress =
  elapsed / duration, exactly 1 when elapsed ≥ duration; easing applied after.
- **Rationale**: the compositor's frame timeline, deterministic from injected times, exact end, pause
  of any length is invisible.

## D5 Interruption and cancel

- **Decision**: snap-then-start for interruption; cancel back to the outgoing scene; finish-now to the
  incoming scene (spec Clarifications).

## D6 Render caching

- **Decision**: no bus-level cache. Each scene compositor keeps its own CMP-013 reuse (correct for that
  scene); the bus encodes the mix every blended frame.

## D7 Reduce Motion

- **Decision**: `SceneTransitionSpec.resolved(reduceMotion:)` returns `.cut` for any non-cut spec when
  Reduce Motion is on; the app's `MotionPolicy.sceneTransition(_:)` calls it with the system state.

## D8 Persistence

- **Decision**: none in this row (SCN-007 owns it). The spec type is Codable with validation so SCN-007
  can store it.

## D9 Pool ticks

- **Decision**: accepted that two compositors tick a shared pool twice per frame during a transition
  (idle-age eviction runs a little faster for those frames). Harmless: only retired textures age.
