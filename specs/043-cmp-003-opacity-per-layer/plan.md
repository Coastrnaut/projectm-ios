# Implementation Plan: CMP-003 Opacity per Layer

**Branch**: `feature/cmp-003` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/043-cmp-003-opacity-per-layer/spec.md`

## Summary

Lift CMP-002-R11's opacity restriction. The compositor accepts any stored opacity (already clamped
to 0…1 by `LayerCompositeSettings`) and composites each shown picture with its premultiplied
channels multiplied by the layer's current opacity (a fragment constant in the existing "over"
pass; × 1.0 is exact, so opacity 1 is bit-identical to CMP-002). A layer at current opacity 0 is
not drawn in the composite pass but keeps rendering and stays prepared. Fades: a new CPU value type
`LayerOpacityAnimator` (target, curve, start value, elapsed seconds; `setOpacity(_:duration:curve:)`
throws a typed `LayerOpacityError` for a non-finite target or a negative or non-finite duration,
clamps finite targets; `advance(by:)` sums the frame clock's clamped frame durations; ends exactly
at the target). The compositor keeps one animator per layer record; `apply(_:opacityTransition:makeLayer:)`
(new defaulted parameter, existing calls unchanged) retargets kept layers whose opacity changed,
new layers start at their opacity. Blend modes and transforms stay refused. Opacity sits before the
composite flash guard, so opacity strobes are limited. Recorded as a CMP-003 amendment to ADR-0013.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the build Mac, Xcode 26 in CI).

**Primary Dependencies**: Compositor (CMP-001, CMP-002), Metal. No `Package.swift` change: the
interpolation is a local pure helper (research CMP-003-D3), not ParameterGraph's `LinearMapping`.

**Storage**: N/A.

**Testing**: XCTest via `swift test --package-path Packages/Compositor` (Mac host), the Linux shape
(`--scratch-path .build/linuxshape -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL
-Xswiftc -DANALYSIS_NO_ACCELERATE`), `xcodebuild test -scheme Compositor` on an iOS 27.2 simulator.

**Target Platform**: iOS/iPadOS 26+, macOS 15 host for tests, Linux for the CPU part.

**Project Type**: Swift package library (mobile app module). No app change.

**Performance Goals**: no new allocation per frame (one `setFragmentBytes` of 4 bytes per drawn
layer); one composite draw saved per layer at opacity 0. Device frame cost: CMP-002-T15 `{device}`
covers it (spec CMP-003-S6).

**Constraints**: Public Apple APIs; no wall clock; owner rule 7 budgets; explicit closure types
for Xcode 26; small edits to shared files (`Compositor.swift`, `LayerContract.swift`,
`CompositorShaders.swift`) because SHD-002 edits the package in parallel.

**Scale/Scope**: ≤ 8 layers; about 150 lines of source, 350 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | Metal only; no new API | Pass |
| VI. Modular boundaries | Changes stay in the `Compositor` target; no projectM, ANGLE, capture or app imports | Pass |
| VII. Real-time audio safety | No audio-path change | Pass |
| VIII. Upstream fidelity | projectM untouched | Pass |
| X. Evidence | Host, Linux-shape and simulator tests; device cost stays with CMP-002-T15 | Pass |
| Flash safety (ADR-0011, ADR-0013 decision 6) | Opacity is applied in the composite, before the guard; history never reset by opacity; strobe test (CMP-003-R9) | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/043-cmp-003-opacity-per-layer/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/layer-opacity.md
└── checklists/requirements.md
docs/adr/0013-compositor-layer-protocol.md   # + "Amendment: CMP-003 opacity per layer"
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/
├── LayerOpacity.swift          # NEW (CPU): LayerOpacityCurve, LayerOpacityTransition, LayerOpacityError, LayerOpacityAnimator
├── LayerContract.swift         # + isSupportedByCompositor (normal blend, identity transform)
├── Compositor.swift            # opacity per record; apply(_:opacityTransition:makeLayer:); skip draw at 0
└── CompositorShaders.swift     # cmp_over multiplies by a constant opacity
Packages/Compositor/Tests/CompositorTests/
├── LayerOpacityAnimatorTests.swift   # NEW (CPU, also Linux shape)
├── LayerOpacityCompositeTests.swift  # NEW (GPU 64 × 64)
├── ContractTests.swift               # updated: opacity now supported
├── LayerStackApplyTests.swift        # updated: refusal case uses a transform
└── TwoLayerCompositeTests.swift      # updated: refusal case uses a transform
```

**Structure Decision**: one new CPU file for the fade so it builds on Linux and so SHD-002's edits
to the shared files stay easy to merge; the compositor changes are a few lines each.

## Complexity Tracking

None.
