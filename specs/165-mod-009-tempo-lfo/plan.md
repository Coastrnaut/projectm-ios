# Implementation Plan: MOD-009 Tempo-Synced LFO

**Branch**: `feature/mod-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/165-mod-009-tempo-lfo/spec.md`

## Summary

MOD-007's oscillator gains an optional sync length in beats; the app feeds SHOW-011's current tempo to the
oscillator bank every frame:

- **ParameterGraph** (`LFO.swift`): `LFOSync` (beats per cycle ¼, ½, 1, 2, 4, 8; BPM clamp 40…240;
  `rateHz(bpm:)`), `LFO.sync` (nil by default; validated), `LFO.effectiveRateHz(tempoBPM:maximumRateHz:)`,
  a pure constant-tempo `value(elapsedNanoseconds:tempoBPM:maximumRateHz:)`, and the exact phase generalised
  to a start phase (`LFO.phase(from:elapsedNanoseconds:rateHz:)`; the existing method calls it with the
  phase offset, so MOD-007 results are bit-identical). `LFOBank.values(atNanoseconds:tempoBPM:maximumRateHz:into:)`
  keeps one phase segment per synced slot (start, phase, rate) and starts a new segment, continuous, when
  the slot's effective rate changes (research MOD-009-D2). Free-running slots are unchanged.
- **PerformanceControl** (`TempoSnapshot+LFO.swift`): `TempoSnapshot.lfoTempoBPM`, the BPM the oscillators
  follow (the snapshot's manual > confident estimate > none order; research MOD-009-D1).
- **SceneFormat** (`SceneLFOs.swift`): the entry's optional `sync` object `{"beats": n}`, written by
  `SceneLFOEntry(_ lfo:)` only when set; `read` parses it; new warnings `invalidLFOSync`, `unknownLFOSync`
  (oscillator stays live unsynced); `SceneIssue`, `SceneRepair` mappings (research MOD-009-D4).
- **App**: `NativeSpectrumHost.lfoTempoBPM` (a main-actor closure read once per frame, only while the bank
  has a synced oscillator) passed to the bank; `AppCoordinator+LFOs.swift` connects it to
  `tempo.snapshot.lfoTempoBPM` (research MOD-009-D5).
- Tests: acceptance (120 BPM: 1 beat = 0.5 s, 4 beats = 2.0 s, within 1e-9; long run), tempo change
  continuity (120 → 90 mid-cycle), fallback, Reduce flashing cap, BPM clamp, validation; tempo priority
  through `TempoSource` (PerformanceControl); scene round trip and issues; app unit test with tapped tempo.

No ADR: nothing overrides a default (a new optional field inside an existing optional entry; no settings key;
the 3 Hz cap is unchanged).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new. ParameterGraph stays free of PerformanceControl (PerformanceControl
already depends on ParameterGraph, so the adaptor lives there).

**Storage**: scene JSON (SCN-001), optional `sync` in `lfos` entries; no UserDefaults key.

**Testing**: XCTest. ParameterGraph, PerformanceControl and SceneFormat on the macOS host (Linux in CI); app
unit tests on the private iOS 27.2 simulator "MOD9 iPhone 17". Budgets (owner rule 7). Times and tempos
injected; no wall clock.

**Target Platform**: iOS/iPadOS 26+ (app), macOS host, Linux (packages).

**Project Type**: mobile app with SwiftPM packages.

**Performance Goals**: per frame at most 8 oscillator evaluations plus one segment compare each; no
allocation (segments preallocated at `set`), no lock.

**Constraints**: Constitution VI, VII (never in audio callbacks), X; FR-072 / ACC-012.

**Scale/Scope**: 1 new source file, ~5 edited sources, 1 edited app view host plus coordinator extension, 3
edited and 1 new test file.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pass: plain Swift and the C math library. |
| II-V Capture | Not affected. |
| VI Modular boundaries | Pass: oscillator in ParameterGraph, tempo adaptor in PerformanceControl, persistence in SceneFormat, feed in the app. |
| VII Real-time audio safety | Pass: display-link frame, allocation-free; no audio callback. |
| VIII Upstream fidelity | Not affected (nothing reaches projectM). |
| IX Pinned dependencies | No new dependency. |
| X Evidence-based quality | Pass: closed-form unit tests with injected times and tempos; app test on the simulator; no device claim. |
| Privacy | No new stored key, no network. |
| Flash safety (FR-072) | Pass: 3 Hz cap still applies; tempo changes never jump the phase. |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/165-mod-009-tempo-lfo/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/tempo-lfo.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/ParameterGraph/Sources/ParameterGraph/LFO.swift
Packages/ParameterGraph/Tests/ParameterGraphTests/LFOSyncTests.swift                    (new)
Packages/PerformanceControl/Sources/PerformanceControl/TempoSnapshot+LFO.swift          (new)
Packages/PerformanceControl/Tests/PerformanceControlTests/LFOTempoSourceTests.swift     (new)
Packages/SceneFormat/Sources/SceneFormat/{SceneLFOs,SceneIssue,SceneRepair}.swift
Packages/SceneFormat/Tests/SceneFormatTests/SceneLFOTests.swift
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
Apps/projectM-iOS/Coordinators/AppCoordinator+LFOs.swift
Apps/projectM-iOS/Tests/LFOBindingAppTests.swift
specs/059-scn-001-versioned-scene-format/contracts/scene-document.md
```

**Structure Decision**: extend MOD-007's files; the tempo adaptor goes where the tempo snapshot lives.

## Complexity Tracking

None.
