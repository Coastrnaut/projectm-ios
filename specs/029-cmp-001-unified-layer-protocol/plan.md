# Implementation Plan: CMP-001 Unified Layer Protocol

**Branch**: `feature/cmp-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/029-cmp-001-unified-layer-protocol/spec.md`

## Summary

A layer contract and a minimal Metal compositor, the render boundary of the roadmap's architecture
(item 2), recorded in ADR-0012. The spike (research CMP-001-D5) shows the pinned ANGLE build can
draw into a Metal texture on the simulator, so projectM also becomes a layer source; the app does not
use the compositor yet (CMP-001-R14).

1. **New package `Packages/Compositor`** (the roadmap's proposed layout), one library product
   `Compositor` so CI's `-scheme Compositor` builds and tests every target:
   - Target `Compositor` (depends on `AnalysisFeatures` for the ANL-016 value types and `FlashSafety`
     for the envelope's definition):
     - CPU, every host including Linux: `LayerPictureDescriptor` (size, format, color space, alpha,
       origin), `LayerFrameContext` and `LayerFrameClock` (monotonic time, frame number, clamped
       duration), `LayerAudioContext` and `LayerAudioBuffer` (preallocated bands and events, filled
       from an `AnalysisSubscription` or set directly), `LayerFallback`, `LayerSourceError`,
       `LayerOutcome`, `LayerCompositeSettings` (opacity, blend mode, transform; only the identity
       values accepted, CMP-001-R11), `LayerSlots` (the per-layer picture bookkeeping: which
       picture to render into and which to show, the last-good rule; CMP-001-R6 to R8).
     - Metal, behind `#if canImport(Metal) && !COMPOSITOR_NO_METAL`: the `LayerSource` protocol,
       `Compositor` (owns pictures and the composite, prepares layers on size changes, renders each
       layer, applies fallbacks, composites with premultiplied "over", runs the guard, writes the
       output), `CompositeFlashGuard` (FX-019's envelope on the finished composite, on the GPU),
       shader source as Swift string constants compiled at run time (ADR-0009 decision 3).
   - Target `SpectrumLayers` (depends on `Compositor` and the `VisualGenerators` product):
     `SpectrumLayerSource` wraps any `SpectrumTextureGenerator` (VIS-001, VIS-002) with an optional
     FX-001 `BloomEffect` chain; bands come from the audio context.
   - Test target `CompositorTests`.
2. **`Packages/ANGLERendering`** (extended, ADR-0003's package):
   - `CANGLE`: declarations for `eglQueryString`, `eglGetConfigAttrib`,
     `eglCreatePbufferFromClientBuffer`, `eglCreateImage`/`eglDestroyImage`,
     `eglCreateSync`/`eglDestroySync`, `eglGetCurrentDisplay`/`eglGetCurrentSurface`, the client-buffer
     constants, and four small C helpers (image framebuffer, scissored clear, flush, shared-event copy
     through `eglGetProcAddress`).
   - New target `ProjectMLayer` in the `ANGLERendering` product (depends on `CANGLE`,
     `ProjectMBridge`, `AudioCore`, `Compositor`): `ProjectMLayerSource`. It does not touch
     `ANGLERenderer`, the warm-up or the flash post-pass.
   - Tests: `ClientBufferSpikeTests` (the spike, kept as a regression check), `ProjectMLayerTests`.
3. **Shared files, minimal edits**: `.github/workflows/ios-ci.yml` (add `Compositor` to the five
   package loops); `project.yml`, `AppCoordinator.swift`, `VisualizerView.swift` and
   `scripts/test_scripts.py` are not changed. The app links `ANGLERendering`, whose product now
   includes `ProjectMLayer`; nothing in the app calls it.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency complete), Xcode 27.2; C (CANGLE).

**Primary Dependencies**: Metal, IOSurface-free Metal textures, QuartzCore (public); ANGLE's EGL
(documented extensions queried at run time); the existing `AnalysisFeatures`, `FlashSafety`,
`VisualGenerators`, `ProjectMBridge`, `AudioCore`. No third-party dependency.

**Storage**: none (no persistence: the layer list is fixed in code in this row; SCN-001 adds
documents).

**Testing**: XCTest. CPU contract tests on the macOS host, the Linux shape
(`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`) and
the iOS 27.2 simulator; GPU tests at 64 × 64 on the host (macOS Metal) and the simulator, skipped
(`XCTSkip`) without a Metal device; the spike and the projectM layer test on the simulator only (the
ANGLE xcframework is iOS-only). Budgets (owner rule 7): each test about 1-2 s (≤ 10 s), the package
suite under 1 minute. Deterministic: injected times and analysis values, solid-color layers, no
wall clock.

**Target Platform**: iOS/iPadOS 26+, macOS 15 host for package tests, Linux for CPU parts.

**Project Type**: Swift packages (library contract); the app is unchanged.

**Performance Goals**: per frame, no allocation by this code; one render pass per layer, one over
pass per layer, one compute dispatch (16 threads × 256 samples) for the guard, one output pass. Cost
on devices is a `{device}` measurement (CMP-001-T20).

**Constraints**: Constitution I (public APIs, documented EGL extensions only), VI (no engine or
capture coupling in layers or compositor), VII (no allocation, lock or I/O on the frame path), VIII
(projectM untouched; PCM through the documented API), X (simulator is not device evidence).

**Scale/Scope**: about 1,200 lines of package code, 700 lines of tests, no app change.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: Metal and `makeLibrary(source:)`; ANGLE's EGL extensions `EGL_ANGLE_metal_texture_client_buffer` and `EGL_ANGLE_metal_shared_event_sync`, checked in the extension string before use; extension entry points through `eglGetProcAddress`. No `dlsym`. `check_compliance.py` runs. |
| II-V Capture | Not affected; no compatibility claim. |
| VI Modular boundaries | Pass: `Compositor` and `SpectrumLayers` import neither projectM, ANGLE, capture nor the app; `ProjectMLayer` imports `Compositor` (the contract) and the bridge, and knows nothing of other layers or the analysis bus; C interop stays in `CANGLE`/`ProjectMBridge`. |
| VII Real-time safety | Pass: pictures, pipelines, report and audio storage are created at init or on a size change; per frame only Metal's own command objects (and ANGLE's own sync object inside the projectM layer). |
| VIII projectM fidelity | Pass: no engine change; the layer feeds PCM with `addPCMInterleavedStereo` as `ANGLERenderer` does. |
| IX Dependencies | Pass: none added. |
| X Evidence | Pass: test-first; simulator results reported as such; device cost and correctness are `{device}`. |
| Privacy | Nothing stored, no network, privacy manifest unchanged. |

Post-design re-check: unchanged (pass).

## Rollback

Every step is a separate commit on `feature/cmp-001`. The app does not use the new code, so
reverting any implementation commit cannot change the app's behavior. Reverting the
`ANGLERendering` commits restores `CANGLE.h`/`CANGLE.c` and removes the `ProjectMLayer` target; the
`Compositor` package can be removed with its CI loop entries. No data, settings or formats exist to
migrate.

## Project Structure

### Documentation (this feature)

```text
specs/029-cmp-001-unified-layer-protocol/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/layer-source.md
└── checklists/requirements.md
docs/adr/0012-compositor-layer-protocol.md
```

### Source Code (repository root)

```text
Packages/Compositor/
├── Package.swift
├── Sources/Compositor/
│   ├── LayerPicture.swift          (descriptor, format, color space; Metal mapping)
│   ├── LayerFrameContext.swift     (context and clock)
│   ├── LayerAudioContext.swift     (context and preallocated buffer)
│   ├── LayerContract.swift         (fallback, errors, outcomes, composite settings; LayerSource)
│   ├── LayerSlots.swift            (per-layer picture bookkeeping)
│   ├── Compositor.swift            (Metal)
│   ├── CompositeFlashGuard.swift   (Metal; FX-019 envelope on the composite)
│   └── CompositorShaders.swift     (Metal shader source constants)
├── Sources/SpectrumLayers/SpectrumLayerSource.swift
└── Tests/CompositorTests/
    ├── FrameContextTests.swift, AudioContextTests.swift, LayerSlotsTests.swift, ContractTests.swift
    ├── TwoLayerCompositeTests.swift (GPU), FallbackRenderTests.swift (GPU),
    ├── CompositeFlashGuardTests.swift (GPU), SpectrumLayerTests.swift (GPU)
    └── TestLayers.swift            (solid, failing and probe layers)
Packages/ANGLERendering/
├── Package.swift                   (target ProjectMLayer; dependency ../Compositor)
├── Sources/CANGLE/CANGLE.c, include/CANGLE.h
├── Sources/ProjectMLayer/ProjectMLayerSource.swift
└── Tests/ANGLERenderingTests/ClientBufferSpikeTests.swift, ProjectMLayerTests.swift
.github/workflows/ios-ci.yml       (Compositor in the package loops)
```

**Structure Decision**: a new package for the compositor (roadmap layout; `VisualGenerators` stays
a library of visuals, and later rows add media, camera and text layers that must not depend on the
spectra), plus a new target in the existing ANGLE package for the projectM layer.

## Complexity Tracking

None: no constitution violation.
