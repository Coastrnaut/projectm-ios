# Release report — projectM 1.0 (build 1) (task T112)

Date: 2026-11-10. Build machine: the project Mac (Xcode 27.2 / iOS SDK 27.2, `verify_environment.py`
exit 0). Archive: `~/Library/Developer/Xcode/Archives/2026-11-10/ProjectMiOS 1.0 (1).xcarchive`
(Release, projectM-iOS only). Upload to App Store Connect: by the owner (owner choice 2026-11-10).

**Result: every quickstart row passes or has an owner-approved waiver.** Owner ruling 2026-11-10
(T112): all rows still open from earlier device tasks are waived.

## Automated checks (macOS)

| Check | Result |
|-------|--------|
| `verify_environment.py` | exit 0 |
| AudioCore / CaptureKit / Diagnostics / CaptureUI (`swift test`, macOS host) | 77 / 80 / 8 / 10 tests, 0 failures |
| `check_compliance.py` | OK |
| `test_scripts.py` | 71 tests OK (1 skipped) |
| CaptureLab UI tests (iOS 27.2 simulator) | 3 tests, 0 failures |
| projectM-iOS unit and UI tests (iOS 27.2 simulator, 2026-11-10) | 30 unit, 17 UI, 0 failures |
| ANGLERendering tests (iOS 27.2 simulator) | 11 tests, 0 failures |

## Scenario A — Stage 1 capture feasibility

| Step | Status | Evidence |
|------|--------|----------|
| A.1–A.5 (US1, D3 on iOS 26, US2, lifecycle) | Pass | T040 `t040-us1.md`, T041 `t041-lifecycle.md`, exports in `exports/` |
| A.6–A.9 (10-min runs, ratings, Gate 2) | Waived | ADR-0001 rulings 18, 19 (T049–T053, T113 not required); Stage decision "go" (T056) |

## Scenario B — Gate 3 render proof

Pass: Gate 3 passed 2026-11-09 (T079, ADR-0003 Option B, `performance.md`).

## Scenario C — Gate 4 and Stage 2 criteria

| Row | Status | Evidence or waiver |
|-----|--------|--------------------|
| SC-005 frame rate | Waived | T102 not required (owner ruling 2026-11-10) |
| SC-006 audio→visual delay | Waived | Owner ruling 2026-11-10 (T112); T087 not run |
| SC-007 preset switch | Pass | D1: 50/50 < 1 s, p95 223 ms (`performance.md`, `exports/gate4/`) |
| SC-008 memory | Waived | T102 not required |
| SC-009 cycles + lifecycle | Pass | D1 and D3: 0 crashes, correct final states (T101) |
| SC-010 usability | Waived | Owner ruling 2026-11-10 (T112); T097 not run |
| SC-012 screen reader | Waived | T105 audit not required (owner ruling 2026-11-10); code in place |
| SC-013 thermal | Waived | T102 not required |
| SC-014 battery | Waived | T102 not required |
| SC-015 cold launch | Pass | D1 max 83 ms, D3 max 113 ms (`performance.md`) |
| FR-084 no auto-lock | Waived on device | Owner ruling 2026-11-10 (T112); `IdleTimerPolicy` unit tests only |
| FR-041 rotation / split view | Waived on device | Owner ruling 2026-11-10 (T112); VisualizerUITests on the simulator only |
| FR-089 indicators stay visible | Waived on device | Owner ruling 2026-11-10 (T112); T084 device part not run |
| US4–US6 acceptance | Waived on device | Owner ruling 2026-11-10 (T112); T087, T092, T097 |

## Scenario D — Release checks

| Row | Status | Evidence |
|-----|--------|----------|
| SC-011 privacy review | Pass | T108 on D1, zero violations (`privacy-review.md`) |
| FR-064 license review | Pass | ADR-0005 final conclusion "go", owner-approved (T109) |
| FR-066 privacy manifest / App Privacy | Pass | T106; `check_privacy_manifest.py` OK on the 1.0 archive; "Data Not Collected" (`docs/release/app-privacy.md`) |
| FR-067 Licenses screen | Pass | Every ADR-0004 component (19 entries, `collect_licenses.py --check` in CI) and all 28 bundled presets (in the LICENSES.md text) |
| FR-062 claims | Pass | T110, no compatibility claims (`docs/release/store-copy.md`) |
| **FR-090** only projectM-iOS submitted | Pass (archive) | The archive holds one app, `projectM-iOS.app` (`org.projectmios.ProjectMiOS` 1.0 (1)); no nested app, no CaptureLab file or string; CaptureLab is never archived for the App Store (`docs/release/capturelab-distribution.md`). Owner to confirm the App Store Connect record is projectM-iOS |

