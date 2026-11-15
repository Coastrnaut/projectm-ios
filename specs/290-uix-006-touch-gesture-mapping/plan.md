# Implementation Plan: UIX-006 Touch Gesture Mapping

**Branch**: `feature/uix-006` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Pure Swift in PerformanceControl (`Gestures/GestureShortcuts.swift`) holds the six mappable gestures with their
precedence, the safe action catalogue, the configuration (master switch plus mapping, JSON-coded, unknown values
read as defaults), the touch-sequence classifier (fingers, movement, duration → recognised gestures, thresholds of
UIX-006-R10) and the precedence resolver (recognised set + configuration + VoiceOver → the winning gesture and
action, or nil). The app adds `GestureShortcutsSetting` (one key, `settings.gestures.shortcuts`, edits refused by
the scene lock), `AppCoordinator+GestureShortcuts.swift` (runs a resolved action through the existing coordinator
paths without revealing the controls), one UIKit `UIGestureRecognizer` subclass that summarises a touch sequence on
the visualizer's tap area and asks the resolver (attached through SwiftUI's `UIGestureRecognizerRepresentable`,
only while the switch is on and VoiceOver is off; the other recognisers on the area wait for it to fail, so one
action runs per touch), and a "Gesture Shortcuts" settings section in Settings › Performance.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26) · **Primary Dependencies**: PerformanceControl,
SwiftUI, UIKit (`UIGestureRecognizer`, `UIGestureRecognizerRepresentable`, iOS 18+) · **Storage**: one
UserDefaults key `settings.gestures.shortcuts` (JSON string), backed up (FILE-005 included) · **Testing**: pure
package tests (also Linux), app unit tests (`GestureShortcutsAppTests`), one UI test (`GestureShortcutsUITests`)
on "UIX6 iPhone 17" (iOS 27.2) · **Target Platform**: iOS 26+ · **Performance Goals**: no recogniser and no work
while off; classification O(fingers) per touch event · **Constraints**: one-finger tap unchanged and undelayed;
no VoiceOver gesture hijack; Linux-safe package code (Foundation only).

## Constitution Check

- I Public APIs only: `UIGestureRecognizer` subclassing (`UIKit.UIGestureRecognizerSubclass`) and `UIGestureRecognizerRepresentable` are public. PASS
- VI Modular boundaries: pure rules in PerformanceControl; one setting, one coordinator extension, one recogniser file and one settings view in the app; `VisualizerView` gains one modifier line. PASS
- VII Real-time audio safety: no audio-thread code touched. PASS
- X Evidence-based quality: resolver and classifier proven by pure tests, actions by app tests, the touch path by a simulator UI test; device feel is `{device}` (UIX-006-T14). PASS
- Privacy: one preference stored on the device, no network. PASS

## Project Structure

```text
Packages/PerformanceControl/Sources/PerformanceControl/Gestures/GestureShortcuts.swift   (new)
Packages/PerformanceControl/Tests/PerformanceControlTests/GestureShortcutTests.swift      (new)
Apps/projectM-iOS/Coordinators/GestureShortcutsSetting.swift                             (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+GestureShortcuts.swift                     (new)
Apps/projectM-iOS/Views/GestureShortcutViews.swift      (new: recogniser, representable, settings section, probe)
Apps/projectM-iOS/Views/VisualizerView.swift            (one modifier on tapArea)
Apps/projectM-iOS/Views/SettingsView.swift              (one optional property, one line in performanceSection)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift     (one lazy property)
Apps/projectM-iOS/Tests/GestureShortcutsAppTests.swift  (new)
Apps/projectM-iOS/UITests/GestureShortcutsUITests.swift (new)
Packages/LibraryBackup/.../LibrarySettings.swift, scripts/run_device_tests.py,
Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift      (the new key)
```

## Complexity Tracking

None.
