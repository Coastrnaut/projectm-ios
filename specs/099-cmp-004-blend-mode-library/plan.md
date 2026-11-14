# Implementation Plan: CMP-004 Blend Mode Library

**Branch**: `feature/cmp-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/099-cmp-004-blend-mode-library/spec.md`

## Summary

CMP-004 completes `LayerBlendMode` and teaches the Metal compositor to draw it. In
`Packages/Compositor` (target `Compositor`):

- `LayerBlendMode` becomes a `String`-backed, `CaseIterable` enum with the six names `normal`, `add`,
  `screen`, `multiply`, `overlay`, `difference` (research CMP-004-D1). `isSupportedByCompositor` is
  true for every mode; `CompositorError.unsupportedCompositeSettings` stays for source compatibility
  and is no longer thrown.
- `LayerBlend.swift` (plain Swift, builds on Linux): the sRGB transfer functions, the six separable
  blend functions on encoded straight colours, and `LayerBlend.composite(_:backdrop:source:opacity:)`,
  the premultiplied source-over formula of the contract, in `Double` with typed steps (research
  CMP-004-D2, D3). This is the CPU reference the tests compare the GPU with (CMP-004-R10).
- `CompositorShaders.source` gains `cmp_blend`: reads the backdrop (`texture(1)`), reads or samples
  the picture (identity: per-pixel read; transformed: CMP-005's bilinear inverse mapping), sanitizes
  and applies opacity as `cmp_over`, then evaluates the contract with the same steps as the CPU
  reference. Its pipeline has fixed-function blending off.
- `Compositor`: each record keeps its `blendMode` (set at `init`/`apply`, a kept layer's mode updated
  at `apply` and shown from the next frame). In the composite pass, normal layers keep the exact
  current path; a non-normal layer ends the current encoder, draws `cmp_blend` into the second
  composite texture (load action don't-care: every pixel is written), swaps the two textures and
  re-opens the "over" encoder with load action load (research CMP-004-D4). The second texture comes
  from the texture pool the first time a non-normal layer is drawn at a size, is counted in
  `pictureAllocations`, and is recycled with the composite on a size change and at `deinit`.
  `blendDraws` counts the frame's mode draws (tests, diagnostics).

In `Packages/SceneFormat`:

- Validation warns `unsupportedBlendMode` only when `LayerBlendMode(rawValue:)` is nil.
- `liveState` maps the six names to `LayerBlendMode`; an unknown name maps to `.normal` and is kept in
  the new `SceneLiveState.preservedBlendModes` (instance → string); `init(capturing:)` writes
  `settings.blendMode.rawValue`, or the preserved string while the live mode is still `.normal`
  (CMP-004-R8; research CMP-004-D5). Format version unchanged (no migration-matrix row).
- Tests that used `"screen"` as the example unsupported mode switch to `"softLight"`.

Docs: ADR-0037 (blend functions in sRGB-encoded space, coverage in linear light: it fixes a colour
space the CMP-001 contract left open); ADR-0028 consequence and SCN-001 contract text updated to list
the drawn names; CMP-001's layer contract notes the modes. No UI (spec Clarifications).

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/blend-modes.md](contracts/blend-modes.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26); Metal Shading
Language compiled at run time from the package's Swift constant (ADR-0009 decision 3).

**Primary Dependencies**: Metal. No new dependency.

**Storage**: none (scene format unchanged; `composite.blend` already a string).

**Testing**: `Packages/Compositor`: `LayerBlendReferenceTests` (CPU, hand-checked values, Linux),
`LayerBlendCompositeTests` (GPU: a backdrop × source pattern grid per mode read back from the
half-float composite and an 8-bit sRGB output; opacity; transforms; mode change at apply; normal
unchanged; a GPU timing bench gated by an environment variable). `Packages/SceneFormat`:
`SceneBlendModeTests` (validation, live round trip, unknown preserved, repair report). Existing
suites unchanged, plus RenderGoldens and ImportFuzz re-run.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (CPU reference and SceneFormat).

**Project Type**: SwiftPM packages (no app change).

**Performance Goals**: normal-only stacks: no change (same passes, same pipeline). Each non-normal
layer: one extra full-screen pass and render-pass switch; measured (CMP-004-S6), not asserted.

**Constraints**: public APIs only; explicit closure types; blend equations in typed steps (no long
untyped number-only expressions; Linux and Xcode 26 type-checker); no C stdio; no main-actor mutation
in setUp/tearDown; no wall-clock assertions; unit tests about 1-2 s, suites under 1 minute (owner rule
7). CAM-007 runs in parallel in `CameraLayer`: no edits there.

**Scale/Scope**: 6 source files touched, 3 new test files, docs.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Metal render passes and run-time shader compilation as already used | Pass |
| VI Modular boundaries | All in `Compositor` (render) and `SceneFormat` (document); no layer kind changes | Pass |
| VII Real-time audio safety | No audio code touched | Pass |
| X Evidence | Unit + GPU read-back tests on the Mac and simulator; GPU time measured on the Mac and labelled not device evidence | Pass |
| X ADR for overriding defaults | ADR-0037 records the blend colour space | Pass |
| Accessibility / flashing | Composite flash guard runs after all modes (unchanged order) | Pass |
| No networking, privacy | None added | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/099-cmp-004-blend-mode-library/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/blend-modes.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/
├── LayerContract.swift        # LayerBlendMode: six named cases
├── LayerBlend.swift           # NEW: CPU reference (sRGB transfer, B, composite), Linux
├── CompositorShaders.swift    # cmp_blend fragment, pipeline without blending
├── Compositor.swift           # per-record mode, ping-pong composite, blendDraws
└── LayerStack.swift           # comment only
Packages/Compositor/Tests/CompositorTests/
├── LayerBlendReferenceTests.swift   # NEW (CPU)
├── LayerBlendCompositeTests.swift   # NEW (GPU + bench)
└── ContractTests.swift              # every mode supported
Packages/SceneFormat/Sources/SceneFormat/
├── SceneValidation.swift, SceneLiveState.swift
Packages/SceneFormat/Tests/SceneFormatTests/
├── SceneBlendModeTests.swift        # NEW
├── SceneValidationTests.swift, SceneForwardCompatibilityTests.swift (example mode → softLight)
docs/adr/0037-blend-mode-colour-space.md, docs/adr/0028-scene-document-format.md,
specs/059-scn-001-versioned-scene-format/contracts/scene-document.md,
docs/test-reports/blend-modes.md
```

**Structure Decision**: extend the existing `Compositor` and `SceneFormat` targets; no new target.

## Complexity Tracking

None.
