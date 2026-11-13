# Implementation Plan: SCN-002 Scene Autosave

**Branch**: `feature/scn-002` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/067-scn-002-scene-autosave/spec.md`

## Summary

The app keeps one **current scene** (an SCN-001 document) for the shown visual and autosaves it:

1. **SceneFormat** gains one public entry point, `SceneJSON.parse(_:)` (the existing bounded reader,
   1 MiB and depth 32), so the app can embed the Text visual's stored JSON as a scene text asset.
2. **App, `SceneAutosaveStore`** (Coordinators): the files `current.scene`, `current.scene.bak` and
   `current.scene.tmp` in `Application Support/Scenes`. Save: write the temporary file, full storage
   flush (`F_FULLFSYNC`, `fsync` fallback), remove the old backup, hard-link the current main file as
   the backup (only when it was read or written good), `rename` the temporary file over the main file,
   flush the folder. Load: remove a leftover temporary file, read at most 1 MiB + 1 byte, decode and
   `liveState` (SCN-001 validation, MOD-013 restore); main → backup → nothing, one event per fallback.
   A test hook can throw before any step (injected failure).
3. **App, `SceneAutosaveDebouncer`**: a pure state machine on an injected clock: quiet 1 s, maximum
   latency 5 s (research SCN-002-D3).
4. **App, `SceneAutosaveCapture`**: pure functions between the app's scene inputs (visual, bar count,
   linear orientation and spacing, glow, text spec, stored photo and video IDs, live bindings) and a
   document, merging what the app does not own from the restored document (unknown layers at their
   index, matched known layers' instance IDs, values and composites, document fields, other assets,
   other parameter values, bindings, expressions, modulation, preserved edges, scene ID and name).
5. **App, `SceneAutosaveCoordinator`** (main actor): restores at launch (before UI-test seeds), tracks
   the inputs with Observation, debounces edits, commits at once on a visual change, when Settings
   closes, on background and on terminate (synchronously), encodes and writes on one serial
   background queue, publishes the committed revision (DEBUG probe), logs events privately.
6. **AppCoordinator**: owns the coordinator, applies restored bindings to the native spectrum when it
   is created, resets the scene folder with `-uitestResetNotice`, commits when Settings closes.
   **NativeSpectrumHost** exposes its live bindings. **VisualizerView** shows the DEBUG probe.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 here; Xcode 26 and Linux in CI: explicit closure types, no
long untyped numeric expressions)

**Primary Dependencies**: SceneFormat, ParameterGraph, VisualParameters, TextLayer, Foundation, POSIX
file calls (`open`, `write`, `fcntl`, `fsync`, `link`, `rename`, `unlink`; Darwin)

**Storage**: `Library/Application Support/Scenes` (two committed files at most, a few KB each)

**Testing**: app unit tests (`projectM-iOSTests`, simulator), one UI test (`SceneAutosaveUITests`), the
existing Text, Glow and Photo UI suites as regression checks, SceneFormat package tests (host and Linux
shape)

**Target Platform**: iOS 26+ app; SceneFormat also Linux

**Project Type**: iOS app + Swift package

**Performance Goals**: capture on the main actor is a struct copy (< 1 ms); encode and write off the
main thread, at most one commit per quiet period; launch read ≤ 1 MiB (typically < 4 KB)

**Constraints**: never on the frame loop or an audio callback; no file timestamps or disk-capacity
APIs; no networking; no C stdio globals; no wall-clock assertions in tests

**Scale/Scope**: one scene; SCN-001 limits (8 layers, 16 assets, 1 MiB)

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Foundation and POSIX file calls (public). Pass. |
| VI Modular boundaries | The format stays file-free in SceneFormat; files and app wiring stay in the app; renderers unchanged except a read-only bindings accessor. Pass. |
| VII Real-time safety | Capture on edits only; writes on a background queue; nothing on the frame loop or audio thread. Pass. |
| IX Dependencies | None added. Pass. |
| X Evidence | Unit tests with injected failures and a fake clock; UI kill-and-relaunch test; device force-quit task left open `{device}`. Pass. |
| Security | The saved file is read as untrusted input (SCN-001 limits, validation; a bad file never blocks launch). Pass. |
| Privacy | Only the user's own settings, text and store identifiers; no audio, paths or device data; policy updated. Pass. |

## Project Structure

```text
specs/067-scn-002-scene-autosave/   spec, plan, research, data-model, contracts/scene-autosave.md, quickstart, tasks
Packages/SceneFormat/Sources/SceneFormat/SceneJSON.swift        + SceneJSON.parse
Packages/SceneFormat/Tests/SceneFormatTests/SceneJSONTests.swift + parse test
Apps/projectM-iOS/Coordinators/SceneAutosaveStore.swift         files, atomic save, validated load
Apps/projectM-iOS/Coordinators/SceneAutosaveDebouncer.swift     quiet / maximum latency
Apps/projectM-iOS/Coordinators/SceneAutosaveCapture.swift       inputs ↔ document, merge
Apps/projectM-iOS/Coordinators/SceneAutosaveCoordinator.swift   tracking, commits, restore, probe
Apps/projectM-iOS/Coordinators/AppCoordinator.swift             wiring (small)
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift              bindings accessor (one line)
Apps/projectM-iOS/Views/VisualizerView.swift                    DEBUG probe
Apps/projectM-iOS/Tests/SceneAutosave*Tests.swift               unit tests
Apps/projectM-iOS/UITests/SceneAutosaveUITests.swift            kill and relaunch
docs/adr/0028-scene-document-format.md                          amendment
docs/privacy-policy.md                                          stored-data list
```

**Structure Decision**: the autosave lives in the app target (it needs the app's settings, stores and
hosts; research SCN-002-D1); the only package change is the public JSON entry point. No `project.yml`
or CI change: the app target already includes every file under `Apps/projectM-iOS`.

## Complexity Tracking

None.
