# Implementation Plan: PRE-010 Preset Quick Audition

**Branch**: `feature/pre-010` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/168-pre-010-quick-audition/spec.md`

## Summary

A preview ("audition") of a preset from the browser that loads it on screen and changes nothing else,
with Keep (commit as a normal selection) and Cancel (reload the original). All state is in memory.

App only; no package changes:

- `Coordinators/PresetCoordinator+Audition.swift` (new): `PresetAudition` (original, showing,
  loading, list scope, notice), `canPreview`, `preview(_:from:)`, `keepAudition()`,
  `cancelAudition()`, the texts and the library-lane announcements (research PRE-010-D1 to D5).
- `PresetCoordinator.swift` (focused edits): the stored `audition` and its generation counter;
  `onScreen` (the preview, else `current`); `select` ends a preview after a successful load (R8) and
  tells the imported-preset guard about the preset actually on screen; the post-load bookkeeping moves
  into `didSelect(_:)` so Keep reuses it without a second load; `setScope`, `planUpcoming`, the
  session exclusion and the loader become reachable from the extension file; the row label adds
  ", previewing".
- Views: `PresetAuditionBar.swift` (new; bar with name, Keep, Cancel — Escape — and the failure
  notice); `PresetBrowserView` (bar as a bottom inset on the stack, cancel on close, Preview in the
  row's menu, leading swipe and VoiceOver actions via a new optional `previewScope` row parameter);
  the browser's list views pass their list's scope to the rows.
- No AppCoordinator, SettingsView, VisualizerView or Compositor change: the browser already holds the
  `PresetCoordinator`, whose `announceLibrary` is wired to the shared announcer's library lane.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/audition.md](contracts/audition.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PresetLibrary (existing). None new.

**Storage**: none (in memory only; no new keys or files).

**Testing**: XCTest. App unit tests `PresetAuditionAcceptanceTests` (acceptance S1 with a fake loader,
injected clock for PRE-006's dwell, a scene-history coordinator over the same settings and SCN-002's
canonical document bytes; Keep; failures; R8), one UI test `PresetAuditionUITests` (under 30 s) on
simulator "PRE10 iPhone 17" (iOS 27.2) with the DEBUG tag seed (`-uitestSeedPresetTags`).

**Target Platform**: iOS 26+.

**Performance Goals**: a preview costs one preset load; Cancel one more. No warm-up during previews.

**Constraints**: Type-check budget (300 ms per body, 200 ms per expression); Linux packages untouched;
`check_status_events.py` covers the new files.

## Constitution Check

| Principle | Status |
|---|---|
| Public Apple APIs only | Pass: SwiftUI and existing app code only. |
| Privacy / local-first | Pass: nothing stored, nothing sent; R10. |
| Photosensitivity (ACC-002) | Pass: no Preview for flagged presets while Reduce flashing is on; FX-019's envelope limits every frame. |
| Honest evidence | Simulator runs are not device evidence; no device task needed. |
| Engine untouched | Pass: uses the existing `PresetLoading.load` (projectM's normal blend). |

## Project Structure

```text
Apps/projectM-iOS/Coordinators/PresetCoordinator.swift            (edited, focused)
Apps/projectM-iOS/Coordinators/PresetCoordinator+Audition.swift   (new)
Apps/projectM-iOS/Views/PresetAuditionBar.swift                   (new)
Apps/projectM-iOS/Views/PresetBrowserView.swift                   (bar, row actions)
Apps/projectM-iOS/Views/PresetFolderView.swift, PresetTagChips.swift, PresetCollectionView.swift,
  RecentPresetsView.swift, UserPresetsView.swift                  (pass the list scope to rows)
Apps/projectM-iOS/Tests/PresetAuditionAcceptanceTests.swift       (new)
Apps/projectM-iOS/UITests/PresetAuditionUITests.swift             (new)
scripts/check_status_events.py                                    (cover the new files)
```

## Complexity Tracking

None.
