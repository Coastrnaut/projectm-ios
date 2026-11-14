# Tasks: UIX-015 Onboarding Permission Explainer

**Input**: `specs/108-uix-015-onboarding-permission-explainer/` (spec, plan, research, data-model,
contracts/permission-explainer.md, quickstart). Tests are requested by the roadmap row (SwiftUI UI tests
plus the simulator). Budgets (owner rule 7): unit tests about 1-2 s, UI tests under 30 s each, each
xcodebuild run under 10 minutes. Never use the Simulator panel tool (owner rule 8).

## Phase 1: Setup

- [ ] UIX-015-T01 Run `xcodegen generate`, initialize the preset submodules if missing, create the simulator "UIX15 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run (owner rule 5)

## Phase 2: Foundational (blocks both stories)

- [ ] UIX-015-T02 Policy, status sources and coordinator in `Apps/projectM-iOS/Coordinators/PermissionExplainer.swift`: `PermissionExplainerPolicy.shouldExplain(status:explained:suppressed:)` = `!suppressed && !explained && status == .notDetermined` (contract C2), `isSuppressed(arguments:environment:harness:)` with opt-in `-uitestPermissionExplainers` (UIX-015-R13), keys `cameraExplainedKey = "permission.explained.camera"` and `localNetworkExplainedKey = "permission.explained.localNetwork"` (no microphone key); `PermissionStatusSource.camera(position:)` (research D2) and `.localNetwork(state:)`; `@MainActor @Observable PermissionExplainerCoordinator` with `pending`, `request(_:status:perform:)`, `continuePending()`, `notNow()`, `markExplained(_:)`, `isExplained(_:)`, `static reset(_:)`
- [ ] UIX-015-T03 [P] Catalog fallbacks in `Apps/projectM-iOS/Coordinators/PermissionCatalog.swift`: `PermissionNotice.fallback: String?` and `offersDismiss: Bool`; camera denied/restricted notice fallback "Showing the spectrum only." with Dismiss; local network notice fallback "OSC control is unavailable; everything else works as usual."; `explainerFallback(_:)` and `explainerNote` (research D6); contract-fixed texts unchanged (UIX-015-R10)
- [ ] UIX-015-T04 [P] Add both keys to `ALLOWED_KEYS` in `scripts/run_device_tests.py`, and clear them under `-uitestResetNotice` in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (UIX-015-R11)
- [ ] UIX-015-T05 Unit tests `Apps/projectM-iOS/Tests/PermissionExplainerTests.swift`: decision table C2 per permission with injected status, Continue stores the flag and performs, Not now stores nothing and performs nothing, a second request after Continue or after denial performs at once (no nag), harness rule, stand-in camera status mapping (restricted and no camera: no explainer, UIX-015 edge cases), catalog fallbacks and dismiss flags; isolated defaults suite, no main-actor mutation in setUp/tearDown

## Phase 3: User Story 1 — explainer before iOS asks (P1)

**Independent test**: never-asked camera stand-in; Not now asks nothing; Continue starts the camera.

- [ ] UIX-015-T06 [P] [US1] Sheet `Apps/projectM-iOS/Views/PermissionExplainerView.swift` (contract C1): decorative symbol, title, body, fallback, note, Continue (prominent) and Not now; scrolls; buttons stack at accessibility sizes; no animation; small bodies built in typed steps
- [ ] UIX-015-T07 [US1] Wire it: `AppCoordinator.explainers` (owned, suppressed by the harness rule), passed to `SettingsView` from `Apps/projectM-iOS/Views/VisualizerView.swift`; in `Apps/projectM-iOS/Views/SettingsView.swift` the Camera row and the OSC toggle's "on" go through `request`, and the sheet is presented from Settings; `OSCReceiverCoordinator` reports an observed local network decision, and OSC enabled at launch marks local network explained (UIX-015-R2)
- [ ] UIX-015-T08 [US1] UI tests in `Apps/projectM-iOS/UITests/PermissionExplainerUITests.swift`: no explainer at launch (UIX-015-S1); camera explainer, Not now leaves the visual and shows no prompt, the next pick shows the explainer again (UIX-015-R4), Continue chooses Camera; local network explainer, Not now leaves OSC off, Continue turns it on; microphone (never asked) FR-005 explainer, Cancel shows no system prompt; at the largest accessibility text size the camera explainer's text and both buttons can be reached (UIX-015-R12, S4)

## Phase 4: User Story 2 — clear fallback, no nagging (P1)

**Independent test**: deny each permission, use the feature twice, count explainers and notices.

- [ ] UIX-015-T09 [US2] Notice view `Apps/projectM-iOS/Views/PermissionNoticeView.swift`: fallback line `<prefix>NoticeFallback`, Dismiss `<prefix>Dismiss` when the notice offers it and the caller passes `onDismiss`; camera notice dismissal per attempt in `AppCoordinator` (`cameraNoticeDismissed`, reset when the Camera visual is created or released) and `VisualizerView` hides a dismissed notice (UIX-015-R7)
- [ ] UIX-015-T10 [US2] UI tests in `PermissionExplainerUITests.swift`: after Continue and a denial, picking Camera again shows no explainer and the notice with fallback; Dismiss hides it, Settings open/close does not bring it back, a new pick shows it; local network: after Continue and denial, off/on shows no explainer and the notice with fallback
- [ ] UIX-015-T11 [US2] Microphone after a real denial (`simctl privacy revoke`, `TEST_RUNNER_FILE013_MIC_REVOKED=1`): run `PermissionAuditUITests/testMicrophoneDeniedForRealShowsBannerAndOpensSettings` (no explainer, banner with Choose source)

## Phase 5: Polish

- [ ] UIX-015-T12 Regression: `projectM-iOSTests` (PermissionCatalogTests, PermissionExplainerTests, OSCReceiverCoordinatorTests), `CameraUITests`, `PermissionAuditUITests`, `OSCReceiverUITests`; update texts in existing tests only where the new Dismiss changes a message
- [ ] UIX-015-T13 Checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`, `check_privacy_manifest.py <Debug .app>`; PosterBoard count after; delete the simulator
- [ ] UIX-015-T14 {device} On D1: the real camera and local network prompts follow the explainer; deny each, use the feature again: no explainer, fallback visible

## Dependencies

T01 → T02 → (T03, T04 in parallel) → T05 → T06/T07 → T08 → T09 → T10 → T11 → T12 → T13. T14 needs a person
and a device.

## Implementation strategy

MVP is US1 (explainers); US2 completes the roadmap acceptance. Both are P1 and ship together.
