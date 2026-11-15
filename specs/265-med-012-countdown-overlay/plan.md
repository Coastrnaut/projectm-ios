# Implementation Plan: MED-012 Countdown Overlay

**Branch**: `feature/med-012` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/265-med-012-countdown-overlay/spec.md`

## Summary

The countdown is a second MED-011-style overlay: a MED-009 `TextLayerSource` (name "countdown")
attached as a `.countdown` entry on top of each compositor visual's stack (above the clock), fed a new
message only when the shown second changes. Plain Swift in the `TextLayer` target (builds on Linux):
`MonotonicClock` (injected seconds; `ContinuousMonotonicClock` reads `ContinuousClock`),
`CountdownTimer` (pure value: duration, accumulated running time, start instant, finished flag;
`remaining(at:) = max(0, duration − elapsed)`; `advance(at:)` returns true exactly once at zero),
`CountdownFormat` ("mm:ss" / "h:mm:ss" of the remaining seconds rounded up) and
`CountdownOverlaySettings` (shown, duration, start-from-new-cues, `TextOverlaySpec` style; versioned
JSON). Shared with MED-011 instead of copied: `ChangedText` (the "report only a changed string"
helper that `ClockText` now uses), `StoredOverlayDecodeResult` (generic stored-value result;
`ClockOverlayDecodeResult` becomes its alias) and, in the app, `OverlayTextLayers` (weak layer list,
spec push, frame count) plus `Compositor.attachOverlay(_:kind:)` (`attachClock` calls it).

SceneFormat gains an optional top-level `countdown` field (`{"durationSeconds": N}`, N 1…5,940;
anything else reads as absent and stays verbatim in `extra`). The app's show path records it when
"Start From New Cues" is on (`ShowLook`) and starts the countdown when a cue applies a scene that has
it (`ShowSceneApply`). Launch restore and reopen ignore it.

The app adds `CountdownOverlayStore` (`settings.countdown.overlay`), `CountdownOverlayCoordinator`
(main actor, `@Observable`: settings, timer, Start/Pause/Reset, cue start, a tick task that sleeps to
the next shown-second change only while running, the finished announcement on a new `.countdown`
announcer lane), a "Countdown" section in Settings after Clock, and DEBUG
`-uitestCountdownFixed <seconds>` (a frozen monotonic clock) with a `countdownProbe`
("<text|none> <state> finished=<n> drawn=<frames>").

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2; CI also Xcode 26: explicit closure types)

**Primary Dependencies**: Foundation, Swift `ContinuousClock`, MED-009 `TextLayer`, Compositor,
SceneFormat; SwiftUI (Settings)

**Storage**: UserDefaults `settings.countdown.overlay` (JSON, `"version": 1`); scene field `countdown`

**Testing**: TextLayerTests (`CountdownTimerTests` on every platform; `CountdownLayerTests` through
the real compositor with Metal), SceneFormatTests (`SceneCountdownTests`), app
`CountdownOverlayTests` (store, coordinator with an injected clock, cue apply), one UI test

**Target Platform**: iOS/iPadOS 26.0+; package code also macOS 15 and Linux

**Performance Goals**: at most one string, one rasterization per second while running; none when
stopped or finished; per frame nothing new

**Constraints**: no wall time, no network, no new shader, no new permission, public APIs only; no
flashing at zero

**Scale/Scope**: ~2 package source files, ~4 app files, ~5 test files

## Constitution Check

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | Foundation, Swift stdlib clocks, existing CoreText/Metal, SwiftUI | Pass |
| VI. Modular boundaries | Countdown logic in `TextLayer`, scene field in `SceneFormat`; the app owns storage, ticks and UI | Pass |
| VII. Real-time audio safety | No audio path change | Pass |
| VIII. Upstream fidelity | projectM untouched | Pass |
| IX. Pinned dependencies | None added | Pass |
| X. Evidence | Deterministic tests with injected clocks; device readability is a `{device}` task | Pass |
| Privacy / FR-068 | Local only; the key is listed for backup, erase and the device privacy check | Pass |
| Flash safety | Holds "00:00", no flashing; the composite flash guard still applies | Pass |

Post-design re-check: unchanged (Pass). No ADR: no default is overridden.

## Project Structure

```text
specs/265-med-012-countdown-overlay/  spec, plan, research, data-model, quickstart, contracts/countdown-overlay.md, tasks

Packages/Compositor/Sources/TextLayer/
├── CountdownOverlay.swift   # MonotonicClock, CountdownTimer, CountdownFormat, CountdownSchedule, CountdownOverlaySettings
├── ClockOverlay.swift       # ChangedText, StoredOverlayDecodeResult shared (ClockText uses them)
└── TextLayerKind.swift      # + LayerKind.countdown
Packages/Compositor/Tests/TextLayerTests/CountdownTimerTests.swift, CountdownLayerTests.swift
Packages/SceneFormat/Sources/SceneFormat/SceneCountdown.swift (+ Tests/SceneCountdownTests.swift)

Apps/projectM-iOS/
├── Coordinators/OverlayTextLayers.swift (shared with the clock; Compositor.attachOverlay)
├── Coordinators/CountdownOverlayStore.swift, CountdownOverlayCoordinator.swift
├── Coordinators/ClockOverlayCoordinator.swift (uses OverlayTextLayers)
├── Coordinators/AppCoordinator.swift (create, attach in the four prepare functions, announcer), AppSettings.swift (key)
├── Coordinators/AppCoordinator+Show.swift, ShowSceneSnapshot.swift (cue record and start)
├── Coordinators/AccessibilityAnnouncer.swift (+ .countdown lane)
├── Views/CountdownSection.swift, SettingsView.swift (one line), Debug probe and fixture
├── Tests/CountdownOverlayTests.swift (+ SettingsTests, LibraryBackupAppTests lists)
└── UITests/CountdownOverlayUITests.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift  # includedKeys
scripts/run_device_tests.py                                          # ALLOWED_KEYS
```

## Complexity Tracking

None.
