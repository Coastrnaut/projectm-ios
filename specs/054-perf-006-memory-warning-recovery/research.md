# Research: PERF-006 Memory Warning Recovery

Decisions taken under the owner's standing delegation (owner rule 4). Each names what was chosen,
why, and what was rejected.

## PERF-006-D1 — Signal source

- **Decision**: observe `UIApplication.didReceiveMemoryWarningNotification` only, in one coordinator.
  PERF-004's own observer in `SharedTexturePool` is removed; the pool becomes a step.
- **Rationale**: one documented app-level signal; Xcode's Simulate Memory Warning sends it. A
  dispatch memory-pressure source fires for the same kernel event and would make every warning look
  like a repeat (false escalation).
- **Alternatives**: dispatch source too (rejected, duplicate); each component observing (rejected,
  unordered and unreported, against PERF-006-R1).

## PERF-006-D2 — Where the policy lives

- **Decision**: `MemoryPressureRecovery` in `PresentationLifecycle`, main actor, weak responders,
  mirroring `PresentationResourceRegistry` (PERF-011).
- **Rationale**: pure Swift, testable on Linux with fakes and a test clock; one small type does not
  justify a new package.
- **Alternatives**: app-only (escalation testable only in the simulator); Diagnostics package (it is
  logging, not lifecycle).

## PERF-006-D3 — Tiers, order and escalation

- **Decision**: two tiers. Cache steps run on every signal in registration order; optional steps run
  only on escalation (critical, or a warning within 30 s of the previous signal) and stay shed until
  60 s after the last escalating signal; each is restored once. Signals arriving during a recovery
  are queued and handled after it.
- **Rationale**: caches are free to drop; background work costs smoothness, so it is shed only when
  freeing caches was not enough. Registration order is deterministic and owners register at creation.
- **Alternatives**: ordering by estimated bytes (estimates differ in quality; order adds nothing when
  all cache steps run anyway); a third "visible" tier (nothing visible is ever shed, D5).

## PERF-006-D4 — Time

- **Decision**: the recovery takes the current monotonic time (seconds, `Double`) as an argument; the
  app passes `MonotonicClock.nowNanoseconds()`; the restore timer is a main-actor `Task` that sleeps
  until the cool-down ends and calls `restoreIfDue`, rescheduling itself when the cool-down was
  extended.
- **Rationale**: no wall clock in the policy; tests are deterministic and instant.

## PERF-006-D5 — What may be freed

- **Decision**: cache tier: the shared texture pool's retired pictures (measured bytes); the preset
  warm-up's thread, EGL context, engine and 256 × 256 target (estimated bytes: the target, 256 KiB, a
  lower bound; the engine and context have no public size); the preset archive's decompressed chunk
  (measured); a native spectrum host that is not the chosen visual (items, no byte figure). Optional
  tier: the preset warm-up itself (requests held during the cool-down).
- **Never freed**: anything the shown visual uses (pictures in use, the decoded photo, camera feed,
  video decoder, projectM's visible engine, the glow and overlay spectrum), the audio source, stored
  settings and files, and the warm-up's record of presets already warmed (a set of IDs).
- **Rejected**: shedding glow (visible change, clarification 3); dropping projectM's engine while
  Camera or Photo is shown (the preset state would be lost; projectM is paused, not idle-cached,
  by design of VIS-001); flushing ANGLE's or Metal's pipeline caches (no public API; they are owned
  by the driver and the OS trims them under pressure itself).

## PERF-006-D6 — GPU release safety (fence rule)

- **Decision**: the pool purge drops retired pictures, including ones still waiting for their last
  command buffer: the command buffer keeps its own retained reference (PERF-004 contract: compositors
  use `makeCommandBuffer()` with retained references), so Metal frees the memory only when the GPU is
  done. The warm-up stop runs on its own thread's safe points and destroys its context there
  (PERF-011-R7, `PMANGLEFinish` after each frame). The spectrum host is released only while paused:
  its frame loop has stopped and its in-flight command buffers hold their own references.

## PERF-006-D7 — Injection for tests

- **Real**: none on the simulator: no public, scriptable way exists to put the simulator under real
  memory pressure (Xcode's Debug > Simulate Memory Warning is a menu item, not scriptable from
  `simctl`, and is not used, owner rule 8). Real pressure is the `{device}` task.
- **Simulated, same path as the system**: the DEBUG probe posts
  `UIApplication.didReceiveMemoryWarningNotification` on `NotificationCenter.default`, exactly the
  notification UIKit posts, so the coordinator's observer, ordering, steps and logging all run as
  they would for a real warning. The critical button calls the coordinator directly (the system
  signal carries no level, D1).
- **Determinism**: under `-uitestMemoryPressure` the shared pool's idle-age limit is raised so retired
  pictures made by a rotation are still there when the test injects (otherwise the 300-frame idle
  eviction races the injection on a slow shared Mac). The byte cap is unchanged.

## PERF-006-D8 — Reporting

- **Decision**: `DiagnosticsLog.memoryRecovery(_ summary:)` emits one Points of Interest event and one
  app log line, private like every dynamic value; the summary is built in the package from the report
  ("warning escalated=no freed 1048576 B [shared texture pool 1048576 B 4, …]"). DEBUG readouts show
  the recovery count, the last report's freed bytes, the pool's retired bytes, whether the warm-up
  holds a context, and the shown visual's frame count.
- **Rejected**: a user-visible notice (clarification 4); MetricKit (aggregated daily, not per event).
