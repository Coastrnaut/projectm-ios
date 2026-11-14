# Tasks: MOD-015 Envelope Follower Bank

**Input**: Design documents from `specs/199-mod-015-envelope-follower-bank/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/band-envelopes.md, quickstart.md

Tests are requested by the roadmap acceptance ("Step tests verify independent smoothing profiles").

## Phase 1: Setup

- [ ] MOD-015-T01 Create the private simulator "MOD15 iPhone 17" (iOS 27.2) and count PosterBoard reports before any run

## Phase 2: Foundational

- [ ] MOD-015-T02 Add `BandEnvelopeProfile` (fast 0.010/0.080 s, medium 0.080/0.350 s, slow 0.400/1.600 s attack/release τ as `AudioFeatureEnvelope`) and `BandEnvelopeBank` (128 × 3 preallocated, band-major `band·3 + profile`, contract B1-B6, B8) in Packages/ParameterGraph/Sources/ParameterGraph/BandEnvelopeBank.swift

## Phase 3: User Story 1 - Follow one band at three speeds (P1) MVP

**Independent test**: a step in one band; each profile matches its closed form; other bands and profiles untouched.

- [ ] MOD-015-T03 [US1] Step acceptance and edge tests (closed form 1e-9 at 60 fps, 120 fps, seeded jitter; 90 % crossing order fast < medium < slow within one frame of τ·ln 10; other bands bit-identical; a variant bank with changed medium constants leaves fast and slow bit-identical; chunking 1e-12; agreement with `AudioFeatureEnvelope.step`; NaN/∞/out-of-range inputs; band-count reset; Δt rules) in Packages/ParameterGraph/Tests/ParameterGraphTests/BandEnvelopeBankTests.swift

## Phase 4: User Story 2 - Bind an envelope to a parameter or trigger (P1)

**Independent test**: a binding from a band envelope follows it; the ID round-trips; triggers accept it.

- [ ] MOD-015-T04 [US2] `AudioFeatureSource.bandEnvelope(Int, BandEnvelopeProfile)`, ID `audio.bandEnvelope.<profile>.<band>` (band 0…127, no sign, no leading zeros), `AudioFeatureFrame.bandEnvelopes` (borrowed) in Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift
- [ ] MOD-015-T05 [US2] Band range checks for the new case in AudioFeatureModulator.swift, ThresholdTrigger.swift and ModulationGraphValidator.swift (Packages/ParameterGraph/Sources/ParameterGraph/)
- [ ] MOD-015-T06 [US2] Refuse the names in Packages/ParameterGraph/Sources/ParameterExpression/ExpressionCatalog.swift; unreachable constant in ExpressionCompiler.swift (no opcode, research MOD-015-D5)
- [ ] MOD-015-T07 [US2] Package tests: ID round trip and refusals, frame value reading, modulator binding following the slow envelope, trigger acceptance, band > 127 refused, expression refusal, in Packages/ParameterGraph/Tests/ParameterGraphTests/BandEnvelopeBankTests.swift Packages/ParameterGraph/Tests/ParameterExpressionTests/ (one test) and a scene binding round trip of `audio.bandEnvelope.slow.0` in Packages/SceneFormat/Tests/ (MOD-015-S4)
- [ ] MOD-015-T08 [US2] App (the bank advances only past the existing no-bindings-no-triggers return, MOD-015-R7): `NativeSpectrumHost.applyModulation` advances a host-owned `BandEnvelopeBank` and passes `values` in the frame (Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift); `inspectorName` "Band <n> <profile>" (Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift)
- [ ] MOD-015-T09 [US2] App unit test: a slow-envelope binding on the glow follows the slow closed form; inspector name "Band 1 slow", in Apps/projectM-iOS/Tests/BandEnvelopeBindingAppTests.swift

## Phase 5: Polish

- [ ] MOD-015-T10 Repo checks (compliance, docs, motion, permissions, status events, script tests), type-check budget build, ParameterGraph package tests (Foundation and C math only, so the Linux CI shape needs no extra flag), PosterBoard count, delete the simulator and derived data

## Dependencies

T01 → T02 → T03 (US1). T04 needs T02; T05-T07 need T04; T08 needs T04; T09 needs T08. T10 last.
Parallel: T05 and T06 touch different files; T03 can be written alongside T04.

## Implementation strategy

MVP is US1 (the bank and its step tests, the roadmap acceptance). US2 exposes it to bindings and the app.
