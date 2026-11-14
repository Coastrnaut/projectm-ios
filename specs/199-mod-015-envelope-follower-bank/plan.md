# Implementation Plan: MOD-015 Envelope Follower Bank

**Branch**: `feature/mod-015` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/199-mod-015-envelope-follower-bank/spec.md`

## Summary

Every band gets three one-pole envelopes (fast, medium, slow) with fixed attack/release time constants on the
frame clock, exposed as bindable sources `audio.bandEnvelope.<profile>.<band>`.

- **ParameterGraph**:
  - `BandEnvelopeProfile` (fast, medium, slow; each an `AudioFeatureEnvelope` from MOD-005, reused, not
    duplicated) and `BandEnvelopeBank` (new, `BandEnvelopeBank.swift`): 128 × 3 preallocated state,
    `advance(bands:timeNanoseconds:)`, `values` (borrowed, band-major), reset on band-count change.
  - `AudioFeatureSource.bandEnvelope(Int, BandEnvelopeProfile)`: ID, parse, value from the new borrowed
    `AudioFeatureFrame.bandEnvelopes`.
  - Band range checks extended to the new case in the modulator, the trigger bank and the graph validator.
  - `ParameterExpression`: the catalog refuses the names (as LFOs, MOD-007-D4); the compiler's exhaustive switch
    gets an unreachable constant, so no opcode is taken (research MOD-015-D5).
- **App**: `NativeSpectrumHost.applyModulation` advances its bank and passes the values in the frame;
  `inspectorName` gets the new case ("Band 4 fast").

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new.

**Storage**: none new (the source ID is stored in scene bindings like any other source); no UserDefaults key.

**Testing**: XCTest. ParameterGraph on the host (Linux in CI); one app unit test on the private simulator
"MOD15 iPhone 17" (iOS 27.2). Frame times injected; no wall clock.

**Target Platform**: iOS/iPadOS 26+; packages also macOS 15 and Linux.

**Performance Goals**: per frame 6 `exp` calls (two coefficients per profile) plus 3 multiply-adds per band; no
allocation.

**Constraints**: chunking-invariant to 1e-12; outputs finite 0…1; type-check budget.

**Scale/Scope**: up to 128 bands × 3 profiles = 384 envelopes.

## Constitution Check

- I Public APIs only: Foundation/C math only. Pass.
- VI Modular boundaries: DSP state in ParameterGraph (no AnalysisFeatures dependency added), feeding in the app. Pass.
- VII Real-time audio safety: runs on the frame loop (main actor), never in an audio callback; preallocated. Pass.
- VIII Upstream fidelity: no projectM analysis duplicated; it smooths the existing ANL-002 bands. Pass.
- X Evidence-based quality: closed-form step tests, independence by bit identity. Pass.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/ParameterGraph/Sources/ParameterGraph/BandEnvelopeBank.swift                         (new)
Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift, AudioFeatureModulator.swift,
  ThresholdTrigger.swift, ModulationGraphValidator.swift
Packages/ParameterGraph/Sources/ParameterExpression/ExpressionCatalog.swift, ExpressionCompiler.swift
Packages/ParameterGraph/Tests/ParameterGraphTests/BandEnvelopeBankTests.swift                  (new)
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift
Apps/projectM-iOS/Tests/BandEnvelopeBindingAppTests.swift                                      (new)
```

**Structure Decision**: the bank lives next to `LFOBank` in ParameterGraph because it produces modulation
sources; ANL-003's `BandSmoother` stays the display smoother (AnalysisFeatures) and is not a dependency.
