# Feature Specification: PERF-004 Texture Pool

**Feature Branch**: `feature/perf-004` (spec directory `052-perf-004-texture-pool`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement PERF-004 (Texture pool) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Reuse intermediate textures with
lifecycle and memory caps." Acceptance, verbatim: "Hundred scene switches do not grow live texture
count indefinitely." P0, effort L, depends on CMP-001 (integrated). Implementation: Metal counters,
os_signpost, MetricKit where appropriate. Verification: performance unit + simulator + physical
device last stage. Implement only PERF-004; PERF-006 (memory warning recovery) builds on it."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `PERF-004-R1…`, success criteria `PERF-004-S1…`, tasks `PERF-004-T01…`.
Requirements of other features are cited by their own IDs: CMP-001-R6 and R9 (the compositor owns
every picture; nothing is created per frame at a steady size), CMP-002 (stacks applied between
frames, removed layers released), OUT-001-R7 (resize for the external display), PERF-006 (memory
warning recovery, a later row).

## Baseline: what exists today (audit of 2026-11-13, commit `bc435fb`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Compositor pictures | `Compositor` creates the composite and one or two pictures per layer (16-bit float RGBA, output size) at the first frame, at every output size change and for every layer a stack adds. Removed layers' pictures and the old size's pictures are dropped. | Nothing is reused: every scene switch and every resize allocates full-size pictures again, and nothing counts what is alive. |
| App visuals | The Camera and Photo visuals each build their own compositor when the user switches to them and release it when the user leaves. | A switch back and forth allocates a new set of full-screen pictures each time; no cap, no counter. |
| Layer resources | Layers create their own working textures in `prepare` (camera picture cache, decoded photo, effect-chain and bloom images in VisualGenerators). They are released with the layer. | Out of this row's reuse scope (see Assumptions); measured by the whole-device allocation check. |
| Memory warnings | No component frees GPU caches on a memory warning. | Nothing to purge. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What are the default caps for idle pictures? → A: Idle and waiting bytes are capped at the smaller of 128 MiB and one eighth of the GPU's recommended working set, and a picture idle for 300 pool frames (about 5 s at 60 fps) is freed; both are configurable per pool. 128 MiB holds about five full-screen 16-bit pictures of an iPhone 15 (1179 × 2556, about 24 MB each), enough to serve one whole visual switch from reuse. Rejected: an uncapped pool (a leak by design); a cap of zero (no reuse across switches); a time-based age (wall-clock dependent, untestable without sleeping).
- Q: How does the pool know that the GPU no longer uses a returned picture? → A: Each return carries a completion signal: the last command buffer the returning compositor encoded with. The picture waits until that command buffer reports completed (or failed); a return made before any frame was encoded is reusable at once. The pool polls the signal when it looks for a picture, so nothing is allocated per frame. Rejected: a fixed latency of N frames (unsafe when the GPU stalls); a completion handler added to every frame's command buffer (a closure allocated per frame, against CMP-001-R9).
- Q: Which visuals share one pool? → A: One pool per GPU device in the app, used by every compositor the app builds (today the Camera and Photo visuals). The native spectra and projectM do not draw through the compositor and keep their own resources. Tests and harnesses that build a compositor without a pool get a private one, so existing behaviour and counters are unchanged. Rejected: a pool per visual (no reuse across switches, which is the row's point); a process-wide global hidden in the Compositor package (shared state the package cannot reason about).
- Q: Are the effect-chain and bloom images (VisualGenerators) and layers' own content textures pooled too? → A: No, not in this row. They are created once per size in a layer's `prepare` and released with the layer, so they cannot grow across switches; pooling them would make VisualGenerators depend on the Compositor package (or move the pool to a new package) for a small gain. The acceptance test also measures the GPU device's whole allocated size across the 100 switches, so growth there would be caught; a debug-only tally of textures created outside the pool is not built (it would need wrappers in five packages to see releases). Rejected for now: a shared lower-level pool package (revisit with PERF-006).
- Q: What triggers a purge? → A: The system memory warning that the app already receives (`UIApplication.didReceiveMemoryWarningNotification`): the app purges its shared pool on it. A purge also happens implicitly when the pool is released. No separate memory-pressure source is added (one signal is enough; PERF-006 owns broader recovery). Rejected: purging on every visual switch (defeats reuse); a dispatch memory-pressure source (duplicate signal on iOS).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Switching scenes many times does not grow memory (Priority: P1)

A performer switches between visuals and edits the layer stack many times during a set (Camera,
Photo, spectra, back to Camera; layers added and removed; the external display plugged in and out).
The app's GPU memory for intermediate pictures settles after the first few switches and stays there,
however long the set lasts.

**Why this priority**: It is the row's acceptance; unbounded growth ends in the system terminating
the app mid-performance.

**Independent Test**: A test applies 100 alternating layer stacks with different layer sets to a
compositor, resizes the output every 10 switches and renders a frame after each switch; the count
and bytes of live intermediate pictures plateau after warm-up and never exceed a fixed bound.

**Acceptance Scenarios**:

1. **Given** a compositor that has rendered one frame, **When** 100 scene switches (alternating
   stacks, a resize every 10th switch) each render a frame, **Then** the live picture count and bytes
   never exceed a fixed bound and are the same at switch 100 as after warm-up.
2. **Given** the app's Camera, Photo and Spectrum visuals, **When** the user switches between them
   repeatedly, **Then** the pictures of a closed visual are reused by the next one instead of
   allocating new ones, and the live count stays bounded.
3. **Given** a steady output size and an unchanged stack, **When** 60 frames render, **Then** no
   picture is created (CMP-001-R9 still holds).

---

### User Story 2 - Reuse never corrupts a frame (Priority: P1)

A picture returned to the pool is never handed to a new user while the GPU may still be reading or
writing it for an earlier frame, so a switch never shows a torn or foreign picture.

**Why this priority**: Reusing a picture too early shows content from another layer (for example a
camera picture inside a photo layer) for a frame: a correctness and privacy defect.

**Independent Test**: Pool tests with a fake GPU-completion signal: a returned picture is not
handed out until its frame is reported complete; after completion it is.

**Acceptance Scenarios**:

1. **Given** a picture returned while its last frame is still on the GPU, **When** the same kind of
   picture is requested, **Then** a different picture is provided.
2. **Given** that frame then completes, **When** the same kind is requested again, **Then** the
   returned picture is reused.

---

### User Story 3 - Idle pictures are capped and freed (Priority: P2)

Pictures waiting in the pool use at most a fixed amount of memory, are freed when unused for a while,
and are all freed on a system memory warning.

**Why this priority**: A pool without caps is itself a leak; memory warnings must be answered.

**Independent Test**: Pool tests: returning pictures past the byte cap evicts the least recently used
first; pictures idle longer than the age limit are evicted; a purge empties the pool.

**Acceptance Scenarios**:

1. **Given** a pool at its idle-byte cap, **When** another picture is returned, **Then** the least
   recently returned pictures are freed until the idle bytes are within the cap.
2. **Given** an idle picture, **When** the age limit passes without anyone asking for it, **Then** it
   is freed.
3. **Given** a memory warning, **When** the app receives it, **Then** every idle and waiting picture
   is freed; pictures in use are untouched and the visual keeps playing.

### Edge Cases

- A layer set changes while a frame is still on the GPU: the removed pictures wait for that frame;
  the new layers get other pictures.
- The output is resized repeatedly (external display renegotiation): the old size's pictures go to
  the pool and are evicted by age or cap if that size never returns.
- A single picture larger than the idle cap is returned: it is freed at once, not kept.
- A frame is never committed (encoding failed): its waiting pictures are never reused but are freed
  by the cap, the age limit or a purge.
- Two compositors share the pool on the same device (a visual opening while the previous one closes):
  both are served; nothing is handed out twice.
- A compositor is released with pictures in use: they are returned (waiting for its last frame).
- A recycled picture holds an earlier frame's content: layers clear their picture before drawing
  (CMP-001 contract) and an unrendered picture is never shown, so stale content is never visible.

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-004-R1**: The app MUST provide a texture pool that hands out intermediate pictures by their
  full description (pixel format, width, height, usage, storage, mip levels, sample count, kind) and
  reuses a returned picture only for an identical description.
- **PERF-004-R2**: A returned picture MUST NOT be handed out again until the last GPU work that may use
  it has completed: each return carries the last command buffer its owner encoded with, and the
  picture waits until that buffer reports completed or failed (a return before any frame is
  reusable at once). Checking this MUST allocate nothing.
- **PERF-004-R3**: Idle and waiting pictures MUST be capped by total bytes (configurable; default the
  smaller of 128 MiB and one eighth of the GPU's recommended working set); past the cap, the least
  recently returned are freed first, and a single picture larger than the cap is freed at once.
- **PERF-004-R4**: Idle pictures MUST be freed after a configurable number of pool frames without use
  (default 300).
- **PERF-004-R5**: A purge MUST free every idle and waiting picture at once, and the app MUST purge its
  shared pool on the system memory warning; pictures in use are not affected.
- **PERF-004-R6**: The pool MUST count live pictures and bytes (in use plus pooled), pooled pictures
  and bytes, hits, misses, evictions and purges, readable by tests and diagnostics, and allocate
  nothing per frame at a steady size.
- **PERF-004-R7**: The compositor MUST take every composite and layer picture from the pool and return
  them when a layer is removed, when the output size changes and when the compositor is released;
  CMP-001-R9 (no picture created per frame at a steady size) MUST still hold.
- **PERF-004-R8**: The app's compositor visuals (Camera, Photo) MUST share one pool per GPU device, so a
  visual switch reuses the previous visual's pictures. A compositor built without a pool uses a
  private one.
- **PERF-004-R9**: The pool MUST be safe to use from more than one thread (visuals sharing it), with
  short, bounded critical sections.
- **PERF-004-R10**: The pool's bookkeeping (keys, caps, eviction order, completion rule, counters)
  MUST be plain code testable without a GPU, including on Linux.
- **PERF-004-R11**: Picture allocations by the pool SHOULD be marked for Instruments (signpost
  intervals) so device traces show when and how often allocation happens.
- **PERF-004-R12**: The feature MUST use only public, documented platform APIs (Constitution I).

### Key Entities

- **Picture description (key)**: what makes two pictures interchangeable.
- **Pool entry**: a picture with its key, its size in bytes, its state (in use, waiting for GPU
  completion, idle) and the frame it was returned at. "Retired" means returned: waiting or idle.
- **Completion signal**: tells whether the last GPU work that may use a returned picture has
  finished.
- **Pool limits**: idle-byte cap and idle-age limit.
- **Pool counters**: live, pooled, hits, misses, evictions, purges.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PERF-004-S1**: Over 100 scene switches with a resize every 10th, live intermediate pictures and
  bytes never exceed a fixed bound and are identical at switch 100 and after warm-up (the acceptance).
- **PERF-004-S2**: At a steady size and stack, 60 frames create 0 pictures.
- **PERF-004-S3**: A returned picture is reused 0 times before its frame completes, in 100% of the
  pool tests.
- **PERF-004-S4**: Idle bytes never exceed the cap after a return; age eviction and purge leave 0
  idle pictures of the affected kind.
- **PERF-004-S5**: Switching the app's visuals Camera → Photo → Spectrum → Camera repeatedly keeps
  live pictures bounded, and the second and later switches are served by reuse.
- **PERF-004-S6**: On D1 and D3, live GPU memory over 100 visual and stack switches plateaus (device
  stage, owner's hands).

## Assumptions

- Scope is the compositor's intermediate pictures (composite and layer pictures), which are the
  full-screen 16-bit allocations repeated on every switch. Layers' own content resources (camera
  picture cache, decoded photo, effect-chain and bloom images) and projectM/ANGLE's GL textures keep
  their current lifecycle (created in `prepare`, released with the layer); the acceptance test also
  checks whole-device GPU allocation so growth there would be seen.
- Memory-warning recovery beyond freeing the pool (dropping optional layers, caches elsewhere) is
  PERF-006.
- Simulator results are never device evidence (Constitution X); device measurements are `{device}`
  tasks left open.
