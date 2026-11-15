# Implementation Plan: MOD-016 Random walk modulator

**Branch**: `feature/mod-016` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/253-mod-016-random-walk/spec.md`

## Summary

The MOD-007/008/009 oscillator gains one shape, `randomWalk`, and one setting, `smoothness`:

- **ParameterGraph** (`LFO.swift`): `LFOShape.randomWalk` (stored name `randomWalk`); `LFO.smoothness`
  (0…1, default 1, validated for every shape like duty and glide). `LFO.value(at: LFOCycle, slot:)` evaluates
  it as centre + amplitude · (W − 0.5), clamped, with W = a + (b − a) · e(φ), a = level(seed, n),
  b = level(seed, n + 1) (`SteppedRandom.level`, MOD-008), e(φ) = (1 − s)·φ + s·smootherstep(φ)
  (research MOD-016-D1, D2). The step and phase come from MOD-008's exact cycle computation, MOD-009's
  segments carry the step across rate changes, so nothing else in the bank changes.
- **New** static `RandomWalk.ease(_:smoothness:)` and `RandomWalk.maximumSlope(smoothness:)` in a small file
  (`RandomWalk.swift`) so tests and the continuity bound share one definition.
- **SceneFormat** (`SceneLFOs.swift`): optional `smoothness` read with default 1, written only for
  `randomWalk` when not 1 (research MOD-016-D4); out of range → `invalidLFO` (existing code). The
  scene-document contract (specs/059) gains a paragraph.
- **App**: no source change (the host evaluates the bank; bindings read `audio.lfo.<i>`). An app unit test
  (`LFOBindingAppTests`) proves a random walk on the glow.
- Tests (`RandomWalkTests`): acceptance (same seed; 60 Hz, 120 Hz, jittery chunkings and direct seeks give
  identical values at shared times over ≥ 100 cycles; a different seed differs), bounds (dense sweeps plus
  spot sweeps through 10 h, extreme centre/depth, all smoothness corners), continuity bound, targets hit
  exactly at cycle starts, no overshoot between targets, ease endpoints and monotonicity, synced continuity
  across a tempo change, Reduce flashing cap, validation; scene round trip, default not written, invalid
  smoothness reported; app glow test.

No ADR: nothing overrides a default (a new optional field in an existing optional entry; no settings key; the
3 Hz cap is unchanged).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new.

**Storage**: scene JSON (SCN-001), an optional field in `lfos` entries; no UserDefaults key.

**Testing**: XCTest. ParameterGraph and SceneFormat on the macOS host (Linux in CI); app unit tests on the
private iOS 27.2 simulator "MOD16 iPhone 17". Budgets (owner rule 7). Frame times injected; no wall clock.

**Target Platform**: iOS/iPadOS 26+ (app), macOS host, Linux (packages).

**Project Type**: mobile app with SwiftPM packages.

**Performance Goals**: per frame at most 8 oscillators, each at most two level hashes and a fifth-degree
polynomial; no allocation, no lock.

**Constraints**: Constitution VI, VII (never in audio callbacks), X; FR-072 / ACC-012.

**Scale/Scope**: 1 new source, 2 edited sources, 1 contract doc, 1 new and 3 edited test files, 1 edited app
test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pass: plain Swift and the C math library. |
| II-V Capture | Not affected. |
| VI Modular boundaries | Pass: oscillator in ParameterGraph, persistence in SceneFormat. |
| VII Real-time audio safety | Pass: display-link frame, allocation-free; no audio callback. |
| VIII Upstream fidelity | Not affected. |
| IX Pinned dependencies | No new dependency. |
| X Evidence-based quality | Pass: exact unit tests with injected times; app test on the simulator; no device claim. |
| Privacy | No new stored key, no network; the seed is not a user identifier. |
| Flash safety (FR-072) | Pass: the 3 Hz cap applies; the walk is continuous (no edges). |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/253-mod-016-random-walk/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/random-walk.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/ParameterGraph/Sources/ParameterGraph/LFO.swift
Packages/ParameterGraph/Sources/ParameterGraph/RandomWalk.swift                    (new)
Packages/ParameterGraph/Tests/ParameterGraphTests/RandomWalkTests.swift            (new)
Packages/ParameterGraph/Tests/ParameterGraphTests/{LFOTests,LFOSyncTests}.swift     (shape switches)
Packages/SceneFormat/Sources/SceneFormat/SceneLFOs.swift
Packages/SceneFormat/Tests/SceneFormatTests/SceneLFOTests.swift
Apps/projectM-iOS/Tests/LFOBindingAppTests.swift
specs/059-scn-001-versioned-scene-format/contracts/scene-document.md
```

**Structure Decision**: extend the oscillator (MOD-007/008/009 files); the ease is its own small file.

## Complexity Tracking

None.
