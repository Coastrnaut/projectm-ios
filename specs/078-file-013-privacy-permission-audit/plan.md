# Implementation Plan: FILE-013 Privacy Permission Audit

**Branch**: `feature/file-013` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

## Summary

One app-side `PermissionCatalog` describes the four permissions the app can trigger (microphone,
camera, local network, screen capture) and records that the Photos library needs none. It maps each
framework's status to a `PermissionState` and returns the user-facing `PermissionNotice` for denied and
restricted. The camera notice and the OSC section in Settings render one shared `PermissionNoticeView`;
every Open Settings goes through one opener. A script checks the catalog against `project.yml` and the
privacy policy. Tests: unit tests for every mapping and every denied/restricted notice; UI tests for the
real microphone denial (`simctl privacy revoke`) and injected camera, local network and screen-capture
states.

## Technical Context

**Language/Version**: Swift 6 (app target `projectM-iOS`, Xcode 27.2; CI also builds with Xcode 26);
Python 3 standard library for the check script.
**Primary Dependencies**: AVFoundation (`AVAuthorizationStatus`), CaptureKit (`MicrophonePermission`,
`StopReason`, `SourceAvailability`), CaptureUI (`UIStrings`), CameraLayer (`CameraFeedState`),
PerformanceControl (`OSCReceiverState`, `OSCReceiver`, `OSCDatagramTransport`), SwiftUI/UIKit
(`UIApplication.openSettingsURLString`).
**Testing**: XCTest app unit tests (`projectM-iOSTests`), XCUITest (`projectM-iOSUITests`) on an own
iOS 27.2 simulator; `scripts/test_scripts.py`.
**Target Platform**: iOS 26+ app; Mac host for the script.
**Constraints**: owner rule 7 (unit tests ~1-2 s, UI tests < 30 s); owner rule 8 (no Simulator panel
tool); explicit closure types, no C stdio globals, no main-actor mutation in setUp/tearDown, no
wall-clock assertions (CI on Xcode 26 and Linux); SCN-012 and ACC-001 run in parallel, so edits to
shared files (`AppCoordinator.swift`, `VisualizerView.swift`, `SettingsView.swift`,
`UITestFakeSource.swift`, `test_scripts.py`) stay small.

## Constitution Check

- I Public APIs only: AVFoundation status, `UIApplication.open(openSettingsURLString)`; no private API.
  PASS.
- Privacy: no new permission, prompt or Info.plist key; prompts stay at their point of use; the
  privacy policy is updated to match the catalog exactly. PASS.
- FR-068 / ADR-0008 (networking): no networking added; the OSC stand-in is a DEBUG fake transport with
  no Network framework. PASS.
- X Evidence: simulator results are never device evidence; restricted states and Screen Time on D1
  stay a `{device}` task (FILE-013-R9). PASS.

No ADR needed: no default is overridden (texts unchanged, no new permission).

## Research decisions

- **D1 Catalog location**: the app target (`Apps/projectM-iOS/Coordinators/PermissionCatalog.swift`).
  It needs types from four packages; no package depends on all of them. Alternatives: a new package
  (adds a target to `project.yml` for a single file; rejected).
- **D2 Single source of each text**: texts fixed by feature 001's contract (microphone denied, screen
  recording not allowed) are referenced from `UIStrings`; the camera texts from `CameraFeedState`
  (Compositor package, tested there); the Local Network denial text moves from
  `OSCReceiverCoordinator.statusText` into the catalog, which the coordinator now reads. So the
  catalog is the one index every feature reads, and no text is written twice. The usage descriptions
  are the exception: Info.plist values cannot be read from Swift at build time, so the catalog repeats
  them and both the script (against `project.yml`) and a unit test (against the built
  `Bundle.main.infoDictionary`) fail on any difference.
- **D3 Restricted where iOS has none**: `AVAudioApplication.recordPermission` has `undetermined`,
  `denied`, `granted`; Local Network has no query API and the listener reports only a policy denial
  (DNS-SD `-65570`). The catalog still defines restricted for both and returns the denied notice
  (`hasDistinctRestrictedState = false`).
- **D4 Screen capture**: `SourceAvailability.unavailable(.screenRecordingNotAllowed)` (the picker's
  `isAvailable` false: not allowed on this device) maps to restricted; `StopReason.screenRecordingNotAllowed`
  (a decline, -3801) maps to denied. No Open Settings (no per-app switch exists in iOS Settings).
- **D5 Mappings**: camera from `AVAuthorizationStatus` (authorized → granted, notDetermined,
  denied, restricted; unknown future → denied, as `AVCameraFrameProvider`) and from `CameraFeedState`
  (requestingAccess → notDetermined, starting/running → granted, denied, restricted; idle,
  unavailable, interrupted, failed → nil: not a permission state); local network from
  `OSCReceiverState` (failed(localNetworkDenied) → denied, listening → granted, otherwise nil: unknown,
  as iOS offers no query); microphone from `MicrophonePermission`.
