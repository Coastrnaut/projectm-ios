# Research: QA-006 Render Soak Test

## QA-006-D1: Memory figure

- **Decision**: `MTLDevice.currentAllocatedSize`, sampled after every completed frame; the per-cycle
  high-water mark is the cycle's sample. When the device reports 0 (no such figure on a platform),
  the fallback is the pool's live bytes plus the bytes of resources the soak knows it keeps (the
  injected leak); the report's `memorySource` says which was used.
- **Rationale**: it is the device-wide figure, so it sees every Metal allocation (pool, layer
  generators, photo textures, pipelines' buffers, capture buffers), not only pooled textures. A host
  probe (2026-11-14, Mac Studio) showed it exact to the allocation: each 256 × 192 `rgba16Float`
  texture added 409,600 bytes and releasing them returned the figure to near its start. The iOS 27.2
  Simulator reports 0 (QA6 run, 2026-11-14), so simulator soaks use the pool fallback and also record the
  process footprint (`TASK_VM_INFO.phys_footprint`) per cycle for information (never judged: it includes CPU
  memory). The macOS host (and later the device) is where the device-wide figure is judged.
- **Alternatives**: pool counters only (blind to non-pooled leaks); process RSS (includes CPU memory
  and is noisy; not a GPU figure); Instruments (not automatable in tests).

## QA-006-D2: "Bounded" rule

- **Decision**: warm-up K = 2 cycles; on the per-cycle high-water marks of the measured cycles,
  least-squares slope ≤ ε = max(64 KiB, 0.5 % × warm-up high-water) per cycle, and every measured
  high-water ≤ warm-up high-water + max(2 MiB, 10 %). Fewer than 3 measured cycles → inconclusive.
- **Rationale**: Metal's pipeline caches, the pool's retired set and the first loads of each scene
  settle during the first visits; after that a healthy run is flat. A slope catches a slow leak that
  stays under any fixed bound in a short run; the bound catches a one-time step that a slope over few
  points might average away. A leak of one 128 × 96 `rgba16Float` texture per cycle (~98-131 KB)
  exceeds the 64 KiB floor, so the short soak can detect the smallest leak the negative controls
  inject.
- **Alternatives**: a single absolute ceiling (passes a slow leak, fails a larger device); comparing
  first and last cycle only (noise-sensitive).

## QA-006-D3: Scene switching path

- **Decision**: CMP-014 `SceneTransitionBus` with one shared `TexturePool`; each switch builds the
  next scene as a new `Compositor` from its document (as loading a scene does); crossfades of 0.25 s,
  every third switch a cut. Dwell 30 frames > transition 15 frames, so a transition always ends
  before the next switch and the outgoing scene is released.
- **Rationale**: whole-scene replacement releases every layer, picture and the compositor itself:
  the widest leak surface. The bus's blend target and both release paths (transition end, cut) are
  exercised. In-place `apply` switching is already soaked by PERF-004's `TexturePoolSwitchTests`.
- **Alternatives**: one compositor with `apply` (narrower); the app's coordinator (UI-bound, slow,
  not deterministic).

## QA-006-D4: Pool baseline

- **Decision**: at every dwell end (just before the next switch), record the pool's checked-out
  textures and bytes and the number of live scene compositors. The first record of each scene after
  the warm-up is its baseline; later records of that scene must be equal; live compositors must be 1.
  After the soak drops the bus and every scene, checked-out must be 0 and live scene objects 0.
- **Rationale**: checked-out pictures belong to the live scene only; any texture taken and not
  returned (a leak in a layer, a missed recycle on release) shows as a mismatch at the next visit of
  the same scene.

## QA-006-D5: Errors

- **Decision**: count thrown build/render errors (with the scene and frame), `encodeFrame` returning
  false, command buffers with `error`, and each scene compositor's PERF-014 `health.faultCount`
  (read when the scene is released and at the end). Layer "not ready" fallbacks (photo decode, text
  rasterization) are not faults in PERF-014 and are not counted.

## QA-006-D6: Negative controls

- **Decision**: `RenderSoakLeak.pooledTexturePerCycle` checks one output-sized `rgba16Float` texture
  out of the shared pool at the start of every cycle and keeps it; `.deviceTexturePerCycle` makes
  one with `device.makeTexture` and keeps it. The first must fail `poolBaseline`, `memorySlope`; the
  second `memorySlope`. Both use 3 scenes and 6 cycles to stay under 10 s.

## QA-006-D7: projectM soak

- **Decision**: a test in the ANGLERendering simulator suite: one `ProjectMLayerSource` in one
  `Compositor` at 64 × 64, five presets from `Vendor/projectM/presets/tests` loaded in turn every 40
  frames (`loadPreset(atPath:)`), a 110 Hz + 440 Hz AUD-016 sine written into the layer's PCM ring
  every frame, 1,200 frames (20 s simulated, 6 cycles), the same `RenderSoakRecorder`. Pool baseline
  per preset (one layer: constant), live scenes not applicable (1 layer kept).
- **Rationale**: preset switching keeps the engine and EGL context and replaces the preset's shaders
  and textures, the projectM-specific leak surface. ANGLE has no macOS build, so the simulator is
  the only place it runs in tests.

## QA-006-D8: On-demand long soak

- **Decision**: `RenderSoakBenchTests` (RenderGoldens) and the projectM soak read
  `QA006_SOAK_SECONDS`; the bench is skipped when unset. `scripts/run_render_soak.py --seconds N
  [--simulator UDID] [--angle] [--report-dir DIR] [--dry-run]` runs `swift test --filter` on the host
  or `xcodebuild test -only-testing` on a simulator (environment passed as `TEST_RUNNER_*`), then
  reads the JSON reports and prints each verdict; exit 1 when any fails.