## The 1.0 archive

- 19 MB app; frameworks `projectM-4`, `libEGL`, `libGLESv2`; `Licenses/` (20 files); presets.
- No automation or test code (`AutomationRunner`, `UITestFakeSource` absent).
- Entitlements in the archive: development signing (`get-task-allow`); distribution signing at
  upload replaces it (T111).

## Upload (2026-11-10)

Done from Xcode's Organizer (owner authorized computer use for the remaining release steps).
App Store Connect record: app ID 6833037520, bundle ID `org.projectmios.ProjectMiOS`, created by
Xcode; store name set to "projectM-iOS" on App Store Connect ("projectM" and "projectM Visualizer" are taken; owner choice). Custom EULA (`docs/release/eula.md`), privacy policy URL and App Privacy "Data Not Collected" (published, owner-approved attestation) entered 2026-11-10. Also entered: description, keywords, support URL, copyright, review notes, content rights, free in all 175 countries, age rating 4+, build 1.0 (1) attached (export compliance answered by the owner; `ITSAppUsesNonExemptEncryption` NO for later builds), 4 iPhone and 4 iPad screenshots (`docs/release/screenshots/`).

1. First upload: rejected by App Store Connect validation: no app icon (90022, 90023, 90713) and no
   `CFBundleShortVersionString` in the ANGLE frameworks (90057).
2. Fixes: app icon from the projectM logo in the owner's UWP frontend fork
   (`scripts/make_app_icon.swift`, asset catalog `AppIcon`, credited on the Licenses screen);
   `scripts/build_angle_xcframework.py` adds `CFBundleShortVersionString` and `MinimumOSVersion` to
   both ANGLE frameworks.
3. Second upload of the rebuilt 1.0 (1) archive: **completed**, with warnings only that the three
   prebuilt frameworks have no dSYMs (crash reports in them are not symbolicated).

## Owner steps at upload (signing is manual)

1. Xcode › Organizer › the 1.0 (1) archive › **Generate Privacy Report**: expect the three API
   categories in `docs/release/app-privacy.md` and no collected data.
2. **Distribute App › App Store Connect › Upload** with your Apple Distribution certificate.
3. App Store Connect: App Privacy "Data Not Collected"; privacy policy URL
   https://github.com/Coastrnaut/projectm-ios/blob/main/docs/privacy-policy.md; custom License
   Agreement from `docs/release/eula.md`; review notes from `docs/release/app-review-notes.md`;
   listing text from `docs/release/store-copy.md`.

## Feature 002 (full preset library), 2026-11-10

Implemented and verified on the Mac and the simulator (`docs/test-reports/preset-library.md`). Not
yet released.

Before a 1.1 upload:

- The owner creates the in-app purchase (T242).
- The device tasks run: T238, T239 and T241.
- Version raised to 1.1 (2) on 2026-11-10 (`project.yml`, `Apps/projectM-iOS/Info.plist`).
- The Release build needs the preset submodules checked out.

The app target was renamed `projectM-iOS`. Later archives are named `projectM-iOS`; the bundle ID
is unchanged, so the App Store Connect record (app ID 6833037520) still applies.

## 1.1 (2) upload, 2026-11-11

- **Archive:** `xcodebuild archive`, Release, `projectM-iOS 1.1 (2).xcarchive`:
  - bundle ID `org.projectmios.ProjectMiOS`, display name "projectM";
  - one app (FR-090), 45 MB, with the preset library (`PresetIndex.json`, `PresetArchive.bin`,
    `PresetTextures/`);
  - no StoreKit test file;
  - zero automation or test symbols (`nm -U`);
  - `check_privacy_manifest.py`: OK.
- **Upload:** `xcodebuild -exportArchive` with `method app-store-connect` and
  `destination upload`, using automatic signing through the account signed in to Xcode; the
  project's signing settings are unchanged. Result: "Upload succeeded". The only warnings are, as
  for 1.0, that the three prebuilt frameworks have no dSYMs.
- **Next:**
  - Create version 1.1 in App Store Connect and attach build 2.
  - Add the in-app purchase "Full Preset Library" to that submission; Apple requires the first
    in-app purchase to go with a new version.
  - Update What's New and the description from `docs/release/store-copy.md`.
  - 1.0 is still "Waiting for Review". Either let it finish, or remove it from review and submit
    1.1 instead (owner's choice).
