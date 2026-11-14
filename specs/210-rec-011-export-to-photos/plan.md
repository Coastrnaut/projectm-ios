# Implementation Plan: REC-011 Export to Photos

**Branch**: `feature/rec-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/210-rec-011-export-to-photos/spec.md`

## Summary

A **Save to Photos** button joins the "Frame ready" and "Recording ready" panels and each readable row of
Settings › Storage › Recordings. One app-wide `PhotosSaveCoordinator` runs the save: it reads iOS's
**add-only** Photos status, requests add-only access only when iOS has not asked yet, then adds the still (its
encoded bytes) or the video (its file, `shouldMoveFile = false`) in one Photos change. Denied, restricted and
failed saves leave the original untouched and still offered, and show a notice ("… The file is still in the
app.") with Open Settings for denied and restricted; every outcome is announced through the ACC-011 router
(new row X8a, capture lane). The Photos service sits behind two small protocols (`PhotosAccessProviding`,
`PhotosSaving`) so tests inject denial, restriction and failure, and count requests. A DEBUG
`-uitestPhotosAccess <state>` stand-in keeps UI tests free of system prompts.

The permission set grows by one (Photos, add only): `NSPhotoLibraryAddUsageDescription` in project.yml, a
fifth `PermissionCatalog` entry, the privacy policy bullet, and `check_permission_catalog.py` now allowing the
add-only key while still forbidding the full-library key. ADR-0059 records the change (it overrides FILE-013's
"no Photos key" and REC-012-R7's "no Photos permission").

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 build machine; CI also Xcode 26).
**Primary Dependencies**: Photos (`PHPhotoLibrary.authorizationStatus(for: .addOnly)`, `requestAuthorization(for: .addOnly)`, `performChanges`, `PHAssetCreationRequest.addResource`), SwiftUI, UIKit (Open Settings through `PermissionCatalog.openSettings()`).
**Storage**: none new; no UserDefaults key, no record of saved items.
**Testing**: app unit tests on the "REC11 iPhone 17" iOS 27.2 simulator (injected access and saver; recording file from REC-010's DEBUG fixture, a frame from fixed bytes); one UI test (< 30 s) with the stand-in; a live simulator check of the real Photos path with `simctl privacy grant|revoke photos-add` (not evidence); script tests for the catalog check.
**Target Platform**: iOS/iPadOS 26+ (add-only authorization exists since iOS 14).
**Project Type**: mobile app with SwiftPM packages (no package changes).
**Performance Goals**: the save runs off the main actor inside Photos; the UI only disables the item's buttons while it runs.
**Constraints**: Constitution I (public APIs), privacy (permission at point of use, accurate usage text, policy updated), X (simulator results are not evidence); `check_permission_catalog.py`, `check_privacy_manifest.py`, `check_status_events.py`, `check_network_symbols`; owner rule 7.
**Scale/Scope**: one new coordinator file (+ DEBUG stand-in), small edits to CaptureResultPanels, RecordingLibraryView, StatusEvents, StatusCaptionView, AppCoordinator, PermissionCatalog (+ PermissionExplainer switch), project.yml, privacy policy, check script and its tests.

## Constitution Check

| Principle | Check |
|---|---|
| I. Public APIs only | Pass. Photos framework public API only. |
| IV. Truthful labeling | Pass. "Saved to Photos." only after Photos reports success. |
| VI. Modular boundaries | Pass. Photos access is in one app coordinator behind protocols. |
| VII. Real-time safety | Pass. Nothing on the frame or audio path; saves run after capture finished. |
| X. Evidence | Pass. Simulator checks are labelled as such; the real-device save is a `{device}` task. |
| Privacy: permission at point of use | Pass. Requested only inside the user's Save to Photos tap (REC-011-R2, S3); add-only (least privilege). |
| Privacy: accurate usage text and policy | Pass. Usage text and policy bullet say add-only, never read. |

Post-design re-check: unchanged (Pass).

## Project Structure

```text
specs/210-rec-011-export-to-photos/   spec, plan, research, data-model, contracts/photos-save.md, quickstart, tasks
docs/adr/0059-photos-add-only-permission.md
Apps/projectM-iOS/Coordinators/PhotosSaveCoordinator.swift      (new: protocols, live service, coordinator)
Apps/projectM-iOS/Debug/PhotosSaveStandIn.swift                 (new, DEBUG: -uitestPhotosAccess)
Apps/projectM-iOS/Coordinators/PermissionCatalog.swift          (+ .photosAdd entry and notices)
Apps/projectM-iOS/Coordinators/PermissionExplainer.swift        (switch: no explainer for photosAdd)
Apps/projectM-iOS/Coordinators/StatusEvents.swift               (+ X8a photosNotice)
Apps/projectM-iOS/Views/StatusCaptionView.swift                 (CaptureEventChanges: post X8a)
Apps/projectM-iOS/Views/CaptureResultPanels.swift               (Save to Photos buttons, notice)
Apps/projectM-iOS/Views/RecordingLibraryView.swift              (row button, notice row)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift             (one property)
project.yml                                                      (NSPhotoLibraryAddUsageDescription)
docs/privacy-policy.md, scripts/check_permission_catalog.py, scripts/test_scripts.py
Apps/projectM-iOS/Tests/PhotosSaveAcceptanceTests.swift          (new)
Apps/projectM-iOS/UITests/PhotosSaveUITests.swift                (new)
```

## Complexity Tracking

None.
