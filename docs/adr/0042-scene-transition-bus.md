# ADR-0042: One Transition Clock and a Two-Scene Transition Bus with One Flash Guard

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: CMP-014 (`specs/116-cmp-014-compositor-transition-bus`)
- **Constitution**: VI (modular boundaries: the bus lives in `Compositor`, no engine or app imports),
  X (evidence-based quality); flash safety (FR-072, FX-019); accessibility (ACC-001)
- **Builds on**: ADR-0013 (unified layer protocol), CMP-002 (stack), PERF-004 (texture pool), FX-019
  (composite flash guard), REC-003 (recording output), ADR-0040 (render caching), ADR-0033 (show cues)
- **Number**: 0042 (0041 went to FILE-005's backup ADR at integration); 0015, 0016, 0025, 0026 and 0031 stay unused.

## Context

The roadmap asks to "blend whole scene outputs using one consistent transition clock", accepted when a
"crossfade reaches exact start/end states with no leaked textures". Before this ADR every cue change was
a cut, one compositor drew one scene, and its flash guard and output pass were fused with the stack phase.
SCN-007 (stored transitions) and SHOW-004 (overrides) depend on this row.

## Decision

1. **A scene output is one compositor.** A `SceneTransitionBus` holds the live scene and, during a
   transition, the outgoing scene: two `Compositor` instances sharing one texture pool, never more.
2. **The compositor's stack phase is callable alone.** `Compositor.encodeScene(…)` runs exactly the stack
   phase of `composite(into:)` (frame tick, render health, layer renders, CMP-013 reuse, pool tick,
   command-buffer watch) and returns the composite. `composite(into:)` is unchanged: it runs the same
   phase, then its own guard and output pass.
3. **One clock: the frame timeline.** `SceneTransitionClock` sums the presentation-time differences of the
   frames shown, each clamped to 0.1 s (`LayerFrameClock.maxFrameDuration`), in integer nanoseconds. The
   first frame after the start or after `pause()` adds nothing. Progress is elapsed / duration, exactly 1
   on the first frame at or after the duration; easing (linear, smoothstep) is applied afterwards and is
   exact at both ends. No wall clock is read.
4. **Exact ends by construction.** At progress 0 the shown texture is the outgoing scene's own composite;
   from progress 1 (when the outgoing scene and blend target are released, before encoding) it is the live
   scene's own composite. Only 0 < progress < 1 runs the mix pass (crossfade, or dip to black) into a
   pooled `rgba16Float` blend target. The guard and output pass are the compositor's own shader source,
   so end frames are byte-identical to the scene alone given the same guard history.
5. **One flash guard on every shown frame.** The bus owns one `CompositeFlashGuard` for its life; scenes
   contribute composites only. Blends and cuts between scenes are measured by the same history, so no
   transition bypasses FX-019. Rejected: a guard per scene plus a second guard after the mix (two gains and
   a settle step to keep the exact end).
6. **Interruption snaps, then starts; cancel goes back.** A new transition during a transition finishes
   the running one at once (its outgoing scene and blend target released), then starts from its incoming
   scene at progress 0. Cancel makes the outgoing scene live again and releases the incoming scene;
   finish-now keeps the incoming scene. At most two scenes are held.
7. **No leaks.** The blend target is the only texture the bus takes from the pool; it goes back, fenced
   by the last command buffer, at the end, on cancel, interruption, size change and deinit. A released
   scene returns its own textures in its deinit.
8. **No bus-level cache.** Each scene keeps its CMP-013 reuse; the bus mixes every blended frame again.
9. **Reduce Motion makes scene transitions cuts.** A transition between scenes is decorative
   (`SceneTransitionSpec.resolved(reduceMotion:)`, `MotionPolicy.sceneTransition`). Blackout and its
   Restore fade, and PERF-014's placeholder, stay safety fades.
10. **No file format change in this row.** `SceneTransitionSpec` is validated and Codable (style, 0…10 s,
    easing) so SCN-007 can store it with each cue; show.json v1 and the scene format are unchanged, and a
    cue without a stored transition stays a cut.
11. **The app's live output is not moved yet.** The app's visuals are separate hosts (projectM on ANGLE,
    the native spectra, one compositor per photo, text, video and camera visual). Feeding the device slot,
    the external display and recording from a bus needs a scene compositor carrying every visual as a layer;
    that is follow-up work. Any output fed from a bus shows the same frame through `encodeOutput` (REC-003
    pattern).

## Consequences

- Two scenes cost two stack phases plus one full-screen pass per blended frame (recorded on the Mac:
  `docs/test-reports/transition-bus.md`).
- Two compositors tick a shared pool twice per frame during a transition; only idle-age eviction of
  retired textures runs faster for those frames.
- SCN-007 stores the spec; SHOW-004 overrides it per cue edge.
