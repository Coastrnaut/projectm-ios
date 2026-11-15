# Implementation Plan: OSC-010 OSC Schema Export

**Branch**: `feature/osc-010` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A pure, Foundation-free builder in PerformanceControl (`OSCSchemaExport`) turns the OSC-003 route table, the
disabled set and the parameter descriptors into rows and one Markdown document (header with app version and a
UTC time from an injected instant, then one table row per route). The app's `OSCSchemaExportCoordinator` reads
the same `OSCRoutesCoordinator` the OSC Routes screen shows, writes the text as a REC-012 share copy
(`ShareFileStore`) and hands it to `ActivitySharePresenter` (new share kind `.oscSchema`); every outcome deletes
the copy. OSC Routes gets one new last section, "Export routes…". The builder's inputs hold no network value, so
nothing private can reach the file; a leak test proves it.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26) · **Primary Dependencies**: PerformanceControl
(OSC routes), ParameterGraph (descriptors), the app's REC-012 share path · **Storage**: none (no new
UserDefaults key; a temporary file under `<tmp>/Sharing` only while the sheet is open) · **Testing**: XCTest:
package tests on the host (and Linux in CI), app unit tests and one UI test on "OSC10 iPhone 17" (iOS 27.2) ·
**Target Platform**: iOS 26+ · **Performance Goals**: building a few dozen rows is instant (< 1 ms) ·
**Constraints**: no networking API, no Foundation in the package file (Linux), type-check budget (300/150 ms).

## Constitution Check

- I Public APIs only: `UIActivityViewController` through the existing presenter. PASS
- VI Modular boundaries: the format lives in the package; the app only gathers inputs and shares. PASS
- X Evidence-based quality: deterministic tests with an injected instant; the device share check is `{device}`. PASS
- Privacy (Platform, Security & Privacy Constraints): the file is created only on the user's tap, holds no network
  identifier or received value, is never uploaded, and is deleted when the sheet closes. PASS
- FR-068 / ADR-0008: network access unchanged. PASS

Re-checked after design: unchanged, PASS.

## Project Structure

```text
Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCSchemaExport.swift        (new: rows, document, file name, UTC stamp)
Packages/PerformanceControl/Tests/PerformanceControlTests/OSCSchemaExportTests.swift     (new: registry match, ranges, determinism, escaping)
Apps/projectM-iOS/Coordinators/OSCSchemaExportCoordinator.swift                         (new: gather inputs, share copy, finish)
Apps/projectM-iOS/Coordinators/CaptureShareCoordinator.swift                            (one Kind case: .oscSchema)
Apps/projectM-iOS/Views/OSCSchemaExportSection.swift                                    (new: button, presenter, DEBUG probe and stand-in)
Apps/projectM-iOS/Views/OSCRoutesView.swift                                             (hook: one section)
Apps/projectM-iOS/Tests/OSCSchemaExportCoordinatorTests.swift                           (new: file + request, leak test, cleanup)
Apps/projectM-iOS/UITests/OSCSchemaExportUITests.swift                                  (new: button shows the stand-in, probe text)
```

## Complexity Tracking

None.