- **D6 One notice view**: `PermissionNoticeView(notice:symbol:identifierPrefix:)`: symbol (hidden from
  VoiceOver), text (`<prefix>NoticeText`), Open Settings (`<prefix>OpenSettings`) when the notice
  offers it, regular material, container `<prefix>Notice`. Camera keeps `camera…` identifiers;
  OSC uses `localNetwork…` and replaces the status line only while denied. The microphone and
  screen-capture denials stay in feature 001's `StatusBanner` (CaptureUI, shared with CaptureLab,
  contract-checked).
- **D7 One opener**: `PermissionCatalog.openSettings()` (main actor) opens
  `UIApplication.openSettingsURLString`; `AppCoordinator.handle(.openSettings)`, the camera notice and
  the OSC notice call it.
- **D8 UI injection**: camera `-uitestCamera restricted|denied` (existing stand-in); local network
  `-uitestOSCFailure localNetworkDenied` (new DEBUG fake transport that fails on start and reports
  `.cancelled` on stop); screen capture `-uitestFake systemAppCapture` with the new
  `-uitestFakeAvailability screenRecordingNotAllowed` (restricted) or the existing
  `-uitestFakeStartError screenRecordingNotAllowed` (denied, StatusUITests).
- **D9 Real denial**: the runner revokes the microphone with
  `xcrun simctl privacy <udid> revoke microphone org.projectmios.ProjectMiOS` and passes
  `TEST_RUNNER_FILE013_MIC_REVOKED=1`; the test then requires the denied banner and that Open Settings
  brings iOS Settings (`com.apple.Preferences`) forward. Without the variable it skips (CI never
  revokes). The real camera path cannot be shown on the simulator: it has no rear camera, so
  `AVCameraFrameProvider` reports `unavailable` before any permission (recorded).
- **D10 Script**: `scripts/check_permission_catalog.py` (stdlib only): reads the `projectM-iOS`
  target block of `project.yml` (the `NS…UsageDescription: "…"` lines), the catalog's
  `infoPlistKey:`/`usageDescription:`/`name:` literals, and the bullets of the privacy policy's
  "Permissions and why" section (`- **<name>**:`). Fails on a key missing either side, a different
  text, any `NSPhotoLibrary…UsageDescription` anywhere in `project.yml`, or a policy bullet set that
  differs from the catalog names. `--json` for machine output. Run in CI's docs job.

## Design

Entities (in `PermissionCatalog.swift`):

- `AppPermission`: `microphone`, `camera`, `localNetwork`, `screenCapture`.
- `PermissionState`: `notDetermined`, `granted`, `denied`, `restricted`.
- `PermissionEntry`: `permission`, `name` (the privacy policy's bullet), `infoPlistKey`,
  `usageDescription`, `features`, `askedWhen`, `settingsCanChange`, `hasDistinctRestrictedState`.
- `PermissionNotice`: `permission`, `state`, `text`, `offersSettings`.
- `PermissionCatalog`: `entries`, `entry(_:)`, `notice(_:_:)` (nil for notDetermined and granted),
  the D5 mappings, `photosLibrary` note, `openSettings()`.

| Permission | Denied notice | Restricted notice | Open Settings |
|---|---|---|---|
| Microphone | `UIStrings.message(.permissionDenied)` | same (iOS reports denied) | yes |
| Camera | `CameraFeedState.denied.notice` | `CameraFeedState.restricted.notice` | yes |
| Local Network | "Local network access is off for projectM in Settings › Privacy & Security › Local Network." | same (iOS reports denied) | yes |
| Screen capture | `UIStrings.message(.screenRecordingNotAllowed)` | same text, row disabled in the chooser | no |

Files:

- New: `Apps/projectM-iOS/Coordinators/PermissionCatalog.swift`,
  `Apps/projectM-iOS/Views/PermissionNoticeView.swift`, `Apps/projectM-iOS/Debug/UITestOSCFailure.swift`,
  `Apps/projectM-iOS/Tests/PermissionCatalogTests.swift`,
  `Apps/projectM-iOS/UITests/PermissionAuditUITests.swift`, `scripts/check_permission_catalog.py`.
- Changed (small): `AppCoordinator.swift` (opener; DEBUG OSC stand-in), `VisualizerView.swift` (camera
  notice), `SettingsView.swift` (OSC notice), `OSCReceiverCoordinator.swift` (denial text from the
  catalog), `UITestFakeSource.swift` (availability argument), `scripts/test_scripts.py`,
  `.github/workflows/ios-ci.yml` (one step), `docs/privacy-policy.md`.

## Validation

See [quickstart.md](quickstart.md).
