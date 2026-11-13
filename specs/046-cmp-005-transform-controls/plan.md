# Implementation Plan: CMP-005 Transform Controls

**Branch**: `feature/cmp-005` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/046-cmp-005-transform-controls/spec.md`

## Summary

Replace the placeholder `LayerTransform` (six raw pixel-space numbers, never used) with a value type
of move, per-axis scale, rotation and anchor point (CPU, Linux), which produces an exact 3 × 3 affine
`LayerTransformMatrix` for an output aspect in the documented order (research CMP-005-D1), refuses
non-finite input with a typed `LayerTransformError`, clamps finite input, and is `Codable` in a
versioned shape whose numbers round-trip bit for bit (CMP-005-D3). The compositor accepts
transforms (`isSupportedByCompositor` = normal blend only), keeps each record's transform (updated
at apply, no re-creation), and draws non-identity layers with a second fragment function
`cmp_over_transformed` that samples the picture bilinearly through the inverse pixel-space matrix
with transparent outside; identity layers keep the exact `cmp_over` path (CMP-005-D4). Recorded as
a CMP-005 amendment to ADR-0013. No transform animation (spec Clarifications).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the build Mac, Xcode 26 in CI).

**Primary Dependencies**: Compositor (CMP-001 to CMP-003), Metal; Foundation for `sin`/`cos` and
the tests' `JSONEncoder`/`JSONDecoder`. No `Package.swift` change.

**Storage**: the saved form is a `Codable` value; files are SCN-001's.

**Testing**: XCTest via `swift test --package-path Packages/Compositor` (Mac host), the Linux shape
(`--scratch-path .build/linuxshape -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL
-Xswiftc -DANALYSIS_NO_ACCELERATE`), `xcodebuild test -scheme Compositor` on an iOS 27.2 simulator.

**Target Platform**: iOS/iPadOS 26+, macOS 15 host for tests, Linux for the CPU part.

**Project Type**: Swift package library (mobile app module). No app change.

**Performance Goals**: no per-frame allocation (a 48-byte `setFragmentBytes` per transformed draw);
one pipeline switch per transformed layer. Device frame cost: CMP-002-T15 `{device}` (CMP-005-S6).

**Constraints**: Public Apple APIs; owner rule 7 budgets (GPU tests at 64 × 64); explicit closure
types and no C stdio globals for Xcode 26 and Linux; no wall-clock assertions.

**Scale/Scope**: ≤ 8 layers; about 250 lines of source, 400 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | Metal and Foundation only | Pass |
| II. Privacy / local-first | The saved form is local data; no network | Pass |
| VI. Modular boundaries | Changes stay in the `Compositor` target; no projectM, ANGLE, capture or app imports | Pass |
| VII. Real-time audio safety | No audio-path change | Pass |
| VIII. Upstream fidelity | projectM untouched | Pass |
| X. Evidence | Host, Linux-shape and simulator tests; device cost stays with CMP-002-T15 | Pass |
| Flash safety (ADR-0011, ADR-0013 decision 6) | Transforms are drawn in the composite pass, before the guard | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/046-cmp-005-transform-controls/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/layer-transform.md
└── checklists/requirements.md
docs/adr/0013-compositor-layer-protocol.md   # + "Amendment: CMP-005 transform controls"
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/
├── LayerTransform.swift        # NEW (CPU): LayerTransform, LayerTransformMatrix, LayerPoint, LayerTransformError, Codable
├── LayerContract.swift         # old placeholder struct removed; isSupportedByCMP001 uses isIdentity; isSupportedByCompositor = normal blend
├── Compositor.swift            # transform per record; apply updates it; transformed draws use the second pipeline
└── CompositorShaders.swift     # + cmp_over_transformed (bilinear through the inverse, clamp to zero)
Packages/Compositor/Tests/CompositorTests/
├── LayerTransformTests.swift          # NEW (CPU, also Linux shape): matrix rules, validation, round trip
├── LayerTransformCompositeTests.swift # NEW (GPU 64 × 64)
├── ContractTests.swift                # updated: transforms supported
├── LayerStackApplyTests.swift         # updated: the old refusal case now applies
└── TwoLayerCompositeTests.swift       # updated: the old refusal case now accepted
```

**Structure Decision**: one new CPU file for the transform model so it builds on Linux and a scene
file (SCN-001) can embed it; the compositor change is a second pipeline and a few lines.

## Complexity Tracking

None.
