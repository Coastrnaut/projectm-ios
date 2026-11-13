# Implementation Plan: MOD-002 Audio Feature Binding

**Branch**: `feature/mod-002` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/031-mod-002-audio-feature-binding/spec.md`

## Summary

A dependency-free binding model in `Packages/ParameterGraph` (MOD-001's module): audio feature
sources, a validated binding (input range → output range, mix mode, optional attack/release
envelope) and a single-owner, allocation-free modulator that resolves a parameter's effective value
from its manual value each frame on a caller-supplied clock. The app evaluates bindings in the
native spectra's frame loop and applies a bound glow intensity to the bloom and to the Reduce-
flashing luminance model; a Debug-only launch argument binds the lowest band to the glow intensity
for a simulator UI test. No user-visible UI, setting or stored data. No ADR: the model follows
ADR-0012's modulation policy and overrides no default (research MOD-002-D1 to D8 record the
choices).

1. **`Packages/ParameterGraph`** (no new dependency; Linux-tested):
   - `AudioFeatureSource` (band level by index, mean level, onset value, beat confidence; stable
     textual IDs) and `AudioFeatureFrame` (borrowed band levels plus optional onset and beat values).
   - `AudioFeatureBinding` (source, target, input range, output range, mix mode, envelope) and
     `AudioFeatureEnvelope`; `AudioFeatureBindingError` (readable reasons).
   - `AudioFeatureModulator` (final class, one owner): `bind`, `unbind`, `unbindAll`, `isBound`,
     `bindings`, `advance(frame:timeNanoseconds:)`, `signal(for:)`, `value(for:manual:)` for
     `Double` and `ParameterValue`, and `value(for:in:)` reading the manual value from a
     `ParameterStore`.
2. **`Packages/VisualGenerators`, target `VisualEffects`**: `BloomEffect.parameters` updates only
   the uniforms when the intensity alone changed (the plan does not depend on it), so a modulated
   intensity costs no `BloomPlan` (array) allocation per frame (research MOD-002-D6).
3. **App** (`Apps/projectM-iOS`):
   - `Visuals/NativeSpectrumHost.swift`: owns an `AudioFeatureModulator` over the visual catalog;
     `bind(_:)`, `unbind(_:)`; per frame, when any binding exists, advances it with the frame's
     bands and display time and applies the effective glow intensity to the bloom and to a
     reference-typed luminance model (`ModulatedGlowLuminance`) set once as the generator's
     downstream luminance. Without bindings the frame loop is unchanged (MOD-002-R11).
   - `Coordinators/AppCoordinator.swift`: under `#if DEBUG`, `-uitestBindGlowToBass` binds band 0
     to `effect.bloom.intensity` (replace, full range) after the host is created; `unbindGlowTest()`.
   - `Debug/UITestModulationPanel.swift` (DEBUG only): the readout and an Unbind button.
   - Tests: `Tests/AudioFeatureBindingAppTests.swift` (host-level, deterministic) and
     `UITests/AudioFeatureBindingUITests.swift` (one UI test, < 30 s).
4. **CI**: no change (no new package; ParameterGraph and VisualGenerators are already in the five
   loops).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 language mode), Xcode 27.2; CI also Xcode 26.

**Primary Dependencies**: Foundation (`exp`) only in the model; the app adds no framework.

**Storage**: none (bindings live in memory; MOD-013 persists them).

**Testing**: XCTest on the macOS host and Linux (CI) for the model; the iOS 27.2 simulator for the
host-level app test and one UI test. Deterministic: frames and timestamps are passed in; no sleeps,
no wall clock. Budgets (owner rule 7): each unit test ≤ 1 s, the ParameterGraph suite < 5 s, the UI
test < 30 s.

**Target Platform**: iOS/iPadOS 26+ (app), macOS 15 host, Linux for the package.

**Project Type**: mobile app + Swift packages.

**Performance Goals**: `advance` is O(bindings × 1) except the mean-level source (O(bands) ≤ 128);
at most 32 bindings; no allocation, lock or dictionary in `advance` and `value(for:)` (linear scan
over ≤ 32 slots with `ParameterID` equality).

**Constraints**: Constitution I (public APIs), VI (the model knows nothing of UI, rendering or
analysis types), VII (never on the audio callback; allocation-free per frame), X (unit tests for
deterministic logic). FX-019: the limiter must see the effective glow. Privacy: no new stored data.

**Scale/Scope**: ~350 lines of model code, ~80 lines of app code, ~400 lines of tests.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: Foundation only in the model; Metal/UIKit only in existing app files. `check_compliance.py` runs. |
| II-V Capture | Not affected; no compatibility claim. |
| VI Modular boundaries | Pass: the model takes plain floats (no dependency on AnalysisFeatures); the app adapts its band buffer. |
| VII Real-time safety | Pass: evaluation runs on the main-thread frame loop, never the audio callback; no allocation or lock per frame (slots preallocated, intensity-only bloom update). |
| VIII projectM fidelity | Pass: projectM untouched; its parameters are not bindable. |
| IX Dependencies | Pass: none added. |
| X Evidence | Pass: unit tests for every rule; simulator tests are not device evidence; no device claim. |
| Safety (FR-072, FX-019) | Pass: Reduce flashing is unregistered and so unbindable; the luminance model follows the effective intensity. |
| Privacy | Pass: no new stored data, no network. |

Post-design re-check (after Phase 1): unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/031-mod-002-audio-feature-binding/
├── plan.md
├── research.md            # MOD-002-D1 … D8
├── data-model.md
├── quickstart.md
├── contracts/audio-feature-binding.md
├── checklists/requirements.md
└── tasks.md               # /speckit-tasks
```

### Source Code

```text
Packages/ParameterGraph/
├── Sources/ParameterGraph/
│   ├── AudioFeatureSource.swift       # source, frame
│   ├── AudioFeatureBinding.swift      # binding, envelope, error, validation
│   └── AudioFeatureModulator.swift    # slots, envelopes, evaluation
└── Tests/ParameterGraphTests/
    ├── AudioFeatureSourceTests.swift
    ├── AudioFeatureBindingValidationTests.swift
    └── AudioFeatureModulatorTests.swift
Packages/VisualGenerators/
├── Sources/VisualEffects/BloomEffect.swift                # intensity-only update
└── Tests/VisualGeneratorsTests/
    ├── BloomRenderTests.swift (or a new small test)        # plan unchanged by intensity
    └── VisualParameterBindingTests.swift                  # app catalog compatibility
Apps/projectM-iOS/
├── Visuals/NativeSpectrumHost.swift
├── Coordinators/AppCoordinator.swift
├── Views/VisualizerView.swift                             # DEBUG panel hook
├── Debug/UITestModulationPanel.swift
├── Tests/AudioFeatureBindingAppTests.swift
└── UITests/AudioFeatureBindingUITests.swift
```

**Structure Decision**: the model goes into `ParameterGraph` (it binds registry parameters and must
stay dependency-free for Linux); the app catalog's compatibility test lives with the catalog in
`VisualGenerators`; app wiring is limited to the native host, one DEBUG hook and its panel.

## Rollback

Additive: deleting the three model files, their tests, the app files' modulation lines and the
DEBUG panel restores the previous behavior; the BloomEffect change is behavior-preserving (same
uniforms, fewer allocations). No stored data depends on it.

## Complexity Tracking

None: no constitution violation.
