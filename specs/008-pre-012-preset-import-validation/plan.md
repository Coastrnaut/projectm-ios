# Implementation Plan: PRE-012 Preset import validation

**Branch**: `feature/pre-012` | **Date**: 2026-11-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/008-pre-012-preset-import-validation/spec.md`

## Summary

The user imports one `.milk` file into "My Presets". The file is copied into app storage under
its content hash, checked statically against limits measured on the built-in corpus, then tried
on a second engine off screen with a time limit. Only then is it playable. Failures end in a
quarantine list with a reason. A durable trial record makes a preset that killed the app
quarantined at the next launch. Validation, the versioned store, quarantine and the trial state
machine live in the existing `PresetLibrary` package (Foundation only, tested on the macOS host
and Linux). The off-screen trial is a new class next to the preset warm-up in `ANGLERendering`.
The app adds a thin coordinator and three SwiftUI views. No new package, dependency, entitlement,
permission or networking.

## Technical Context

**Language/Version**: Swift 6.4.2 (strict concurrency), Xcode 27.2 / iOS SDK 27.2 (ADR-0002)

**Primary Dependencies**: none new. Foundation, SwiftUI (`fileImporter`), Observation,
UniformTypeIdentifiers (app only). Hashing is a small pure-Swift SHA-1 and SHA-256 inside
`PresetLibrary`, because the package is also tested on Linux where CryptoKit is absent (research
D3).

**Storage**: `<Application Support>/UserPresets/`: `index.json` (versioned, Codable, atomic),
`files/<sha256>.milk`, `quarantine/<sha256>.milk`, `trial.json`, `incoming/` (staging). The scope
stays in `settings.presetScope` with the new value `user`.

**Testing**: XCTest. `PresetLibrary` with `swift test` on the macOS host (valid on Linux);
`ANGLERendering` and `Rendering` with `xcodebuild test` on the iOS 27.2 simulator (real engine);
app unit tests and XCUITests in the `projectM-iOS` scheme on the same simulator. Fixtures are
synthetic presets written in the tests; no third-party preset is copied into the repository.

**Target Platform**: iOS and iPadOS 26.0+; `PresetLibrary` also builds for macOS 15 and Linux.

**Project Type**: mobile app with SwiftPM packages under `Packages/`

**Performance Goals**: static validation of a 512 KiB file under 1 s (S2); a valid preset
playable within 5 s of being picked on the simulator (S5).

**Constraints**: public Apple APIs only; no networking; no new entitlement; nothing from an
imported file is executed except by handing its text to the engine through the existing bridge;
no file under `Vendor/` changes; the collections file format (PRE-007) is unchanged.

**Scale/Scope**: at most 1,000 user presets and 200 quarantined files; index well under 2 MB.

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| I. Public APIs only | Pass | `fileImporter`, security-scoped URL access, Foundation, EGL through ANGLE as today. `check_compliance.py` must stay green. |
| II-V. Capture | n/a | No capture code is touched. |
| VI. Modular boundaries | Pass | Validation and persistence in `PresetLibrary`; the engine trial behind a protocol declared in `Rendering` and implemented in `ANGLERendering`; C++ stays behind `ProjectMBridge`, which is unchanged. |
| VII. Real-time audio safety | Pass | No audio callback is touched. The trial feeds its own engine a generated tone on its own thread. |
| VIII. Upstream fidelity | Pass | No engine patch. The static limits are derived from the engine's observed behavior, not from changes to it. |
| IX. Pinned dependencies, license review | Pass | No new dependency. "User-imported presets MUST be handled as untrusted input" is the subject of the feature. The takedown list is honored for imports. |
| X. Evidence | Pass | Unit tests for every deterministic rule; simulator tests with the real engine; device checks tagged `{device}` and left for the final device phase; simulator results are not called device evidence. |
| Security: imported files | Pass | Size, type and content are validated; malformed input fails gracefully (R3, R7-R10). |
| Privacy | Pass | Files stay on the device; FR-065 is amended by R30 and the privacy policy gains a row and a sentence. |

No deviation; Complexity Tracking is empty. Re-checked after design: unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/008-pre-012-preset-import-validation/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── user-presets.md
│   └── user-presets.schema.json
├── checklists/requirements.md
└── tasks.md            (/speckit-tasks)
```

### Source Code (repository root)

