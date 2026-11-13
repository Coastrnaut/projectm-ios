# Feature Specification: PERF-006 Memory Warning Recovery

**Feature Branch**: `feature/perf-006` (spec directory `054-perf-006-memory-warning-recovery`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement PERF-006 (Memory warning recovery) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Evict caches and optional layers
on memory pressure." Acceptance, verbatim: "Injected warning drops cache usage and retains playable
scene." P0, effort M, depends on PERF-004 (integrated). Verification: performance unit + simulator +
physical device last stage."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `PERF-006-R1…`, success criteria `PERF-006-S1…`, tasks `PERF-006-T01…`.
Requirements of other features are cited by their own IDs: PERF-004-R5 (the texture pool frees its
retired pictures on a memory warning), PERF-011-R7 (the preset warm-up releases its thread, context,
engine and target when stopped), CMP-001-R9 (nothing is created per frame at a steady size).

## Baseline: what exists today (audit of 2026-11-13, commit `8a7a923`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Memory warning signal | Only `SharedTexturePool` (PERF-004) observes the system memory warning, and it purges retired pictures. | No single place receives warnings; nothing else reacts; nothing reports what was freed. |
| Preset warm-up (feature 002, PERF-011) | A background engine with its own drawing context and 256 × 256 target warms upcoming presets. Its thread keeps the context while it waits for the next request. It is released only when the app cannot present frames. | On a memory warning the warm-up keeps its context, engine and target, and goes on starting work. |
| Preset archive (feature 002) | The pack archive keeps the last decompressed chunk in memory (up to a few hundred KB) so stepping through a folder rarely decompresses twice. | Never dropped. |
| Idle native spectrum | A circular or linear spectrum created once stays alive (paused, with its glow images) after the user moves to projectM, Camera, Photo or Video. | Never dropped while another visual is chosen. |
| Repeated warnings | — | No escalation when the system warns again shortly after, and no cool-down. |
| Diagnostics | PERF-011 logs presentation transitions as counts. | No memory-recovery event. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

(Filled by `/speckit-clarify`.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The show keeps playing when the device runs low on memory (Priority: P1)

A performer runs the visualizer for a long set while other apps hold memory. The system warns the
app that memory is low. The app immediately frees what it can rebuild later (idle pictures, the
background preset warm-up and its drawing context, decompressed preset data, a spectrum that is not
shown). The visual on screen keeps rendering without a visible change and the audio source keeps
playing; nothing the user chose or stored changes.

**Why this priority**: It is the row's acceptance. An app that ignores memory warnings is terminated
by the system, which ends the performance.

**Independent Test**: Inject a memory warning while a visual renders: the freed caches report zero
remaining (idle pictures 0 bytes, no warm-up context), the next frame renders, frames keep coming,
and the audio source was not restarted.

**Acceptance Scenarios**:

1. **Given** the Photo (or Camera) visual rendering with idle pictures in the shared pool, **When** a
   memory warning arrives, **Then** the pool holds no idle picture afterwards, the freed bytes are
   reported, and frames keep being shown.
2. **Given** projectM rendering with the preset warm-up holding its drawing context, **When** a memory
   warning arrives, **Then** the warm-up holds no context, engine or target afterwards and projectM
   keeps rendering.
3. **Given** any visual and source, **When** a memory warning arrives, **Then** the audio source is not
   stopped or restarted, the chosen visual stays the shown visual, and no setting changes.
4. **Given** caches were freed, **When** they are needed again (a visual switch, the next preset
   warm-up request, a pack preset load, choosing a spectrum again), **Then** they are rebuilt on
   demand without an error.

---

### User Story 2 - Repeated pressure sheds optional background work for a while (Priority: P2)

When the system warns again shortly after the first warning (or signals critical pressure), freeing
caches has not been enough. The app also holds back optional background work (the preset warm-up)
for a cool-down, then brings it back by itself. The shown visual is never shed.

**Why this priority**: Background GPU work that immediately rebuilds what was just freed would undo
the recovery; but shedding it on every single warning would cost preset-switch smoothness for no
reason.

**Independent Test**: With fake recovery steps and a test clock: one warning runs only the cache
steps; a second warning inside the repeat window (or a critical signal) also runs the optional
steps; after the cool-down the optional steps are restored exactly once.

**Acceptance Scenarios**:

1. **Given** no recent warning, **When** one warning arrives, **Then** only cache steps run.
2. **Given** a warning less than the repeat window ago, **When** another arrives, **Then** cache steps
   run again and optional steps are shed until the cool-down ends.
3. **Given** optional work is shed, **When** the cool-down passes with no further warning, **Then** the
   optional work is restored once; a warning during the cool-down extends it.
4. **Given** optional work is shed, **When** a preset warm-up is requested, **Then** it is remembered
   and issued only after the restore.

---

### User Story 3 - What was freed is visible to diagnostics (Priority: P3)

A developer investigating a device report can see, in the system log and in a debug readout, how
many recoveries ran, whether they escalated and how many bytes each freed, without any user content.

**Why this priority**: Without a report the recovery cannot be verified on devices.

**Independent Test**: The diagnostics summary for a recovery names the level, escalation, steps and
byte counts and nothing else; the debug readout shows the last freed bytes and the recovery count.

**Acceptance Scenarios**:

1. **Given** a recovery ran, **When** the log is read, **Then** one event names the level, whether it
   escalated, each step's name and freed bytes, and the total; no preset name, file name or audio.
2. **Given** a debug build with the test flag, **When** a warning is injected, **Then** the readout
   shows the recovery count and the last freed bytes.

### Edge Cases

- A second warning arrives while a recovery is running (a step posts work that re-enters): it is
  handled after the running one, never nested.
- A warning arrives while the app cannot present frames (background, lock): cache steps still run
  (they are idempotent with PERF-011's suspension); nothing is resumed by the recovery.
- A warning arrives before any visual exists (notice or chooser): steps with nothing to free report
  0 bytes; nothing is created to be freed.
- The idle pictures are still waiting for their last frame's GPU work: they are dropped from the pool;
  the GPU work keeps its own reference, so freeing is safe (PERF-004 fence rule).
- A responder (visual host, renderer) is released before the next warning: it is skipped.
- The user chooses the spectrum again after it was freed: it is created again as on first use.
- Optional work is shed and the app goes to the background: the presentation suspension and the
  memory shedding are independent; resuming presentation does not end the shed early.
- The restore timer fires after the coordinator was replaced (tests): nothing happens.

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-006-R1**: The app MUST receive memory warnings in one place (the memory pressure
  coordinator), which runs every registered recovery step; components MUST NOT observe the warning
  on their own.
- **PERF-006-R2**: Each recovery step MUST be registered by the component that owns the resource,
  with a stable name (no user content), a tier (cache or optional) and an estimate of the bytes it can
  free; steps are held weakly.
- **PERF-006-R3**: On every warning the coordinator MUST run all cache-tier steps, in registration
  order, before any optional-tier step.
- **PERF-006-R4**: A step MUST be idempotent: running it when nothing is held frees 0 bytes and does
  not fail.
- **PERF-006-R5**: The coordinator MUST escalate (also run the optional-tier steps) when the signal is
  critical or a warning arrives within the repeat window after the previous one; optional steps stay
  shed for the cool-down, which each further escalating signal extends; at the end of the cool-down
  each shed step is restored exactly once.
- **PERF-006-R6**: Recovery MUST NOT stop, restart or change the audio source, MUST NOT change the
  chosen visual or the preset playing, and MUST NOT change stored settings or files.
- **PERF-006-R7**: After a recovery the shown visual MUST render its next frame and keep rendering;
  everything freed MUST be rebuilt on demand (lazily) by its owner.
- **PERF-006-R8**: The shared texture pool step MUST free every retired picture (PERF-004-R5) and report
  the retired bytes it held as freed.
- **PERF-006-R9**: The preset warm-up cache step MUST end the warm-up's work and release its thread,
  drawing context, engine and target (PERF-011-R7), cancel a request waiting for its delay, and keep
  the record of presets already warmed; the next request starts it again.
- **PERF-006-R10**: The preset warm-up optional step MUST hold new warm-up requests during the
  cool-down (the newest is remembered) and issue the newest after the restore.
- **PERF-006-R11**: The preset archive step MUST drop its decompressed chunk and report its size.
- **PERF-006-R12**: The idle-visual step MUST release a native spectrum that is not the chosen visual
  (its glow images with it); a spectrum that is chosen is never released.
- **PERF-006-R13**: Releasing GPU resources MUST respect in-flight GPU work: a resource that a submitted
  frame may still use is only released through references that the frame's command buffer keeps, or
  after its work completed.
- **PERF-006-R14**: Each recovery MUST produce a report (level, escalated, per-step freed bytes and
  items, total) and log one diagnostics event carrying only that report's names and counts.
- **PERF-006-R15**: Debug builds MUST offer a launch flag that shows a probe to inject a warning through
  the same path as the system's warning (and a critical signal), and readouts of the recovery count,
  the last freed bytes, the pool's retired bytes and the shown visual's frame count. Release builds
  contain none of it.
- **PERF-006-R16**: Recovery steps MUST run on the main actor; nothing in a recovery waits on the
  audio thread or allocates on a per-frame path afterwards (CMP-001-R9 still holds at a steady size).

### Key Entities

- **Memory pressure level**: warning or critical.
- **Recovery step (responder)**: an owner-registered action with name, tier, reclaimable-bytes estimate,
  a release action returning freed bytes and items, and (optional tier) a restore action.
- **Recovery report**: level, escalated flag, per-step results, total freed bytes, the cool-down end.
- **Recovery counters**: recoveries, escalations, total freed bytes, restores.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PERF-006-S1**: After an injected warning, the shared pool's retired bytes are 0 and the reported
  freed bytes equal what the pool held before (simulator and host tests).
- **PERF-006-S2**: After an injected warning, the shown visual's frame count advances within the
  next second and the source start count is unchanged (1) (simulator UI test on projectM, Camera
  stand-in and Photo).
- **PERF-006-S3**: After an injected warning, the preset warm-up holds no drawing context; a later
  request warms again (simulator test).
- **PERF-006-S4**: After the recovery, 60 frames at a steady size create no picture (pool misses
  unchanged after the first rebuilt frame).
- **PERF-006-S5**: Escalation, cool-down and restore follow PERF-006-R5 exactly in unit tests with a
  test clock (no wall-clock waits).
- **PERF-006-S6** `{device}`: On D1 and D3 under real memory pressure (a memory-hungry companion app,
  or Xcode's Simulate Memory Warning while attached), the app survives, logs a recovery event and
  keeps rendering and playing.

## Assumptions

- The system memory warning that UIKit delivers to the app is the signal; a separate dispatch
  memory-pressure source is decided in the Clarifications.
- Freed bytes are measured where the owner knows them (pool retired bytes, the archive chunk's size)
  and estimated otherwise (the warm-up target's size; the spectrum's glow images are counted as items,
  not bytes). The report says which.
- The shown visual's own resources (its pictures in use, its decoded photo, the camera feed, the video
  decoder, projectM's engine) are the playable scene and are never freed by recovery.
- Simulator results are not device evidence (Constitution X); the device task stays open.
