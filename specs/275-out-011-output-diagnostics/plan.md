# Implementation Plan: OUT-011 Output Connection Diagnostics

**Branch**: `feature/out-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A pure value type `OutputDiagnostics` (PresentationLifecycle) is either `.disconnected` or `.connected(OutputReadings)`
and formats to labelled rows and one text block. `ExternalDisplayCoordinator.outputDiagnostics` builds it at read time
from the first settled display's live slot: the slot's scene screen (`UIScreen` native bounds and scale, bounds and
scale, `maximumFramesPerSecond`, trait `displayGamut`, `potentialEDRHeadroom`/`currentEDRHeadroom`, `mirrored`,
`overscanCompensation`) or, in DEBUG, the stand-in readings; plus OUT-003's resolved drawable (only when the visual is
in that slot), OUT-004's resolved pixel aspect and OUT-006's output mode. Without a settled display, or once its slot
is gone, it is `.disconnected`. Nothing is stored. A new `OutputDiagnosticsSection` in Settings (after External Display)
reads it in a 1 s `TimelineView` and through observation of `hasExternalDisplay`, so a disconnect re-renders at once.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 / iOS SDK 27.2; CI Xcode 26)
**Primary Dependencies**: UIKit (`UIScreen`, `UIPasteboard` local-only), SwiftUI
**Storage**: none (no settings keys; OUT-011-R9)
**Testing**: XCTest: PresentationLifecycle pure tests (host, Linux-safe), app tests and one XCUITest on simulator "OUT11 iPhone 17" (iOS 27.2)
**Target Platform**: iOS/iPadOS 26 and 27
**Performance Goals**: reads only while Settings shows the section (1 Hz); nothing on the render or audio path
**Constraints**: owner rule 7 budgets; Xcode 26 type-check budget; PresentationLifecycle builds on Linux (no UIKit in the package file)
**Scale/Scope**: one package file, coordinator property, slot stand-in field, one section view, DEBUG fake size + probe

## Constitution Check

- I. Public Apple APIs only: documented `UIScreen` properties, `UITraitCollection.displayGamut`, `UIPasteboard`. PASS.
- IV/V. No capture or compatibility claims; values the system does not report read "Not available". PASS.
- VI. Modular boundaries: formatting and the snapshot in a package; UIKit reading in the app. PASS.
- VII. Real-time audio: untouched. PASS.
- X. Evidence: pure tests, app acceptance test, UI test on the simulator (never device evidence); HDMI on D1 `{device}`. PASS.
- Privacy: no storage, no network; copy is local-only and user-initiated. PASS.

Post-design re-check: unchanged, PASS.

## Project Structure

```text
Packages/PresentationLifecycle/Sources/PresentationLifecycle/OutputDiagnostics.swift      (new, C1)
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/OutputDiagnosticsTests.swift (new)
Apps/projectM-iOS/ExternalDisplay/OutputScreenReader.swift                               (new, C2: UIScreen → readings)
Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift                                   (standInReadings, C2)
Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift                       (outputDiagnostics, C2)
Apps/projectM-iOS/Views/OutputDiagnosticsSection.swift                                   (new, C3)
Apps/projectM-iOS/Views/SettingsView.swift                                               (one line, C3)
Apps/projectM-iOS/Debug/UITestExternalDisplay.swift                                      (720p stand-in, probe, C4)
Apps/projectM-iOS/Tests/OutputDiagnosticsAppTests.swift, UITests/OutputDiagnosticsUITests.swift (new)
```

**Structure Decision**: existing layout; PresentationLifecycle is already in CI's `PKGS_LIBRARY`. No ADR: no default
is overridden and no settings key is added.

## Complexity Tracking

None.
