# Implementation Plan: UIX-002 Quick Scene Switcher

**Branch**: `feature/uix-002` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/103-uix-002-quick-scene-switcher/spec.md`

## Summary

A compact search overlay over the visualizer lists the show's cues (the only named local scenes),
filters them as the user types and recalls the chosen one through SHOW-001's `go(to:)` path, so
validation, SCN-012's repair report, notices, undo restart and the saved position are unchanged.
Everything is app-side SwiftUI; no package changes.

- `SceneSwitcher.swift` (Coordinators): pure value types and the model.
  - `SceneSwitcherEntry` (cue ID, number, label, scene name, active, missing) built from a
    `ShowCueList` plus the show's scene names and unreadable set.
  - `SceneSwitcherFilter.results(_:query:)`: trimmed query, folded with case, diacritic and width
    insensitivity; contains on label or scene name; prefix or word-start matches first, show order
    kept within each group (research UIX-002-D2).
  - `SceneSwitchLatencyProbe`: begin at the choice, finish at the applied state or the repair
    request, on an injected monotonic clock (seconds, `ProcessInfo.systemUptime` in the app;
    research UIX-002-D3). Budget 0.250 s. Records the last `SceneSwitchMeasurement`.
  - `SceneSwitcherModel` (`@MainActor @Observable`): `isOpen`, `query`, `highlightedCueID`,
    `abandonedQuery`; `open(entries:)`, `queryChanged(entries:)`, `moveHighlight(by:entries:)`,
    `close(chose:)`; the highlight rules of UIX-002-R5 and the reopen rule of R6; `focusReturnRevision`
    bumped on a close without a choice.
- `AppCoordinator+SceneSwitcher.swift` (Coordinators): `openSceneSwitcher()`,
  `closeSceneSwitcher()`, `toggleSceneSwitcher()`, `sceneSwitcherEntries`, `chooseSwitcherScene(_:)`
  (close, begin the probe, `show.go(to:)`, finish "failed" if neither end point fired, announce
  "Scene: <label>" on success), `announceSwitcherCount(_:)`.
- `AppCoordinator.swift`: one stored property `let sceneSwitcher = SceneSwitcherModel()` (kept small;
  the file is shared with parallel features).
- `AppCoordinator+Show.swift` `connectShow()`: the `applyScene` closure calls
  `sceneSwitcher.probe.finish(.applied, …)` after `applyShowScene`, the `requestRepair` closure calls
  `finish(.repairShown, …)` before presenting; both are no-ops without a pending measurement.
- `AccessibilityAnnouncer.swift`: new `AnnouncementKind.search`; text helpers
  `sceneSwitcherCountText(_:)` ("1 scene", "3 scenes", "No matching scenes") and
  `sceneChosenText(_:)` ("Scene: Drop").
- `Views/SceneSwitcherView.swift`: the card (dim backdrop that closes on tap; header "Scenes" +
  Close; `TextField` "Search scenes" bound to the model's query with `@FocusState` set on appear,
  `.onKeyPress` for Up, Down and Escape, `.onSubmit` for Return, `.submitLabel(.go)`, no
  autocorrection or capitalization; the count line; a `ScrollView` + `LazyVStack` of entry buttons
  inside a `ScrollViewReader` that keeps the highlight visible). Max width 480 pt, max height 70 % of
  the container; entries wrap at accessibility sizes. Appearance through
  `reduceMotionAware(MotionPolicy.controlsFade, …)`. DEBUG probe `sceneSwitcherProbe` under
  `-uitestDiagnostics`.
- `Views/ShowControls.swift`: `ShowCueRow` gains a "Scenes" button (`showSceneSwitcher`,
  `magnifyingglass`) with an `@AccessibilityFocusState` that follows `focusReturnRevision`;
  `ShowKeyCommands` adds ⌘K and drops the arrow and Page keys while the switcher is open.
- `Views/VisualizerView.swift`: two small edits: the overlay in the ZStack (when open and Settings
  is closed) and `SceneHistoryKeyCommands` also off while the switcher is open.
- `scripts/check_status_events.py`: the new view joins the checked list (announcements through the
  announcer only).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2, strict concurrency), SwiftUI, iOS 26.0 deployment
**Primary Dependencies**: app target only; `ShowControl` (`ShowCueList`, `ShowCue`), existing
`ShowCoordinator`, `SceneRepairCoordinator`, `AccessibilityAnnouncer`, `MotionPolicy`
**Storage**: none (the query lives in memory; UIX-002-R12)
**Testing**: XCTest app unit tests (`projectM-iOSTests`, new `SceneSwitcherTests.swift`), XCUITest
(new `SceneSwitcherUITests.swift`) with `-uitestShowSeed` and `-uitestShowRepairSeed`
**Target Platform**: iPhone and iPad, iOS/iPadOS 26.0+; evidence on an own iOS 27.2 simulator
**Project Type**: mobile app
**Performance Goals**: choice → applied state ≤ 250 ms on the simulator (UIX-002-R8, S2); filtering
256 cues < 5 ms (S6)
**Constraints**: public APIs only, no networking, no C stdio, no main-actor mutation in
setUp/tearDown, no wall-clock assertions (the probe uses the monotonic uptime clock), unit tests
≤ 10 s, UI tests < 30 s each
**Scale/Scope**: up to 256 cues (`ShowCueList.maximumCues`)

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: SwiftUI `TextField`, `FocusState`, `onKeyPress`, `keyboardShortcut`, `AccessibilityFocusState`. |
| II–V. Capture | Not affected: the switcher never touches the audio source (UIX-002-R7). |
| VI. Modular boundaries | Pass: app-only UI over the existing `ShowCoordinator` API; the filter and probe are pure types tested in isolation. |
| VII. Real-time audio safety | Not affected (main actor only, no audio callback code). |
| VIII. Upstream fidelity | Not affected. |
| IX. Pinned dependencies | No new dependency. |
| X. Evidence-based quality | Pass: unit tests for filter, highlight and probe; UI tests for focus, latency and repair; simulator numbers labelled as such, no device claims. |
| Privacy | Pass: nothing stored or sent. |

Post-design re-check: unchanged (no ADR needed; nothing overrides a default or a prior ADR).

## Project Structure

### Documentation (this feature)

```text
specs/103-uix-002-quick-scene-switcher/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/scene-switcher.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Apps/projectM-iOS/
├── Coordinators/
│   ├── SceneSwitcher.swift                  # new: entry, filter, probe, model
│   ├── AppCoordinator+SceneSwitcher.swift   # new: open/close/choose, announcements
│   ├── AppCoordinator+Show.swift            # probe end points in connectShow()
│   ├── AppCoordinator.swift                 # one stored property
│   └── AccessibilityAnnouncer.swift         # kind `search`, two texts
├── Views/
│   ├── SceneSwitcherView.swift              # new: the overlay card
│   ├── ShowControls.swift                   # Scenes button, ⌘K, keys off while open
│   └── VisualizerView.swift                 # overlay + undo keys off while open
├── Tests/SceneSwitcherTests.swift           # new
└── UITests/SceneSwitcherUITests.swift       # new
scripts/check_status_events.py               # new view in CHECKED
```

**Structure Decision**: app target only; no package, because the switcher is UI over the app's
`ShowCoordinator` and the filter needs only Foundation.

## Complexity Tracking

None.
