# Implementation Plan: MOD-008 Stepped LFO (square and sample-and-hold)

**Branch**: `feature/mod-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/212-mod-008-stepped-lfo/spec.md`

## Summary

MOD-007's oscillator gains two stepped shapes; MOD-009's phase segment gains a whole-cycle count:

- **ParameterGraph** (`LFO.swift`): `LFOShape.square` and `.sampleHold`; `LFO.dutyCycle` (0.05…0.95,
  default 0.5), `LFO.seed` (`UInt32?`, nil = position default), `LFO.glide` (0…1, default 0), validated.
  The exact phase function is generalised to return the whole-cycle count too (`LFO.cycle(from:…)` →
  `LFOCycle(step: Int64, phase: Double)`); the existing `phase(…)` returns its phase, bit-identical.
  `LFO.value(at: LFOCycle, slot:)` evaluates every shape; sine and triangle ignore the step.
- **New** `SteppedRandom.swift`: the counter-based level `level(seed:step:)` (SplitMix64 finalizer, 53-bit
  unit value; research MOD-008-D1) and the position default seed (MOD-008-D2).
- `LFOBank`: passes each slot's position (for the default seed); MOD-009 segments carry `startCycle` so a
  rate change continues the step count (MOD-008-D4).
- **SceneFormat** (`SceneLFOs.swift`): optional `duty`, `seed`, `glide` fields, written only when they matter
  (MOD-008-D5); read with defaults; out of range → `invalidLFO` (existing code). The scene-document contract
  (specs/059) gains a paragraph.
- **App**: no source change needed (the host evaluates the bank; bindings read `audio.lfo.<i>`). An app unit
  test (`LFOBindingAppTests`) proves a sample-and-hold oscillator on the glow.
- Tests: acceptance (same seed, 60 Hz / 120 Hz / jittery chunkings, ≥100 steps identical; different seed
  differs), square boundaries, glide, hours-long step exactness, synced step continuity, Reduce flashing cap,
  validation; scene round trip, defaults not written, invalid values reported; app glow test.

No ADR: nothing overrides a default (new optional fields in an existing optional entry; no settings key; the
3 Hz cap is unchanged).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new.

**Storage**: scene JSON (SCN-001), optional fields in `lfos` entries; no UserDefaults key.

**Testing**: XCTest. ParameterGraph and SceneFormat on the macOS host (Linux in CI); app unit tests on the
private iOS 27.2 simulator "MOD8 iPhone 17". Budgets (owner rule 7). Frame times injected; no wall clock.

**Target Platform**: iOS/iPadOS 26+ (app), macOS host, Linux (packages).

**Project Type**: mobile app with SwiftPM packages.

**Performance Goals**: per frame at most 8 oscillators, each at most two level hashes (glide) — integer
arithmetic only; no allocation, no lock.

**Constraints**: Constitution VI, VII (never in audio callbacks), X; FR-072 / ACC-012.

**Scale/Scope**: 1 new source, 2 edited sources, 1 contract doc, 2 edited and 1 new test file, 1 edited app test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pass: plain Swift and the C math library. |
| II-V Capture | Not affected. |
| VI Modular boundaries | Pass: oscillator in ParameterGraph, persistence in SceneFormat. |
| VII Real-time audio safety | Pass: display-link frame, allocation-free; no audio callback. |
| VIII Upstream fidelity | Not affected. |
| IX Pinned dependencies | No new dependency (the generator is a few lines of integer code). |
| X Evidence-based quality | Pass: exact unit tests with injected times; app test on the simulator; no device claim. |
| Privacy | No new stored key, no network; the seed is not a user identifier. |
| Flash safety (FR-072) | Pass: 3 Hz cap applies to the new shapes; square duty limited to 0.05…0.95. |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/212-mod-008-stepped-lfo/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/stepped-lfo.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/ParameterGraph/Sources/ParameterGraph/LFO.swift
Packages/ParameterGraph/Sources/ParameterGraph/SteppedRandom.swift                 (new)
Packages/ParameterGraph/Tests/ParameterGraphTests/SteppedLFOTests.swift            (new)
Packages/ParameterGraph/Tests/ParameterGraphTests/{LFOTests,LFOSyncTests}.swift     (shape switches)
Packages/SceneFormat/Sources/SceneFormat/SceneLFOs.swift
Packages/SceneFormat/Tests/SceneFormatTests/SceneLFOTests.swift
Apps/projectM-iOS/Tests/LFOBindingAppTests.swift
specs/059-scn-001-versioned-scene-format/contracts/scene-document.md
```

**Structure Decision**: extend MOD-007's and MOD-009's files; the generator is its own small file.

## Complexity Tracking

None.
