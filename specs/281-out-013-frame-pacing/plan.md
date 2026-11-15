# Implementation Plan: OUT-013 Frame Pacing per Output

**Branch**: `feature/out-013` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A lock-free, pure `OutputFrameGate` (FrameTiming, Linux-buildable) bounds each visual's frames in flight to 2, never
blocks, records a one-tick back-off after a slow drawable wait, and counts every drop by cause. A `ScreenDisplayLink`
(ANGLERendering, UIKit) builds each visual's display link from the screen of the window its view is in (iOS 27:
`UIWindowScene.displayLink(target:selector:)`; iOS 26: `UIScreen.displayLink(withTarget:selector:)`) and rebuilds it
when the view moves to another screen, keeping the frame-rate range and pause state. The five Metal hosts (native
spectra, camera, photo, video, text) ask the gate before `nextDrawable`, time the wait, and release the slot from the
command buffer's completion handler (`MetalOutputPacing`, app). `ANGLERenderer` asks the gate before rendering,
inserts a GL fence after each presented frame and polls the fences at every tick with a zero timeout
(`ANGLEFrameFences`); its own drawable fetch inside ANGLE is therefore only reached when the GPU has room. The
acceptance proof is a simulation in FrameTimingTests (injected clock, 100 ms output, 120 Hz device ticks, 10 s) plus
an app test (native host in the external stand-in with held completions and a main-actor probe) and an ANGLE test
(held fences).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 / iOS SDK 27.2; CI Xcode 26 / iOS SDK 26.5), C (CANGLE helpers)
**Primary Dependencies**: QuartzCore (`CADisplayLink`, `CAMetalLayer`), UIKit (screen/scene display links), Metal
(command buffer completion), ANGLE GL ES 3.0 sync objects through `eglGetProcAddress` (as `glFinish` today),
Swift `Synchronization` (atomics, as PERF-007)
**Storage**: none (no UserDefaults key, OUT-013-R10)
**Testing**: FrameTimingTests (host + Linux), ANGLERenderingTests and app tests on simulator "OUT13 iPhone 17"
(iOS 27.2); no UI test (no UI change)
**Target Platform**: iOS/iPadOS 26 and 27
**Performance Goals**: per frame: two atomic operations, one closure for the completion handler (Metal), one fence
insert and ≤ 2 zero-timeout polls (ANGLE); nothing allocated in the gate
**Constraints**: owner rule 7 budgets; no wall-clock assertion in the acceptance model; Xcode 26 type-check budget;
`compiler(>=6.4)` guard for the iOS 27 scene API
**Scale/Scope**: 1 package file + test (FrameTiming), 1 file in ANGLERendering + renderer edits + 3 C helpers, 1 app
file + 5 host edits (a few lines each), 1 app test file, ANGLE test file

## Constitution Check

- I. Public Apple APIs only: `CADisplayLink`, `UIScreen`/`UIWindowScene` display links, `CAMetalLayer` properties,
  `MTLCommandBuffer.addCompletedHandler`, GL ES 3.0 `glFenceSync`/`glClientWaitSync`/`glDeleteSync` via
  `eglGetProcAddress` (no dlsym). PASS.
- VI. Modular boundaries: the policy and counts are pure (FrameTiming); UIKit glue in ANGLERendering; Metal glue in
  the app next to the hosts. PASS.
- VII. Real-time audio safety: no audio callback touched; the analysis queue never waits on an output. PASS.
- VIII. Upstream fidelity: no change to projectM or ANGLE sources. PASS.
- X. Evidence: model and app tests are simulator/host evidence only; the real display + heavy preset is `{device}`.
  PASS.

Post-design re-check: unchanged, PASS.

## Project Structure

```text
Packages/Compositor/Sources/FrameTiming/OutputFrameGate.swift                  (new, C1)
Packages/Compositor/Tests/FrameTimingTests/OutputFramePacingTests.swift        (new, model + simulation, S1-S3)
Packages/ANGLERendering/Sources/ANGLERendering/ScreenDisplayLink.swift         (new, C2)
Packages/ANGLERendering/Sources/ANGLERendering/ANGLEFrameFences.swift          (new, C3)
Packages/ANGLERendering/Sources/CANGLE/include/CANGLE.h, CANGLE.c              (fence helpers)
Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift             (link, gate, fences, layer policy)
Packages/ANGLERendering/Tests/ANGLERenderingTests/ANGLEOutputPacingTests.swift (new)
Apps/projectM-iOS/Visuals/MetalOutputPacing.swift                              (new, C4)
Apps/projectM-iOS/Visuals/{NativeSpectrum,Camera,Photo,Video,Text}*Host.swift  (link + gate, a few lines each)
Apps/projectM-iOS/Tests/OutputFramePacingAppTests.swift                        (new, S4)
```

**Structure Decision**: existing packages; Compositor is already in CI's `PKGS_VISUAL`; ANGLERendering is built and
tested as today. No ADR: no default is overridden (the layer's drawable count stays 3; the timeout stays on).

## Complexity Tracking

None.
