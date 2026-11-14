# Implementation Plan: QA-006 Render Soak Test

**Branch**: `feature/qa-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/155-qa-006-render-soak/spec.md`

## Summary

A render soak switches QA-002's fixture scenes through CMP-014's `SceneTransitionBus` for a fixed
number of frames with seeded fixture audio and an injected clock, and decides with a plain-Swift
verdict whether GPU memory stayed bounded (least-squares slope of per-cycle high-water marks after a
warm-up, plus a step bound), whether pooled textures came back after every scene change, whether
scene objects were released, and whether any render error happened. Three parts:

1. `RenderSoak.swift` in the `Compositor` target (plain Swift, next to `TexturePoolCore` and
   `RenderHealth`; Linux-tested): tolerance, samples, recorder, slope, verdict, Codable report.
2. `RenderSoakDriver` in QA-002's `SceneRenderHarness` (`Packages/RenderGoldens`): builds each scene
   anew with `GoldenLayerFactory` (shared with `GoldenSceneRenderer` through a small extracted
   `buildScene`), one `TexturePool` for every scene and the bus, crossfades and cuts, measures
   `MTLDevice.currentAllocatedSize`, pool counters and live objects (weak references), counts errors,
   supports an injected leak for the negative controls, writes the JSON report.
3. A projectM preset-switch soak test in `Packages/ANGLERendering` (simulator) using the same
   recorder; `scripts/run_render_soak.py` runs the on-demand long soak (`QA006_SOAK_SECONDS`).

No rendering code changes unless the soak finds a leak (QA-006-R12).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio globals); Python 3 for the script

**Primary Dependencies**: none new. `Compositor` (pool, bus, health), `SceneRenderHarness`
(QA-002), `ProjectMLayer` and `AudioCore`'s `ToneGenerator` (projectM soak)

**Storage**: JSON report in `QA006_REPORT_DIR` or the test's temporary folder (never committed)

**Testing**: XCTest. Host: `swift test --package-path Packages/Compositor --filter RenderSoak` and
`swift test --package-path Packages/RenderGoldens --filter RenderSoak`; Linux shape of both;
simulator QA6 (iOS 27.2): `xcodebuild` RenderGoldens and ANGLERendering schemes with
`-only-testing`. Script tests in `scripts/test_scripts.py`.

**Target Platform**: macOS 15 host and iOS 26+ simulator (tests); device run `{device}` later

**Project Type**: Swift packages (test infrastructure) + a Python script

**Performance Goals**: default soak 60 s simulated (30 s before the 2026-11-14 CI fix) in < 20 s wall on the host (hard limit 60 s);
negative controls < 10 s each; projectM soak < 30 s on the simulator; verdict unit tests < 1 s

**Constraints**: deterministic switch sequence and audio (seeded); no wall-clock assertions; no new
package or dependency edge except ANGLERendering's test target already depending on `Compositor`;
other agents edit `Compositor.swift` in parallel, so the Compositor change is a new file only

**Scale/Scope**: ~5 new Swift files, 1 small refactor in `GoldenSceneRenderer`, 1 script, docs

## Constitution Check

| Principle | Check |
|---|---|
| I. Public Apple APIs only | `MTLDevice.currentAllocatedSize`, Metal, XCTest only; `check_compliance.py` must pass. |
| VI. Modular boundaries | Verdict logic in the package that owns the pool and health; driver in the existing harness; no app code. |
| VII. Real-time audio safety | Not touched (no audio callback code). |
| VIII. Upstream projectM fidelity | Engine untouched; the projectM soak only loads test presets. |
| IX. Pinned dependencies | No new dependency. |
| X. Evidence-based quality | Simulator/host results are labelled as such; the device soak stays `{device}`; negative controls prove the detector. |

Gate: PASS (pre-design and post-design).

## Project Structure

### Documentation (this feature)

```text
specs/155-qa-006-render-soak/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/render-soak.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/Compositor/Sources/Compositor/RenderSoak.swift            # verdict, samples, report (plain Swift)
Packages/Compositor/Tests/CompositorTests/RenderSoakVerdictTests.swift
Packages/RenderGoldens/Sources/SceneRenderHarness/GoldenSceneRenderer.swift   # extract buildScene (no behaviour change)
Packages/RenderGoldens/Sources/SceneRenderHarness/RenderSoakDriver.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/RenderSoakTests.swift        # acceptance, negative controls, bench
Packages/ANGLERendering/Tests/ANGLERenderingTests/ProjectMPresetSoakTests.swift
scripts/run_render_soak.py (+ tests in scripts/test_scripts.py)
Packages/RenderGoldens/README.md (soak section)
```

**Structure Decision**: extend the existing QA-002 package and the Compositor target; no new
package, product or CI step (CI already runs both packages on the host, the simulator and Linux, and
the ANGLERendering simulator step).

## Complexity Tracking

None.
