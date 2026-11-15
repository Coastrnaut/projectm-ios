# Implementation Plan: OUT-014 Output Profile Export

**Branch**: `feature/out-014` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

A pure, Linux-buildable `OutputProfile` value plus `OutputProfileDocument` codec and `OutputDisplayClass` matcher in
PresentationLifecycle (contract C1): sorted-key JSON, format tag and version, strict all-or-nothing validation (16 KB,
field set, enum names, OUT-003 percentage range, OUT-007 `CornerPin` validity, OUT-009 calibration ranges). The app
(contract C2) converts between `ExternalOutputSetting` and the profile (`outputProfile(display:)`, `apply(_:)`), reads
the connected display's class from OUT-011's live readings (`ExternalDisplayCoordinator.outputDisplayClass`), and an
`OutputProfileCoordinator` (owned by the setting) runs export through the system file mover and import through the
file picker, with the different-class confirmation. Settings › External Display gains two rows and a status line
(contract C3). Applying sets the setting's properties, whose existing `didSet`s persist the keys and push to the
external coordinator, so the live output updates inside the call.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 / iOS SDK 27.2; CI Xcode 26)
**Primary Dependencies**: Foundation `JSONEncoder`/`JSONDecoder`/`JSONSerialization` (package); SwiftUI `fileMover` and `fileImporter` (app)
**Storage**: none new: the existing `settings.externalDisplay.*` keys through `ExternalOutputSetting`
**Testing**: XCTest: PresentationLifecycle pure tests (host, Linux-safe), app tests and one XCUITest on simulator "OUT14 iPhone 17" (iOS 27.2)
**Target Platform**: iOS/iPadOS 26 and 27
**Performance Goals**: user-initiated only; nothing on the render or audio path; documents under 2 KB
**Constraints**: owner rule 7 budgets; Xcode 26 type-check budget; no UIKit or Compositor in the package file
**Scale/Scope**: one package file + tests, one app coordinator, small additions to the setting, coordinator, section view

## Constitution Check

- I. Public Apple APIs only: Foundation JSON, SwiftUI file mover/importer, security-scoped URLs. PASS.
- IV/V. No compatibility claims; simulator results are not device evidence. PASS.
- VI. Modular boundaries: format and validation in a package; UIKit/SwiftUI and settings in the app. PASS.
- VII. Real-time audio: untouched. PASS.
- X. Evidence: pure, app and UI tests; projector round trip on D1 is `{device}`. PASS.
- Privacy: no network, no identifiers in the file (leak test), no new storage, untrusted input bounded and validated. PASS.

Post-design re-check: unchanged, PASS.

## Project Structure

```text
Packages/PresentationLifecycle/Sources/PresentationLifecycle/OutputProfile.swift            (new, C1)
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/OutputProfileTests.swift    (new)
Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting+Profile.swift                      (new, C2: convert/apply)
Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift                              (owns the coordinator)
Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift                         (outputDisplayClass, C2)
Apps/projectM-iOS/Coordinators/OutputProfileCoordinator.swift                              (new, C2)
Apps/projectM-iOS/Views/OutputProfileRows.swift                                            (new, C3)
Apps/projectM-iOS/Views/ExternalDisplaySection.swift                                       (two rows, C3)
Apps/projectM-iOS/Tests/OutputProfileAppTests.swift, UITests/OutputProfileUITests.swift    (new)
```

**Structure Decision**: existing layout; PresentationLifecycle is already in CI's `PKGS_LIBRARY`. No ADR: no default
is overridden and no settings key is added. SettingsView and AppCoordinator are not touched (the coordinator lives
on the setting).

## Complexity Tracking

None.
