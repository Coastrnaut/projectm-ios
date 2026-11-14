# Implementation Plan: MED-006 Image Slideshow

**Branch**: `feature/med-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/127-med-006-image-slideshow/spec.md`

## Summary

The Photo visual's layer (`ImageLayerSource`) already draws one stored picture and caches it as a
still layer (CMP-013). MED-006 keeps a list of up to 20 stored pictures (FILE-008 references in the
same Photos folder) and a plain-Swift schedule that, ticked once per shown frame with the monotonic
clock and the tempo grid, decides when the next slide is due. The layer gains a one-entry prepared
slot so the next slide is decoded ahead and the change is a single-frame cut that renders once
(research MED-006-D2, D5).

In `Packages/Compositor` (target `ImageLayer`; plain Swift parts build on Linux):

- New `Slideshow.swift`: `SlideshowSettings`, `SlideshowMode`, `SlideshowBeatGrid`,
  `SlideshowSchedule`, `SlideshowSafetyFloor` (contract C1, C2).
- `ImageLayerSource.preload(_:)` and adoption of a prepared texture in `content`'s setter (C3).

In `Packages/SceneFormat`: `SceneSlideshow` and `SceneAsset.photoSlideshow` (C5; no version change).

In `Packages/LibraryBackup`: `settings.photo.slideshow` included in backups and erased with
"Photos and videos" (research D8).

In the app:

- `SlideshowStore` (new) and `PhotoStore` protection of slide references (D1).
- `SlideshowCoordinator` (new): settings, imports (several at once), list edits, thumbnails, the
  schedule, announcements through the shared announcer.
- `PhotoVisualHost.beforeFrame` and `preload`; `AppCoordinator` wiring: content choice, tick, tempo
  grid, safety floor, scene inputs and restore (autosave, undo, cues) (D6, D7).
- `SlideshowSection` (new view file) mounted after the Photo section in Settings (D9).
- DEBUG: `slideshowProbe`, `-uitestSeedPhoto slideshow5`.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/slideshow.md](contracts/slideshow.md); checks: [quickstart.md](quickstart.md). No ADR: no
default is overridden; the scene field follows the optional-field rule (as MED-003/MED-004), and the
cut-only choice is recorded in the spec's Clarifications.

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: Compositor (`ImageLayer`), SceneFormat, LibraryBackup, LocalPortability,
PerformanceControl (tempo snapshot), FlashSafety (`SafetyClamp`), SwiftUI, PhotosUI, ImageIO
(thumbnails). No new dependency, no networking, no photo library permission.

**Storage**: one UserDefaults key, `settings.photo.slideshow` (JSON Data); slide copies in
Application Support/Photos as FILE-008 references.

**Testing**: `Packages/Compositor`: `SlideshowTests` (plain Swift, Linux shape: settings sanitizing
and JSON; the five-slide schedule in Time and Beats; uncertain-grid fallback; safety floor at 240 BPM;
pauses add nothing; timing change restarts) and `SlideshowLayerTests` (Metal: preload, one render per
change, no transparent frame, the five solid colours in order through the compositor).
`Packages/SceneFormat`: `SceneSlideshowTests`. `Packages/LibraryBackup`: policy tests gain the key.
App: `SlideshowTests` (store, protection, coordinator order and edits, persistence, scene round trip,
backup include, erase). UI: `SlideshowUITests` with `-uitestSeedPhoto slideshow5`.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (CPU parts).

**Project Type**: iOS app plus SwiftPM package targets.

**Performance Goals**: no per-frame allocation on frames without a change; decoding off the main
thread ahead of the change.

**Constraints**: public APIs only; explicit closure types; typed steps for strings and numbers; no C
stdio globals; no main-actor mutation in setUp/tearDown; no wall-clock assertions; unit tests about
1-2 s, UI test under 30 s (owner rule 7). Parallel work: FX-004 (hue shift) and MIDI-002 (MIDI
monitor); shared-file edits (SettingsView, AppCoordinator, AppSettings, LibraryBackup policies,
VisualizerView) kept to a few lines.

**Scale/Scope**: 4 new app sources (store, coordinator, section, seed extension), 1 new package
source, about 18 files touched, 5 new test files.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | SwiftUI, PhotosUI `PhotosPicker` (out of process), ImageIO thumbnails | Pass |
| VI Modular boundaries | Schedule and settings in `ImageLayer` (plain Swift, no tempo or app import: the grid is a plain value); scene field in SceneFormat; the app wires tempo and safety | Pass |
| VII Real-time safety | No audio code touched; the tick runs on the display link (main actor), never on an audio thread; decode on the layer's background queue | Pass |
| X Evidence | Injected clock and grid, simulator fixtures; the real multi-select picker is `{device}` | Pass |
| Privacy | Sanitized copies only, no photo library permission, nothing sent; backup like MED-001 | Pass |
| Photosensitivity | Safety floor from the profile; composite flash guard on every frame; cuts only | Pass |
| No networking | None; `check_compliance.py` | Pass |
| Accessibility | Labels, VoiceOver row actions, ACC-005 seconds slider, announcer, no animation | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/127-med-006-image-slideshow/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/slideshow.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/ImageLayer/
├── Slideshow.swift                # new (plain Swift)
└── ImageLayerSource.swift         # preload + prepared adoption
Packages/Compositor/Tests/CompositorTests/
├── SlideshowTests.swift           # new (Linux shape)
└── SlideshowLayerTests.swift      # new (Metal)
Packages/SceneFormat/Sources/SceneFormat/SceneSlideshow.swift   # new
Packages/SceneFormat/Tests/SceneFormatTests/SceneSlideshowTests.swift   # new
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, LibraryErasePolicy.swift
Apps/projectM-iOS/
├── Coordinators/SlideshowStore.swift, SlideshowCoordinator.swift   # new
├── Coordinators/PhotoStore.swift, AppSettings.swift, AppCoordinator.swift
├── Coordinators/SceneAutosaveCapture.swift, ShowSceneSnapshot.swift
├── Coordinators/AppCoordinator+SceneHistory.swift, AppCoordinator+Show.swift
├── Views/SlideshowSection.swift   # new
├── Views/SettingsView.swift, VisualizerView.swift
├── Visuals/PhotoVisualHost.swift
├── Debug/UITestPhotoFixture.swift
├── Tests/SlideshowTests.swift     # new
└── UITests/SlideshowUITests.swift # new
scripts/run_device_tests.py        # allowed key
```

**Structure Decision**: extend the `ImageLayer` target and the Photo visual; no new target.

## Complexity Tracking

None.
