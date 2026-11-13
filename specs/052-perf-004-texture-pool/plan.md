# Implementation Plan: PERF-004 Texture Pool

**Branch**: `feature/perf-004` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/052-perf-004-texture-pool/spec.md`

## Summary

A `TexturePool` in the `Compositor` target hands out Metal textures by an exact key (pixel format,
width, height, usage, storage mode, mip levels, sample count, texture type) and takes them back with
a completion signal: the last command buffer their owner encoded with. A returned texture waits until
that buffer's `status` is `.completed` or `.error` (polled when a texture of that key is requested, so
nothing is allocated per frame; research PERF-004-D2). Retired textures (idle or waiting) are capped
by bytes (least recently returned evicted first; default min(128 MiB, recommended working set / 8))
and by idle age in pool frames (default 300); `purge()` frees them all. All bookkeeping lives in a
generic, plain-Swift `TexturePoolCore<Resource, Fence>` that builds and is tested on Linux with fake
textures and fences; the Metal class wraps it with an `NSLock` and adds signposts around allocations.

`Compositor` takes an optional pool (`init(device:layers:texturePool:)`, private pool when nil), checks
out its composite and layer pictures from it, ticks it once per frame, remembers the last command
buffer it encoded, and returns pictures when a layer is removed by `apply`, when the output size
changes and in `deinit`. The app keeps one pool per Metal device (`SharedTexturePool`), used by the
Camera and Photo visual hosts, and purges it on `UIApplication.didReceiveMemoryWarningNotification`.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the build Mac; Xcode 26 / iOS SDK 26.5 in CI).

**Primary Dependencies**: Metal, os (signposts), Foundation (`NSLock`); existing Compositor package.
No new package or dependency.

**Storage**: none.

**Testing**: `swift test --package-path Packages/Compositor` (pool core with fakes; GPU acceptance:
100 switches; steady-size frames; existing CMP tests unchanged); Linux shape (`-Xswiftc
-DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path
.build/linuxshape`); `xcodebuild test -scheme Compositor` once on an iOS 27.2 simulator; app unit
test (`TexturePoolAppTests`) plus the Camera, Photo and NativeVisual UI tests.

**Target Platform**: iOS/iPadOS 26+ (macOS 15 host for package tests; Linux for the core).

**Project Type**: mobile app plus Swift packages.

**Performance Goals**: zero texture allocations per frame at a steady size (CMP-001-R9); pool
operations O(pooled entries) with a few dozen entries at most; the lock is held only for array
bookkeeping (no allocation by Metal under the lock).

**Constraints**: public APIs only; explicit closure types; no wall-clock assertions; owner rule 7
budgets (unit ~1-2 s, suite < 1 min); never the Simulator panel tool; minimal edits to shared files
(MED-002 works on the Compositor and app in parallel).

**Scale/Scope**: about 350 lines of source, 400 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | `MTLDevice.makeTexture`, `MTLCommandBuffer.status`, `allocatedSize`, `recommendedMaxWorkingSetSize`, `OSSignposter`, `UIApplication` notification | Pass |
| VI. Modular boundaries | Pool in the Compositor target (no app, engine or capture import); the app only chooses the shared instance | Pass |
| VII. Real-time audio safety | No audio-path change | Pass |
| VIII. Upstream fidelity | projectM and ANGLE untouched (their GL textures out of scope, recorded) | Pass |
| X. Evidence | Unit, GPU host and simulator tests; device memory plateau left as `{device}` tasks | Pass |
| Privacy | A recycled picture is always cleared by its layer before it is shown (CMP-001 contract); nothing stored | Pass |

Post-design re-check: unchanged, all pass. No ADR needed: no constitution default is overridden;
the decisions are recorded in research.md (PERF-004-D1 to D7).

## Project Structure

### Documentation (this feature)

```text
specs/052-perf-004-texture-pool/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/texture-pool.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/TexturePoolCore.swift     # NEW: key, limits, counters, generic bookkeeping (plain Swift)
Packages/Compositor/Sources/Compositor/TexturePool.swift         # NEW: Metal wrapper (lock, signposts, MTLCommandBuffer fence)
Packages/Compositor/Sources/Compositor/Compositor.swift          # pictures through the pool; return on remove/resize/deinit
Packages/Compositor/Tests/CompositorTests/TexturePoolCoreTests.swift      # NEW: fakes; runs on Linux
Packages/Compositor/Tests/CompositorTests/TexturePoolSwitchTests.swift    # NEW: GPU acceptance (100 switches) and Metal pool tests
Apps/projectM-iOS/Visuals/SharedTexturePool.swift                # NEW: one pool per device, purge on memory warning
Apps/projectM-iOS/Visuals/CameraVisualHost.swift, PhotoVisualHost.swift   # use the shared pool
Apps/projectM-iOS/Tests/TexturePoolAppTests.swift                # NEW: Camera → Photo → Spectrum → Camera bounded
```

**Structure Decision**: the pool sits next to its only user (the compositor) in the `Compositor`
target, so every compositor client gets it without a new dependency.

## Complexity Tracking

None: no constitution violation.
