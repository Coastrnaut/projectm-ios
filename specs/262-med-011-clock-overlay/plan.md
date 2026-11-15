# Implementation Plan: MED-011 Clock Overlay

**Branch**: `feature/med-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/262-med-011-clock-overlay/spec.md`

## Summary

The clock is a MED-009 `TextLayerSource` fed one message, the formatted local time, attached as a
`.clock` layer on top of each compositor visual's stack (Photo, Video, Camera, Text) exactly like
MED-010's logo. Plain Swift in the `TextLayer` target (builds on Linux): `ClockSource` (injected
date and time zone; `SystemClockSource` reads `Date()` and `TimeZone.current`), `ClockHourCycle`,
`ClockOverlaySettings` (shown, hour cycle, seconds, a `TextOverlaySpec` style; versioned JSON),
`ClockFormatter` (`DateFormatter` with a fixed pattern and an injected locale and time zone),
`ClockText` (the string for a date, reported only when it changes) and `ClockSchedule` (delay to the
next second boundary). `LayerKind.clock` (one per stack). `TextLayerSource` gains a layer name and a
`rasterizationCount` (diagnostics, tests); nothing else in MED-009 changes.

The app adds `ClockOverlayStore` (`settings.clock.overlay`), `ClockOverlayCoordinator` (main actor,
`@Observable`: settings, attach to compositors, a one-per-second tick task aligned to second
boundaries while the clock is shown and a layer is live), a "Clock" section in Settings' media
sections, and DEBUG `-uitestClockFixed <epoch seconds>` (a fixed clock in UTC with `en_US_POSIX`)
plus a `clockProbe` diagnostics element ("<string> drawn=<frames>").

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2; CI also Xcode 26: explicit closure types)

**Primary Dependencies**: Foundation (`DateFormatter`, `TimeZone`, `Locale`), MED-009 `TextLayer`,
Compositor; SwiftUI (Settings)

**Storage**: UserDefaults `settings.clock.overlay` (JSON, `"version": 1`, a few hundred bytes)

**Testing**: TextLayerTests (`ClockFormatterTests` on every platform; `ClockLayerTests` through the
real compositor with Metal), app `ClockOverlayStoreTests`, one UI test `ClockOverlayUITests`

**Target Platform**: iOS/iPadOS 26.0+; package code also macOS 15 and Linux

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: per frame nothing new (the text layer's clear and blit, or a CMP-013 reuse);
a format at most once per second on the main actor; a rasterization only when the string changes

**Constraints**: no network, no new shader, no new permission, public APIs only

**Scale/Scope**: ~2 package source files, ~3 app files, ~4 test files

## Constitution Check

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | Foundation, CoreText (existing), Metal (existing), SwiftUI | Pass |
| VI. Modular boundaries | Clock logic in `TextLayer` (Foundation only); the app owns storage, ticking and UI | Pass |
| VII. Real-time audio safety | No audio path change | Pass |
| VIII. Upstream fidelity | projectM untouched | Pass |
| IX. Pinned dependencies | None added | Pass |
| X. Evidence | Deterministic host/Linux/simulator tests with injected clocks; device readability is a `{device}` task | Pass |
| Privacy / FR-068 | Local time only, no networking API, stored settings listed for backup and erase | Pass |
| SHD-011 | No Metal source | Pass |

Post-design re-check: unchanged (Pass). No ADR: no default is overridden.

## Project Structure

```text
specs/262-med-011-clock-overlay/  spec, plan, research, data-model, quickstart, contracts/clock-overlay.md, tasks

Packages/Compositor/Sources/TextLayer/
├── ClockOverlay.swift          # ClockSource, ClockHourCycle, ClockOverlaySettings (+ JSON), ClockFormatter, ClockText, ClockSchedule
├── TextLayerKind.swift         # + LayerKind.clock
└── TextLayerSource.swift       # + name, rasterizationCount
Packages/Compositor/Tests/TextLayerTests/
├── ClockFormatterTests.swift   # S1, S4, schedule, settings JSON (every platform)
└── ClockLayerTests.swift       # S2, S3 through the compositor (Metal)

Apps/projectM-iOS/
├── Coordinators/ClockOverlayStore.swift, ClockOverlayCoordinator.swift (+ Compositor.attachClock)
├── Coordinators/AppCoordinator.swift (create, attach in the four prepare functions), AppSettings.swift (key)
├── Views/ClockSection.swift, SettingsView.swift (one line in mediaSections), VisualizerView.swift (DEBUG probe)
├── Tests/ClockOverlayStoreTests.swift (+ SettingsTests, LibraryBackupAppTests lists)
└── UITests/ClockOverlayUITests.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift  # includedKeys
scripts/run_device_tests.py                                          # ALLOWED_KEYS
```

## Complexity Tracking

None.
