# Implementation Plan: UIX-015 Onboarding Permission Explainer

**Branch**: `feature/uix-015` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Add one shared pre-prompt explainer for the camera (Camera visual row) and local network (OSC receiver
toggle), modelled on FR-005's microphone sheet, with texts from FILE-013's `PermissionCatalog`. A pure
policy decides "explain or go ahead" from the permission's status and a stored explained flag; a small
main-actor coordinator holds the pending request. Denied and restricted camera notices gain a fallback
line and Dismiss (per attempt); the local network notice gains a fallback line. The microphone is
unchanged.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), SwiftUI, iOS 26+ deployment
**Primary Dependencies**: AVFoundation (`AVCaptureDevice.authorizationStatus`, `AVCaptureDevice.default`;
both public), existing app modules (CameraLayer, PerformanceControl)
**Storage**: UserDefaults, two Bool keys (`permission.explained.camera`, `permission.explained.localNetwork`)
**Testing**: XCTest unit tests in `projectM-iOSTests` (injected status, isolated defaults suite);
XCUITest with the camera stand-in, the OSC failing transport and the simulator's microphone
**Target Platform**: iPhone and iPad
**Project Type**: mobile app (XcodeGen `project.yml`)
**Performance Goals**: none beyond keeping SwiftUI bodies small (CI's Xcode 26 type-checker)
**Constraints**: no networking, no new permission or usage text, contract texts unchanged
**Scale/Scope**: 2 explainers, 3 notices touched, ~4 source files, 2 test files

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | `AVCaptureDevice` status and device queries; no prompt workaround: the explainer only precedes iOS's own prompt | Pass |
| IV Truthful labeling | Microphone explainer (FR-005) unchanged | Pass |
| VI Modular boundaries | Pure policy + coordinator in Coordinators; view only shows; catalog stays the text source | Pass |
| VII Real-time safety | No audio path change | Pass |
| X Evidence | Simulator stand-ins; real prompts on D1 are a `{device}` task | Pass |
| Privacy | Two on-device Bool keys, in `ALLOWED_KEYS`; nothing sent | Pass |
| No networking (FR-068) | No network code; OSC transport untouched | Pass |
| Accessibility (ACC-001/004/006/011) | No animation; scrolls and stacks at AX sizes; no announcement | Pass |
| Permissions (FILE-013) | Texts from the catalog; `check_permission_catalog.py` unchanged | Pass |

Post-design re-check: unchanged, Pass. No ADR needed (no default overridden beyond the CAM-001-R5
refinement recorded in Clarifications).

## Project Structure

```text
specs/108-uix-015-onboarding-permission-explainer/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/permission-explainer.md
└── checklists/requirements.md

Apps/projectM-iOS/
├── Coordinators/PermissionExplainer.swift      (new: policy, status sources, coordinator)
├── Coordinators/PermissionCatalog.swift        (explainer and notice fallbacks; notice gains fallback, offersDismiss)
├── Coordinators/AppCoordinator.swift           (owns the coordinator; reset; camera notice dismissal)
├── Coordinators/OSCReceiverCoordinator.swift   (reports an observed local network decision)
├── Views/PermissionExplainerView.swift         (new: the sheet)
├── Views/PermissionNoticeView.swift            (fallback line, Dismiss)
├── Views/SettingsView.swift                    (Camera row and OSC toggle go through the coordinator)
├── Views/VisualizerView.swift                  (passes the coordinator; hides a dismissed camera notice)
├── Tests/PermissionExplainerTests.swift        (new)
└── UITests/PermissionExplainerUITests.swift    (new)
scripts/run_device_tests.py                     (ALLOWED_KEYS)
```

**Structure Decision**: app-target code only; the policy is small and depends on `AppPermission`,
which lives in the app.
