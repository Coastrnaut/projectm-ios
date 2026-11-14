# Implementation Plan: MOD-005 Attack/Release Envelope

**Branch**: `feature/mod-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/141-mod-005-attack-release/spec.md`

## Summary

MOD-002 already smooths each binding with a one-pole attack/release envelope driven by the injected
frame clock. This row makes it correct, complete and proven rather than re-implementing it:

- `AudioFeatureEnvelope` documents its definition (τ, 63.2 % at τ, 10–90 % = τ·ln 9), gains the pure
  step `AudioFeatureEnvelope.step(from:toward:elapsedSeconds:)` (attack for rise, release for fall,
  τ = 0 instant, Δt ≤ 0 or non-finite ignored, non-finite previous value snaps, result clamped to
  0…1) and conversion helpers `riseTime10To90(timeConstant:)` / `timeConstant(riseTime10To90:)`
  (research MOD-005-D1 to D3).
- `AudioFeatureModulator.advance` calls the step (bit-identical for valid inputs; the arithmetic
  expression is unchanged) and gains `setEnvelope(_:for:)`, which validates and replaces the times
  without restarting the signal (MOD-005-R8).
- SceneFormat already stores `envelope {attack, release}` as optional fields. Restore reports an
  invalid envelope at `$.bindings[i].envelope` (MOD-005-R10). No format change.
- Tests: the step-response acceptance at 60 fps, 120 fps and seeded jitter; edge cases; scene round
  trip; an app unit test on the simulator (slow attack, fast release on the glow intensity).

No ADR: nothing overrides a default; the range and meaning stay MOD-002's.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: Foundation `exp`, `log` only (available on Linux).

**Storage**: scene JSON (SCN-001) unchanged; the existing optional `envelope` object.

**Testing**: XCTest. ParameterGraph and SceneFormat on the macOS host (Linux in CI); the app unit test
host on the private iOS 27.2 simulator "MOD5 iPhone 17". Budgets (owner rule 7): each test ≲ 1 s, each
suite under 1 minute. Seeded jitter uses a local SplitMix64, no system randomness, no wall clock.

**Target Platform**: iOS/iPadOS 26+ (app), macOS host, Linux.

**Project Type**: Swift packages plus one app unit test.

**Performance Goals**: one `exp` per binding per frame (unchanged); no allocation in `advance` or
`setEnvelope`.

**Constraints**: Constitution VI, VII (allocation-free per frame, never on the audio callback), X.
Bit-identity for valid inputs (MOD-005-R9). QA-004 meta-test passes (no new `SceneDecodeError` case,
no new field). MIDI files untouched (MIDI-004 merging in parallel).

**Scale/Scope**: ~60 lines of model code, ~10 lines of scene code, ~350 lines of tests.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: Swift and libm. `check_compliance.py` runs. |
| II-V Capture | Not affected; no compatibility claim. |
| VI Modular boundaries | Pass: envelope maths in ParameterGraph; SceneFormat only reports. |
| VII Real-time safety | Pass: value-type step, no allocation or lock; still off the audio callback. |
| VIII projectM fidelity | Not affected. |
| IX Dependencies | Pass: none added. |
| X Evidence | Pass: unit tests per requirement; the simulator run is the app unit test host, not device evidence. |
| Privacy | Pass: no new stored data. |

Post-design re-check (after Phase 1): unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/141-mod-005-attack-release/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/envelope.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/ParameterGraph/Sources/ParameterGraph/
├── AudioFeatureBinding.swift      # envelope definition docs, step(), 10–90 % helpers
└── AudioFeatureModulator.swift    # advance uses step(); setEnvelope(_:for:)
Packages/ParameterGraph/Tests/ParameterGraphTests/
└── EnvelopeStepResponseTests.swift   # acceptance + edge cases + setEnvelope
Packages/SceneFormat/Sources/SceneFormat/SceneModulationRestore.swift   # invalidEnvelope → .envelope path
Packages/SceneFormat/Tests/SceneFormatTests/SceneEnvelopeTests.swift   # round trip, legacy, invalid
Apps/projectM-iOS/Tests/EnvelopeBindingAppTests.swift                   # slow attack, fast release on glow
```

**Structure Decision**: existing packages and the existing app test target only; no app source change
(`NativeSpectrumHost.bind` passes the whole binding, envelope included). The new app test file is
picked up by XcodeGen's folder source.

## Complexity Tracking

None.
