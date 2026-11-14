# Implementation Plan: MOD-004 Curve Mapping

**Branch**: `feature/mod-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/129-mod-004-curve-mapping/spec.md`

## Summary

Add `MappingCurve`, a pure value type in `Packages/ParameterGraph` that shapes a 0…1 position into
0…1 (linear, ease-in, ease-out, ease-in-out, logarithmic, exponential, piecewise-linear through up
to 8 interior points), with exact ends, boundedness, monotonicity and determinism for every curve,
valid or not (research MOD-004-D1 to D4). `AudioFeatureBinding` gains `curve` (default `.linear`);
`AudioFeatureModulator` refuses invalid curves (`invalidCurve`) and resolves
`mapping.interpolate(curve.apply(signal))`, which is bit-identical to today for `.linear` (the curve
returns the already clamped signal unchanged). SHD-009's `ExpressionMapping` gains the same seam.
SceneFormat stores a non-linear curve as an optional `curve` object on a binding (no version bump);
an unreadable curve stays in the binding's unknown fields, and restore rejects that binding with the
new warning `unsupportedCurve` (preserved verbatim by MOD-013). A one-line text form is defined for
MIDI-004. No UI (no binding editor exists). No ADR: the change follows SCN-001's optional-field rule
and overrides no default.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 language mode), Xcode 27.2; CI also Xcode 26
and Linux (explicit closure types, typed maths steps).

**Primary Dependencies**: Foundation's C maths (`pow`, `log1p`, `expm1`) only; available on Linux.

**Storage**: scene JSON (SCN-001) gains an optional binding field; nothing else.

**Testing**: XCTest. ParameterGraph and SceneFormat on the macOS host (and Linux in CI); the app
unit test host (`projectM-iOSTests`) on a private iOS 27.2 simulator for the end-to-end binding and
the ACC-012 clamp. Budgets (owner rule 7): each test about 1-2 s or less, each suite under 1 minute.

**Target Platform**: iOS/iPadOS 26+ (app), macOS 15 host, Linux.

**Project Type**: Swift packages plus one app unit test.

**Performance Goals**: a few floating-point operations per resolve (piecewise: a scan of at most 8
points); no allocation per frame (curve stored in the binding slot at bind time).

**Constraints**: Constitution VI (model in dependency-free ParameterGraph), VII (allocation-free per
frame), X (unit tests for deterministic logic). MOD-004-R7 bit-identity for linear. Scene format: no
version change; QA-004's meta-test must pass (no new `SceneDecodeError` case).

**Scale/Scope**: ~250 lines of model code, ~60 lines of scene code, ~400 lines of tests.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: Swift and libm maths. `check_compliance.py` runs. |
| II-V Capture | Not affected; no compatibility claim. |
| VI Modular boundaries | Pass: the curve lives in ParameterGraph (shared with PerformanceControl for MIDI-004); SceneFormat only persists it. |
| VII Real-time safety | Pass: value type, no allocation or lock in `apply`; still off the audio callback. |
| VIII projectM fidelity | Not affected. |
| IX Dependencies | Pass: none added. |
| X Evidence | Pass: unit tests for every requirement; the simulator run is the app unit test host, never device evidence. |
| Privacy | Pass: no personal data; the stored curve is numbers only. |

Post-design re-check (after Phase 1): unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/129-mod-004-curve-mapping/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/mapping-curve.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/ParameterGraph/Sources/ParameterGraph/
├── MappingCurve.swift            # new: kinds, validation, apply, text form
├── AudioFeatureBinding.swift     # + curve, + invalidCurve error
└── AudioFeatureModulator.swift   # validate curve; interpolate(curve.apply(signal))
Packages/ParameterGraph/Sources/ParameterExpression/ExpressionMapping.swift   # + curve
Packages/ParameterGraph/Tests/ParameterGraphTests/
├── MappingCurveTests.swift       # acceptance fixtures, validation, text form
└── CurvedBindingTests.swift      # modulator: linear bit-identity, curved values, refusal
Packages/SceneFormat/Sources/SceneFormat/
├── SceneDocument.swift           # SceneBinding.curve
├── SceneEncoding.swift / SceneDecoding.swift   # optional "curve" object
├── SceneModulationRestore.swift  # unsupportedCurve rejection
├── SceneIssue.swift / SceneRepair.swift        # new warning code, mapping group
Packages/SceneFormat/Tests/SceneFormatTests/SceneCurveTests.swift
Apps/projectM-iOS/Tests/CurveMappingAppTests.swift   # end to end + ACC-012 clamp
specs/059-scn-001-versioned-scene-format/contracts/scene-document.md   # C5 row, binding field
```

**Structure Decision**: Existing packages only; no new target, no app source change (the app's
`NativeSpectrumHost.bind` already passes the whole binding to the modulator).

## Complexity Tracking

None.
