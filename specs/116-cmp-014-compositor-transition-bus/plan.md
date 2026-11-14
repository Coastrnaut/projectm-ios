# Implementation Plan: CMP-014 Compositor Transition Bus

**Branch**: `feature/cmp-014` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/116-cmp-014-compositor-transition-bus/spec.md`

## Summary

A `SceneTransitionBus` in the Compositor package shows one scene output (a CMP-001 compositor with its
CMP-002 stack) and blends two of them during a transition, driven by one `SceneTransitionClock` that
sums the presentation-time durations of the frames shown.

- **Compositor split (focused edit).** `Compositor.composite(into:…)` keeps its behaviour; its body is
  split into a private frame routine that runs the stack phase and hands the finished composite to a
  closure. `composite(into:)` passes the existing guard + output closure; the new
  `encodeScene(width:height:commandBuffer:…) -> MTLTexture?` passes a closure that only returns the
  composite. Render health, caching, pool ticks and the command-buffer watch run the same way on both.
- **Bus frame.** Per frame the bus asks the live scene (and, during a transition, the outgoing scene)
  for its composite, then: progress 0 → the outgoing scene's composite as is; 0 < progress < 1 → one
  full-screen mix pass into a pooled `rgba16Float` blend target; progress ≥ 1 → the outgoing scene and
  the blend target are released before encoding, and the live scene's composite is used as is. The
  bus's single `CompositeFlashGuard` runs on that texture and the output pass (`cmp_output`, the same
  shader source as the compositor) writes it × the gain. `encodeOutput(into:commandBuffer:)` repeats
  the output pass for recording or a second display (REC-003 pattern).
- **Exact ends.** At progress 0 and from progress 1 the shown texture is the scene compositor's own
  composite and the guard and output pass are the same code as `composite(into:)`, so the output is
  byte-identical to the scene alone given the same guard history.
- **No leaks.** The blend target is checked out of the shared pool at the first blended frame and
  returned (fenced by the last command buffer) at the end, on cancel, on interruption, on a size change
  and in `deinit`. The released compositor returns its own pictures in its `deinit`.
- **Model (Linux).** `SceneTransition.swift`: style (cut, crossfade, dip to black), easing (linear,
  ease in-out), a validated Codable `SceneTransitionSpec` with `resolved(reduceMotion:)`, the clock,
  and the mix weights.
- **App.** `MotionPolicy.sceneTransition(_:)` resolves a spec with the system Reduce Motion state
  (decorative → cut). The live output is not moved onto the bus in this row (Clarifications); cues stay
  cuts.

ADR-0041 records the clock and the bus. Report: `docs/test-reports/transition-bus.md`.

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2.
**Primary Dependencies**: none new (Metal; the existing compositor shaders, flash guard and pool).
**Storage**: none (no file format changes; SCN-007 stores transitions).
**Testing**: XCTest in `Packages/Compositor` (GPU tests on the Mac host, skipped without Metal); the
Linux shape with `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`; app unit tests on
an iOS 27.2 simulator; RenderGoldens, SceneFormat, ShowControl, ImportFuzz, SceneArchive regressions.
**Target Platform**: iOS 26+ (app), macOS 15 (package tests), Linux (model).
**Performance Goals**: a blended frame adds one full-screen pass and one scene's work; recorded only.
**Constraints**: nothing allocated per frame at a steady size except the blend target at a
transition's first blended frame (from the pool); unit tests 1–2 s, at most 10 s; package suite under
1 minute (owner rule 7).
**Scale/Scope**: two live scenes at most.

## Constitution Check

| Principle | Check |
|---|---|
| I Public APIs | Metal only. Pass. |
| VI Modular boundaries | The bus lives in `Compositor`; no engine, capture or app imports. Pass. |
| VII Audio safety | Nothing on the audio path. Pass. |
| X Evidence | Byte-identity, pool counts and clock tests; GPU time recorded, not claimed; no device claim. Pass. |
| Privacy | No data, no files, no network. Pass. |
| Flash safety (FR-072, FX-019) | One guard on every shown frame, transitions included. Pass. |
| Accessibility (ACC-001) | Scene transitions are decorative → cut under Reduce Motion. Pass. |

Post-design re-check: unchanged, pass.

## Project Structure

```text
specs/116-cmp-014-compositor-transition-bus/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
└── contracts/transition-bus.md
Packages/Compositor/Sources/Compositor/
├── SceneTransition.swift          # new: spec, easing, clock, weights (Linux)
├── SceneTransitionBus.swift       # new: the bus (Metal)
└── Compositor.swift               # encodeScene + the shared frame routine
Packages/Compositor/Tests/CompositorTests/
├── SceneTransitionModelTests.swift   # new: clock, easing, spec, weights (Linux too)
└── SceneTransitionBusTests.swift     # new: acceptance, cancel, interrupt, cache, flash, timing
Apps/projectM-iOS/Views/MotionPolicy.swift       # sceneTransition(_:)
Apps/projectM-iOS/Tests/MotionPolicyTests.swift  # Reduce Motion → cut
docs/adr/0041-scene-transition-bus.md
docs/test-reports/transition-bus.md
```

**Structure Decision**: one new pair of files in the existing `Compositor` target; the Compositor edit
is limited to the split.

## Follow-up (not this row)

Moving the app's device slot, external display and recording onto a scene compositor fed through the
bus needs every visual as a layer (projectM's `ProjectMLayer`, the spectra adapters exist) and is a
separate change; SCN-007 then stores the cue's transition and SHOW-004 adds overrides.

## Complexity Tracking

None.