```text
Packages/PresetLibrary/Sources/PresetLibrary/
├── PresetScope.swift                    + case user
├── PresetLibrary.swift                  + userSource, withUserPresets(_:), .user members
└── UserPresets/
    ├── ContentHash.swift                SHA-1 (git blob id), SHA-256
    ├── PresetImportLimits.swift         the limits of Clarifications
    ├── MilkdropPresetValidator.swift    static validation over bytes
    ├── UserPresetModel.swift            UserPreset, states, reasons, warnings, license metadata, texts
    ├── UserPresetsFile.swift            versioned document + migrations
    ├── UserPresetStore.swift            files, index, trial record; transactions
    └── UserPresetLibrary.swift          actor: import, trial state machine, proving, removal
Packages/PresetLibrary/Tests/PresetLibraryTests/
├── ContentHashTests.swift, MilkdropPresetValidatorTests.swift, PresetMutationSweepTests.swift,
│   UserPresetStoreTests.swift, UserPresetLibraryTests.swift, UserPresetScopeTests.swift,
│   UserPresetFixtures.swift
└── Golden/user-presets-v1.json

Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift   + PresetTrialOutcome, PresetTrialing,
                                                                  VisualizerRenderer.presetTrial (default nil)
Packages/ANGLERendering/Sources/ANGLERendering/
├── PresetTrialRunner.swift              off-screen trial: own thread, context, engine; time limit
└── ANGLERenderer.swift                  + presetTrial, registered as a presentation-bound resource
Packages/ANGLERendering/Tests/ANGLERenderingTests/PresetTrialRunnerTests.swift

Apps/projectM-iOS/
├── Coordinators/UserPresetsCoordinator.swift     new: presentation state, import, guard hooks
├── Coordinators/PresetCoordinator.swift          user presets in the library; proving and failure hooks
├── Coordinators/AppCoordinator.swift             creates and wires the coordinator (small, localized)
├── Views/UserPresetsView.swift                   My Presets, information, Quarantine
├── Views/PresetBrowserView.swift                 the My Presets row
├── Tests/UserPresetsCoordinatorTests.swift
└── UITests/UserPresetsUITests.swift
project.yml                         PresetBlocklist.json becomes a bundled resource (one exclude removed)
docs/privacy-policy.md              one sentence and one coverage row
```

**Structure Decision**: extend `PresetLibrary`, `Rendering`, `ANGLERendering` and the app. No new
package. `ProjectMBridge` is unchanged: its typed load failure is all the trial needs.

## Design

### Layers

1. **Admission** (`UserPresetLibrary.importFile`): regular file, `.milk`, 1…524,288 bytes, read
   through a bounded read into `incoming/`. Hash (SHA-256 and git blob SHA-1). Refuse takedown
   content and duplicates. Nothing is stored for a refusal.
2. **Static validation** (`MilkdropPresetValidator`): one pass over bytes, iterative, no `String`
   decoding of the whole file. Mirrors the engine's own line parser (first `=` or space ends the
   key; the first occurrence of a key wins; code blocks are `prefix1…prefixN` until the first
   gap) so the validator judges what the engine will actually read.
3. **Trial** (`PresetTrialRunner` behind `PresetTrialing`): a new thread with a 512 KiB stack
   (the visible renderer runs on the main thread, 1 MiB), an unshared EGL context on the visible
   renderer's display, a fresh engine, a 256 × 256 BGRA target. Load, then 30 frames with a
   generated 440 Hz tone, then `glFinish`. Outcome is passed, failed(message), timedOut or
   unavailable(reason).
4. **Record** (`UserPresetStore`): `trial.json` is written and synced before the trial or the
   proving period starts and removed when it ends. `load()` at launch quarantines the preset it
   names.
5. **On screen** (`PresetCoordinator`): a user preset that fails on the visible renderer is
   quarantined; an unproven one is proven after 3 s of presented frames.

### State machine (one user preset)

```text
            import ok               trial passed            3 s on screen
(file) ───────────────▶ pending ───────────────▶ playable ───────────────▶ playable, proven
   │ static failure        │ failed / timed out      │ load failure on screen
   ▼                       ▼ record found at launch  ▼ record found at launch
quarantined ◀──────────────┴─────────────────────────┘
   │ delete
   ▼
 (gone)
pending ──unavailable──▶ pending (tried again at the next opportunity)
```

`pending` and `quarantined` are never in any list the renderer can be asked to play: only
`playable` records are turned into `IndexedPreset` values.

### Transactions and rollback

Every change builds a new index in memory, writes it atomically, and only then updates memory
(the PRE-007 pattern). File moves happen before the index write and are undone when it fails, so
after any failure the directory and index are what they were. `incoming/` is emptied at load.
Files in `files/` or `quarantine/` that no record names are left alone (never deleted silently).

### How user presets join the library

`PresetLibrary.withUserPresets(_:)` returns a library whose `presets`, id lookup and search keys
include the user presets (source `user`, never locked). Favorites, collections and search then
work without format changes. `.all` and the home tree are the built-in library only; `.user` is
the new scope. `PresetCoordinator` keeps the built-in library and rebuilds the combined one when
the user list changes. User presets are not handed to the preset warm-up: its second engine is
outside the guarded path and its benefit for a handful of small presets is nil.

### Deterministic tests

- Validator: table of fixtures → exact reason; the limits at N and N+1; the built-in corpus check
  runs when the pack folder exists and is skipped otherwise.
- Mutation sweep: seeded SplitMix64, 600 variants (byte flips, truncation, duplication of lines,
  insertion of brackets, NULs, long runs), each validated and imported into a temp store with a
  fake trial; asserts time bound, the three outcomes, and byte-identical store for refusals.
- Store: golden `user-presets-v1.json`, newer version, unreadable, failing writer (rollback).
- Trial state machine: fake `PresetTrialRunning` returning each outcome; the "died during trial"
  and "died while proving" recoveries are simulated by constructing a second library on the same
  directory without finishing the first.
- Real engine (simulator): valid synthetic preset passes; bad equations fail with the engine's
  message; a nested-loop preset times out and later trials report unavailable; presets built at
  the static limits (nesting 64, 8,192-byte statements) do not crash the process; the visible
  renderer keeps presenting frames of its preset during and after failing trials.
- App: coordinator tests with a fake loader and fake trial; XCUITests import through a launch
  argument (the system picker is not driven), as AUD-001 does.

## Complexity Tracking

No constitution deviation.
