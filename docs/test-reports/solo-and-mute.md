# Test report: CMP-012 Solo and mute

Feature: `specs/112-cmp-012-solo-and-mute` (branch `feature/cmp-012`). No ADR (no default overridden,
no saved format change; decisions in the spec's Clarifications and research CMP-012-D1 to D6). Host:
the Mac Studio (build machine of record), Xcode 27.2, Swift 6.4.2. Simulator results are not device
evidence; no device run was made.

## Audit (2026-11-14, commit `35179456`)

Layers have **no enabled flag**; a layer is hidden today only by opacity 0 or a switched-off CMP-011
group. The saved enable flags are therefore the groups' `enabled`; the layers' saved visibility is
their saved opacity. No screen edits a layer stack (the visual hosts build fixed stacks), so there is
no UI, no DEBUG probe and no launch argument; everything is tested at the package level.

## Baseline (CMP-012-T01, before any change)

`swift test --package-path Packages/Compositor`: 318 tests, 4 skipped, 0 failures, 11.0 s.
`swift test --package-path Packages/SceneFormat`: 110 tests, 0 failures, 2.2 s.

## Design in one paragraph

`LayerSoloMute` (Compositor, plain Swift) is a transient overlay kept beside the `LayerStack`, never in
it: soloed and muted layers and groups. A layer is drawn when its existing conditions hold (picture,
opacity > 0, group on with opacity > 0) and it is not muted, its group is not muted, and no solo is
active or it or its group is soloed. Solos combine as a union; mute wins over solo, and a muted solo
still counts as active; IDs not in the stack are ignored. The compositor resolves the overlay into one
flag per layer at `apply` and `setSoloMute`; a hidden layer keeps rendering every frame and is only
left out of the composite (and of its group's isolation decision). Documents are built from the stack
or the app's `SceneInputs`, so scenes, autosave, undo, show cues and archives cannot carry it.

## Results

| Check | Result |
|---|---|
| `LayerSoloMuteTests` (CPU rule, 8 tests) | pass, 0.002 s; host and Linux shape |
| `LayerSoloMuteCompositeTests` (8 GPU tests + opt-in bench) | pass, 0.19 s |
| `SceneSoloMuteTests` (document + GPU acceptance, 2 tests) | pass, 0.07 s |
| Compositor full suite | 335 tests, 5 skipped (benches), 0 failures, 12.1 s |
| SceneFormat full suite | 112 tests, 0 failures, 7.2 s |
| Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) | Compositor 184, SceneFormat 111, 0 failures |
| RenderGoldens / ImportFuzz / ShowControl / SceneArchive | 39 / 15 / 31 / 27, 0 failures (goldens unchanged) |
| App unit tests (`projectM-iOSTests`, own iOS 27.2 simulator, created and deleted) | 498 tests, 0 failures, 21.5 s test time (140 s wall with build) |
| Repository checks | compliance, docs (985 files), motion policy, permission catalog, status events OK; script tests 153 OK (1 skipped) |
| PosterBoard reports during the simulator run | 0 new |

### The acceptance (CMP-012-S1)

`SceneSoloMuteTests.testSoloIsolatesTheSelectedLayerWithoutChangingTheSavedScene`: a scene (#1 red,
#2 green at opacity 0.5, #3 blue, #4 white in a switched-off group) is loaded into a live stack and the
real compositor. Before: every pixel blue. Solo #2: every pixel (0, 0.5, 0, 0.5) — only #2, at its saved
opacity — with flash gain 1. `SceneDocument(capturing:)` during the solo encodes to the same bytes as
the original, every saved opacity and the group's `enabled` are unchanged, and `appliedStack` equals the
loaded stack. Soloing #4 as well shows nothing of it (solo never overrides a saved flag). Clearing
restores the frame from before bit for bit; the scene's bytes are still identical; no layer was
prepared again. `testSoloAndMuteNeverChangeTheDocumentCaptureOrUndoHistory` repeats the document part on
the CPU (also on Linux) and shows `SceneHistory.record` returns `.unchanged` (no undo step) during and
after.

### Mute, combinations and groups (S2-S4)

References are drawn by the same compositor from the stack the overlay should equal, so equality is bit
for bit: solo of the middle of three overlapping boxes = a stack of that box alone; two solos = both in
stack order; mute of the top = the stack without it (three frames, the muted layer `.rendered` each
time); solo plus mute of one layer = transparent; group solo = the group's layers alone; solo of a child
of a moved group at opacity 0.5 = that group holding only the child (one isolated draw, green 0.5);
solo of the normal child of an opacity-1 group whose other child is screen-mode = the child alone, now
flattened (0 isolated, 0 blend draws); group mute = the stack without the group, members still
rendering; switched-off group with a soloed child = transparent. Every clear or un-mute restores the
earlier frame bit for bit. Across mute, solo and clear: 0 layer preparations, 0 picture allocations,
0 texture pool misses (no source restart). An opacity fade keeps advancing while its layer is muted and
the layer reappears at the fade's current value at once.

### GPU time (CMP-012-S6; Mac, not device evidence)

`CMP012_BENCH=1 swift test -c release -Xswiftc -DDEBUG --package-path Packages/Compositor --filter LayerSoloMuteCompositeTests/testBench`,
8 transformed layers at opacity 0.8, 1920 × 1080, `bgra8Unorm_srgb`, 120 measured frames:

| Case | Median (ms) | p95 (ms) | Hidden layers |
|---|---|---|---|
| 8 layers, 0 muted | 0.490 | 1.136 | 0 |
| 8 layers, 4 muted | 0.329 | 0.377 | 4 |

Muting saves the composite draws; the hidden layers' own render work continues (by design, for an
instant return; for camera and video that is their usual decode and render cost).

## Not verified

No device run (D1-D3). No UI (none exists to drive). The bench is a Mac measurement only.
