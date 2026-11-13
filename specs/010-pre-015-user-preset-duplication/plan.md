# Implementation Plan: PRE-015 User preset duplication

**Branch**: `feature/pre-015` | **Date**: 2026-11-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/010-pre-015-user-preset-duplication/spec.md`

## Summary

"Duplicate to My Presets" copies a bundled preset's bytes (read from the app bundle or the
preset archive) into PRE-012's user-preset store as a new user preset whose record names its
origin. The copy goes through PRE-012's validator and off-screen trial. A plain text editor
edits any playable user preset; a save is validated and tried on the off-screen engine before
the new text replaces the old one, so the last good version stays playable. Copies of locked-pack
presets are held (listed, not playable or editable) while the full-library entitlement is absent.
All store logic extends `PresetLibrary`'s `UserPresets` folder (Foundation only, host-tested);
the record moves to version 2 with a pure migration. The engine trial is PRE-012's existing
`PresetTrialRunning`; `Rendering` and `ANGLERendering` do not change. The app adds a duplicate
action to preset rows and the controls, an editor sheet, and a "Needs the full library" section.

## Technical Context

**Language/Version**: Swift 6.4.2 (strict concurrency), Xcode 27.2 / iOS SDK 27.2 (ADR-0002)

**Primary Dependencies**: none new. Foundation, SwiftUI (`TextEditor`, `TextField`,
`confirmationDialog`, `interactiveDismissDisabled`), Observation.

**Storage**: unchanged layout under `<Application Support>/UserPresets/` (PRE-012): `index.json`
now version 2, `files/<sha256>.milk` (content-addressed), `quarantine/`, `trial.json`,
`proving.json`, plus `edit.json` (the edit-check record). Migration backup
`index.v1.backup.json` until the version-2 file is saved.

**Testing**: XCTest. `PresetLibrary` with `swift test` on the macOS host; app unit tests and
XCUITests in the `projectM-iOS` scheme on the iOS 27.2 simulator (real engine for the trial and
the visible renderer). `Rendering` and `ANGLERendering` suites are rerun unchanged as a
regression check. Fixtures are synthetic presets written in tests, the PRE-012 v1 golden file,
and the app's own 28 Included presets read from the built app bundle.

**Target Platform**: iOS and iPadOS 26.0+; `PresetLibrary` also builds for macOS 15 and Linux.

**Project Type**: mobile app with SwiftPM packages under `Packages/`

**Performance Goals**: editor opens a 524,288-byte preset in under 2 s on D1 (S7, `{device}`);
duplicate of an Included preset playable within 5 s on the simulator (PRE-012-S5 parity).

**Constraints**: public APIs only; no networking; no new entitlement; no write outside
`UserPresets/`; nothing under `Vendor/` changes; the collections file format is unchanged.

**Scale/Scope**: PRE-012 limits (1,000 presets, 200 quarantined, 4 MiB record).

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| I. Public APIs only | Pass | SwiftUI text controls, Foundation file APIs. `check_compliance.py` stays green. |
| II-V. Capture | n/a | No capture code is touched. |
| VI. Modular boundaries | Pass | Store, migration, naming, lock hold and edit transactions in `PresetLibrary`; reading bundled bytes stays in the app's `RendererPresetLoader`/`PresetArchive`; the engine trial stays behind `PresetTrialRunning`. |
| VII. Real-time audio safety | Pass | No audio code is touched. |
| VIII. Upstream fidelity | Pass | No engine change. |
| IX. Pinned dependencies, license review | Pass | No new dependency. A copy carries its pack's documented basis (ADR-0007) verbatim and records rights as not verified; copies of locked packs stay behind the purchase; edited text is treated as untrusted input (validator + trial). The takedown list applies to duplicates and edits. |
| X. Evidence | Pass | Tests first (red run recorded); host unit tests for every rule; simulator app and UI tests; S7 tagged `{device}`. |

Post-design re-check: unchanged (Pass). The version bump is justified in research D4.

## Project Structure

### Documentation (this feature)

```text
specs/010-pre-015-user-preset-duplication/
├── spec.md
├── plan.md            # this file
├── research.md        # D1-D8
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── user-preset-duplication.md
│   └── user-presets-v2.schema.json
├── checklists/requirements.md
└── tasks.md           # /speckit-tasks
```

### Source Code (repository root)

```text
Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/
├── UserPresetModel.swift        # + PresetDuplicateOrigin, Origin.bundledDuplicate, modifiedAt
├── UserPresetsFile.swift        # version 2, migration 1 → 2
├── UserPresetStore.swift        # + replaceContents, edit record, path guard
├── UserPresetLibrary.swift      # + duplicate, edit, entitlement hold, editor text
└── UserPresetEditing.swift      # NEW: outcomes and words, copy naming, text decoding
Packages/PresetLibrary/Tests/PresetLibraryTests/
├── UserPresetDuplicationTests.swift   # NEW
├── UserPresetEditingTests.swift       # NEW
├── UserPresetsMigrationTests.swift    # NEW (v1 golden → v2)
└── Golden/user-presets-v2.json        # NEW golden fixture
Apps/projectM-iOS/
├── Coordinators/UserPresetsCoordinator.swift  # duplicate, edit, hold, notices
├── Coordinators/PresetCoordinator.swift       # entitlement → user guard, purchase request, reload
├── Coordinators/AppCoordinator.swift          # RendererPresetLoader.bundledData (small)
├── Views/UserPresetEditorView.swift           # NEW editor sheet
├── Views/UserPresetsView.swift                # Edit action, held section, origin in info
├── Views/PresetBrowserView.swift              # row action, duplicate result alert
├── Views/ControlsOverlay.swift                # duplicate the current preset
├── Views/VisualizerView.swift                 # duplicate result alert outside the browser
├── Tests/UserPresetDuplicationAppTests.swift  # NEW (real bundle, 28 Included)
└── UITests/UserPresetEditingUITests.swift     # NEW
docs/privacy-policy.md            # PRE-012 row extended (one line)
docs/test-reports/preset-duplication.md  # NEW evidence report
```

**Structure Decision**: extend the PRE-012 `UserPresets` code; one new Swift file for the
editing vocabulary to keep `UserPresetModel.swift` readable. No new package.

## Design

### Layers

1. **App reads bundled bytes** (`RendererPresetLoader.bundledData(for:)`): Included from the
   bundle file, pack presets from `PresetArchive`. Read-only APIs only.
2. **`UserPresetLibrary.duplicate(source:contents:)`**: lock check → hash check against the index
   hash → takedown → existing copy → validator (reject = refuse) → limits → store add (pending)
   → PRE-012 trial. Returns `PresetDuplicateOutcome`.
3. **`UserPresetLibrary.edit(id:name:text:)`**: editable check → name rules → encode → size →
   no-op detection → takedown / built-in / user duplicates → validator → `edit.json` record →
   trial (in memory) → `store.replaceContents` → clear record. Returns `PresetEditOutcome`.
4. **Entitlement hold**: `setLibraryUnlocked(_:)`; a copy with `requiresLibraryUnlock` is held
   while false: excluded from `playable`, listed in `needsUnlock`, `data(for:)` and
   `editorText(for:)` return nil, no trial runs for it.
5. **App**: `UserPresetsCoordinator` words outcomes and refreshes; `PresetCoordinator` forwards
   entitlement changes before changing the scope, opens the purchase sheet for locked sources
   and held copies, and reloads the current preset after its text was saved.

### Transactions and rollback

- Duplicate: PRE-012's `add` (file, then record; record failure removes the file).
- Edit: write `files/<new sha>.milk` (if absent) → save record → delete the old file. A failed
  record save deletes the new file and leaves memory unchanged. The old file is deleted only
  after the record no longer names it.
- Edit check record: written before the trial, removed after; found at launch → discarded,
  notice "An edit to “X” was not saved because the app closed while checking it." No quarantine.
- Migration 1 → 2: PRE-012/PRE-007 rule; `index.v1.backup.json` until the v2 file is saved.
- Path guard: every write, move and delete in `UserPresetStore` goes through one function that
  refuses a path not inside the store directory (standardized, symlinks resolved) and reports
  the operation to an internal observer used by tests.

### Deterministic tests

- Host: fake trial (`ScriptedTrial`), injected clock and id maker, temporary directories, a
  read-only "bundle" directory with a fixture preset to prove it is never written.
- App: the real 28 Included presets from the test host's bundle with a scripted trial;
  hashes before/after compared with the index's hash.
- UI: launch arguments of PRE-012 (`-uitestResetNotice`, fake entitlement `-uitestUnlocked`),
  real off-screen engine on the simulator.

## Complexity Tracking

No constitution violation. The one structural cost is the record version bump (research D4).
