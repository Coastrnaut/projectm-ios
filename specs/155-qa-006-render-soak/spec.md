# Feature Specification: QA-006 Render Soak Test

**Feature Branch**: `feature/qa-006` (spec directory `155-qa-006-render-soak`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement QA-006 (Render soak test) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Switch scenes repeatedly using fixture audio for fixed duration."
Acceptance, verbatim: "No unbounded GPU memory growth and no uncaught render error." P1, effort L,
depends on QA-002 (golden render scenes, integrated). Owner rule 7: the default soak is short (20-60 s
of simulated time, under 60 s of wall time); the long soak is an on-demand bench
(`QA006_SOAK_SECONDS=<n>`), run by a script and on a device in the final QA phase."

Identifiers carry the roadmap ID: requirements `QA-006-R1…`, success criteria `QA-006-S1…`, tasks
`QA-006-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `8ac8bd01`)

| Area | Today | Gap for this row |
|---|---|---|
| Scene rendering off screen | QA-002's `GoldenSceneRenderer` (`Packages/RenderGoldens/Sources/SceneRenderHarness`) decodes an SCN-001 document, builds its layers with `GoldenLayerFactory` (photo, material, graph, spectra, text) and renders a few fixed frames through a fresh `Compositor` with an injected presentation clock. 7 canonical scenes in `Packages/RenderGoldens/Scenes`, run settings (seed, seeded audio bands) in `GoldenSceneCatalog`. | One scene per call, a few frames, a new compositor each time: no repeated switching, no memory or error bookkeeping across switches. |
| Image comparison | QA-003's `ImageDiff` (golden tolerance). | Not needed for a soak (no golden output); not reused. |
| Scene changes | CMP-002 `Compositor.apply(_:)` (stack switch inside one compositor) and CMP-014 `SceneTransitionBus` (crossfade between two whole scene compositors on one transition clock, blend target from the pool). | Tested for single transitions only. |
| GPU memory bookkeeping | PERF-004 `TexturePool` / `TexturePoolCounters` (checked out, retired, live, misses); the app's `SharedTexturePool` (one pool per device); `TexturePoolSwitchTests` checks 100 switches keep the live count bounded on one compositor. `MTLDevice.currentAllocatedSize` is not read anywhere. | No check across whole scenes, transitions and every layer kind; no device-level memory figure; no trend check. |
| Render errors | PERF-014 `RenderHealth` on each compositor (fault count, state, recoveries); command buffer `error`. | Never summed over a long run. |
| projectM | `ProjectMLayerSource` (ANGLE, simulator tests in `Packages/ANGLERendering`), presets in `Vendor/projectM/presets/tests`; `PresetWarmUpMemoryTests` covers warm-up memory pressure steps. | No repeated preset switching with memory and error checks. |
| Fixture audio | `GoldenAudio.seededBands` (per-frame bands from a seed) for compositor layers; AUD-016 `ToneGenerator` (sines, sweeps) for PCM. | — |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where does the soak live? → A: The scene soak driver lives in QA-002's `SceneRenderHarness` (`Packages/RenderGoldens`), reusing `GoldenLayerFactory`, the scene catalog and its fixture audio; the pass/fail bookkeeping (samples, slope, verdict, report) is plain Swift in the `Compositor` target next to `TexturePoolCore` and `RenderHealth`, so it builds and is tested on Linux and both the scene soak and the projectM soak (`Packages/ANGLERendering`, which already depends on `Compositor`) use the same rule. No new package.
- Q: How are scenes switched? → A: Through CMP-014's `SceneTransitionBus` with one shared `TexturePool`: each switch builds the next scene as a new compositor (new layers, as loading a scene does) and crossfades to it over a short transition; every third switch is a cut. This covers both scene-change paths that release a whole scene (transition end and cut) and the bus's pooled blend target.
- Q: Which scenes? → A: Six of QA-002's seven canonical scenes, in a fixed order: photo-gradient, text-caption, spectrum-circular, material-plasma, graph-hue-rings, stack-composite (strobe-guarded adds nothing a soak checks). One pass over all six is a "cycle". The projectM preset switch soak runs separately on the simulator (ANGLE has no macOS host build), cycling five test presets in one `ProjectMLayerSource`.
- Q: What is the fixture audio? → A: The scene soak feeds each frame `GoldenAudio.seededBands(count: 32)` from the soak seed (deterministic, varies every frame); the projectM soak writes an AUD-016 two-tone sine (110 Hz + 440 Hz) into the layer's PCM ring every frame.
- Q: What is "time"? → A: An injected clock: frame n is presented at start + n × 1/60 s. Simulated duration = frames / 60. Frames are rendered as fast as the GPU completes them (each frame is committed and awaited), so the soak runs faster than real time; nothing asserts wall-clock time.
- Q: What is measured? → A: Per frame: `MTLDevice.currentAllocatedSize` (the device-level figure; when the platform reports 0, the pool's live bytes plus a tracked estimate stand in, and the report says which), the pool's counters, render errors. Per cycle: the high-water mark of the memory figure, the pool's checked-out textures and bytes at the end of every scene's dwell, the number of scene compositors and layers still alive (weak references) and the counters of misses (textures Metal created).
- Q: What is a render error? → A: Any thrown error from building or rendering a scene, a frame the bus could not encode, a command buffer that ended with an error, and every fault the PERF-014 health records count (each scene's compositor `health.faultCount`). The pass rule needs zero of all; the first few are listed in the report.
- Q: What is "bounded"? → A: After a warm-up of K = 2 cycles: (1) the least-squares slope of the per-cycle memory high-water marks over the remaining cycles is at most ε = max(64 KiB, 0.5 % of the warm-up high-water) per cycle; (2) no later cycle's high-water exceeds the warm-up high-water plus a tolerance of max(2 MiB, 10 %). At least 3 measured cycles are needed after the warm-up, or the verdict is "inconclusive" (a failure in tests). The slope catches a slow leak a single absolute bound would miss; the bound catches a step.
- Q: What does "pool checkouts return to baseline" mean? → A: At the end of each scene's dwell (no transition running), the pool's checked-out texture count equals the count recorded the first time that scene finished its dwell after the warm-up; exactly 1 scene compositor is alive at the end of a dwell (the outgoing one of a transition has been released); after the soak releases everything, nothing is checked out.
- Q: How is the detector proven? → A: Negative controls in the normal suite: the same short soak with an injected leak — (a) a fake resource that checks a texture out of the pool per cycle and never returns it, and (b) one that keeps a device texture (not pooled) per cycle — must fail with the expected rule (pool baseline and memory slope for (a), memory slope for (b)).
- Q: How short is the default? → A: 30 s simulated (1,800 frames at 128 × 96, dwell 30 frames = 0.5 s, transition 0.25 s: 60 switches, 10 cycles), well under 60 s wall time on the host; the projectM soak runs 20 s simulated (1,200 frames at 64 × 64, a preset switch every 40 frames, 5 presets: 30 switches, 6 cycles) on the simulator. Each negative control runs a shorter soak (6 cycles).
- Q: How is the long soak run? → A: `QA006_SOAK_SECONDS=<n>` turns on a bench test (skipped otherwise) that runs n simulated seconds with the same rule and writes the report; `scripts/run_render_soak.py` runs it on the host or a named simulator (passing the variable through as `TEST_RUNNER_QA006_SOAK_SECONDS`) and prints the verdict. The device run is a FINAL-stage task `{device}`.
- Q: Where does the report go? → A: A JSON report (configuration, per-cycle samples, slope, bounds, errors, verdict) is written to `QA006_REPORT_DIR` when set, else to the test's temporary folder, and attached to the test; the script collects it.
- Q: Does the default soak run in CI? → A: Yes. It is an ordinary RenderGoldens test, so CI runs it on the macOS host and the iOS simulator jobs that already test the package (skipped without a Metal device, and compiled out in the Linux shape, where the verdict tests still run); the projectM soak runs in CI's existing ANGLERendering simulator step. The long soak never runs in CI.
- Q: Which compositor settings does the soak use? → A: The app's defaults: render caching (CMP-013) on, Reduce flashing on, content scale 2, standard effect order, each scene's own effect settings when it has them. Caching on is the path that keeps the most state between frames, so it is the one a leak would hide in.
- Q: How long may each soak test take? → A: The default scene soak under 20 s wall time on the host (the owner's 10 s unit-test ceiling does not fit a soak; QA-006-R8's 60 s is the hard limit), each negative control under 10 s (6 cycles, 3 scenes), the projectM soak under 30 s on the simulator. The report records wall time and frames per second so a slow run is visible, but no test asserts wall time.

## User Scenarios & Testing *(mandatory)*

The "users" are developers and agents who change the renderer, and the owner who reads the final QA
report.

### User Story 1 - A short soak in every test run proves no leak and no render error (Priority: P1)

A developer runs the RenderGoldens suite. A short soak switches the fixture scenes many times with
fixture audio and passes only when there was no render error, memory stayed bounded and pooled
textures came back after every scene change.

**Why this priority**: It is the row's acceptance.

**Independent Test**: Run the soak test alone; it passes on the macOS host and the simulator within
the unit-test budget and writes a report.

**Acceptance Scenarios**:

1. **Given** the six fixture scenes and fixture audio, **When** the default soak runs, **Then** it
   reports zero render errors, a memory slope within ε, every later high-water within the bound, and
   pool checkouts at baseline at every dwell end.
2. **Given** the soak finished, **When** everything is released, **Then** the pool has nothing checked
   out and no scene compositor is alive.

---

### User Story 2 - The detector catches a leak (Priority: P1)

A test author injects a deliberate leak; the soak fails and names the rule.

**Why this priority**: A soak that cannot fail proves nothing.

**Independent Test**: The negative-control tests.

**Acceptance Scenarios**:

1. **Given** a fake resource that keeps one pooled texture per cycle, **When** the soak runs, **Then**
   the verdict fails on the pool baseline and the memory slope.
2. **Given** a fake resource that keeps one device texture per cycle, **When** the soak runs, **Then**
   the verdict fails on the memory slope.
3. **Given** synthetic samples (flat, flat with noise, a ramp, a single step), **When** the verdict is
   computed, **Then** flat and noisy pass, the ramp fails the slope and the step fails the bound.

---

### User Story 3 - projectM preset switching soaks too (Priority: P2)

On the simulator, one projectM layer switches through test presets with fixture PCM; no render error
and bounded memory.

**Independent Test**: The ANGLERendering simulator suite's soak test.

---

### User Story 4 - A long soak runs on demand (Priority: P2)

The owner or an agent runs `scripts/run_render_soak.py --seconds 600` on the host, a simulator or (in
the final QA phase) a device and gets a JSON report and a verdict.

### Edge Cases

- A platform where `currentAllocatedSize` is 0: the pool's live bytes plus the leak-tracking estimate
  stand in; the report names the source.
- Too few cycles for a slope: "inconclusive", never a pass.
- A scene that fails to build: counted as a render error with its message; the soak continues with the
  next scene.
- Asynchronous loading (photo decode, text rasterization) must not count as an error: a layer's
  "not ready" fallback is not a fault.
- A transition interrupted by the next switch (dwell shorter than the transition): the bus snaps; the
  soak's defaults keep dwell > transition.
- `QA006_SOAK_SECONDS` unset, empty, non-numeric or ≤ 0: the bench test is skipped.

## Requirements *(mandatory)*

### Functional Requirements

- **QA-006-R1**: A soak driver MUST render a fixed list of fixture scenes off screen, switching scene
  every N frames for a fixed number of frames, with an injected presentation clock and per-frame
  fixture audio; the same configuration MUST produce the same sequence of scene switches.
- **QA-006-R2**: Scene switches MUST go through the transition bus (crossfades and cuts) with every
  scene compositor and the bus sharing one texture pool, and each switch MUST build the scene anew from
  its document.
- **QA-006-R3**: The driver MUST record per frame the device's allocated GPU memory (or the stated
  fallback) and per cycle its high-water mark, the pool's checked-out count and bytes at every dwell
  end, the textures the pool created, and the number of live scene objects.
- **QA-006-R4**: The driver MUST count every render error: thrown build or render errors, unencoded
  frames, command buffer errors and PERF-014 health faults; it MUST NOT let an error escape the soak
  uncounted.
- **QA-006-R5**: The verdict MUST pass only when there are zero render errors, the post-warm-up memory
  slope is ≤ ε, every post-warm-up high-water is ≤ warm-up high-water + tolerance, pool checkouts equal
  each scene's baseline at every dwell end, live scene objects stay within their limits, and the pool
  is empty after release; otherwise it MUST fail naming every failed rule, or be "inconclusive" with
  fewer than 3 measured cycles.
- **QA-006-R6**: The verdict logic MUST be plain Swift that builds and is tested on Linux.
- **QA-006-R7**: The soak MUST write a JSON report with its configuration, per-cycle samples, slope,
  bounds, errors and verdict.
- **QA-006-R8**: The default soak in the normal suite MUST simulate 20-60 s and finish in under 60 s
  wall time on the host (target under 20 s; negative controls under 10 s each), using the app's default
  compositor settings (render caching on, Reduce flashing on); wall time is reported, never asserted.
- **QA-006-R9**: A long soak MUST run on demand with `QA006_SOAK_SECONDS=<n>` (skipped otherwise), and
  a script MUST run it on the host or a simulator and print the verdict and report path.
- **QA-006-R10**: Negative controls MUST show that an injected per-cycle leak (pooled and non-pooled)
  fails the soak.
- **QA-006-R11**: A projectM preset-switch soak MUST run on the simulator in the ANGLERendering suite
  with the same verdict rule, kept short.
- **QA-006-R12**: Rendering code MUST NOT change unless the soak finds a real leak; a found leak MUST be
  fixed, reported and covered by a regression test.

### Key Entities

- **Soak configuration**: scenes, resolution, frames, dwell, transition, warm-up cycles, tolerances,
  seed, injected leak.
- **Cycle sample**: memory high-water, pool checked-out textures and bytes, misses, live objects.
- **Soak report**: configuration, samples, errors, slope, bounds, verdict and failed rules.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **QA-006-S1**: The default scene soak (30 s simulated, 60 switches) passes on the macOS host and the
  iOS 27.2 Simulator with zero render errors in under 60 s wall time each.
- **QA-006-S2**: Both negative controls fail with the expected rules.
- **QA-006-S3**: The verdict unit tests (flat, noisy, ramp, step, too few cycles, errors, baseline
  drift) pass on the host and the Linux shape.
- **QA-006-S4**: The projectM soak (20 s simulated, 30 preset switches) passes on the simulator.
- **QA-006-S5**: `scripts/run_render_soak.py` runs a long soak on demand and its script tests pass.
- **QA-006-S6** `{device}`: a long soak (≥ 10 minutes simulated) on D1 passes in the final QA phase.

## Assumptions

- Simulator and host results are not device evidence; the device soak stays open for the final QA
  phase.
- The soak is a test-only harness: no app code and no new UserDefaults key.
- Graph pipelines compiled per device may be cached by Metal; that cache is warm-up, which is why the
  bound starts after K cycles.
