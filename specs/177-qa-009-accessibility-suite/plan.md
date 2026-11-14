# Implementation Plan: QA-009 Accessibility Snapshot Suite

**Branch**: `feature/qa-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

One manifest (`PrimaryScreensManifest.swift`, UI test target) lists the 13 built primary screens, how each
is opened, and its required controls. One manifest-driven suite (`PrimaryScreensAccessibilityUITests`)
runs one test per screen and layout: it opens the screen, walks the required controls in order (each must
exist, be labelled with a label that is not its identifier, and be wholly visible and hittable after at
most one scroll), then runs the system audit with the existing ACC-004 (default size) or ACC-006 (AX3,
AX5) filters. Default run: default size and AX5 (26 tests); `QA009_FULL=1` adds AX3 (39 tests). A
script test checks that every manifest identifier still appears in the app's source. Defects found are
fixed in the views. Details: [research.md](research.md), [data-model.md](data-model.md),
[contracts/manifest.md](contracts/manifest.md), [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26); Python 3 for the script test.

**Primary Dependencies**: XCTest (`performAccessibilityAudit`, iOS 17+). None new.

**Storage**: none (no new keys; screens are seeded through existing launch arguments).

**Testing**: UI tests on simulator "QA9 iPhone 17" (iOS 27.2), each under 30 s; `scripts/test_scripts.py`
gains `QA009ManifestTests` (no simulator).

**Target Platform**: iOS 26+ (tests on iOS 27.2 simulator).

**Performance Goals**: default subset under 10 minutes in one xcodebuild run; each test ≤ 30 s.

**Constraints**: owner rules 7 (short tests) and 8 (no Simulator panel); type-check budget; no blanket
filters; other agents edit `SettingsView.swift` in parallel, so the app edit there is three `.id(...)`
anchors only.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: XCTest and SwiftUI only; DEBUG aids compile out of Release. |
| X Evidence-based quality | Pass: simulator results are labelled UI evidence only; device VoiceOver passes stay with ACC-004-T12 / ACC-006-T12 {device}. |
| Privacy / local-first | Pass: no new stored keys, no networking. |
| Modular boundaries | Pass: test-target code plus small view fixes. |

Post-design re-check: unchanged (Pass).

## Project Structure

```text
Apps/projectM-iOS/UITests/PrimaryScreensManifest.swift                (new: the manifest)
Apps/projectM-iOS/UITests/PrimaryScreensAccessibilityUITests.swift    (new: checks and 39 tests)
Apps/projectM-iOS/UITests/AccessibilityScreensUITests.swift           (systemDone filter made reusable)
Apps/projectM-iOS/Views/SettingsView.swift                            (.id anchors: effectOrder, recordingQuality, recordingFrameRate)
Apps/projectM-iOS/Debug/UITestSettingsSection.swift                   (comment: the new anchors)
Apps/projectM-iOS/Views/*                                             (accessibility fixes, if the suite finds defects)
scripts/test_scripts.py, scripts/qa009_manifest_check.py              (new script test)
```

## Overlap with existing suites (recorded decision)

ACC-004 and ACC-006 stay: they also cover announcements, alerts, notices, text input and visual-specific
rows. The new suite overlaps them only on the audit of the controls, browser, Settings top, show editor,
scene switcher, Storage and Licenses; its added value there is the required-control list, the "label is
not the identifier" rule and the one-scroll rule. Post-merge checks run only this suite's default subset.

## Complexity Tracking

None.
