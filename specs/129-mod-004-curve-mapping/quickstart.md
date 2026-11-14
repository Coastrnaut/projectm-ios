# Quickstart: MOD-004 Curve Mapping

Run from the repository (or worktree) root on the Mac.

1. Curve model and binding pipeline (acceptance MOD-004-S1 to S3):
   `swift test --package-path Packages/ParameterGraph` — all pass, suite under 1 minute.
2. Scene storage (S4) and QA-004's meta-test:
   `swift test --package-path Packages/SceneFormat` — all pass.
3. End to end in the app's unit test host (S5), on a private simulator:
   `xcodegen generate`, then `xcodebuild test -scheme projectM-iOS -destination 'platform=iOS Simulator,id=<udid>'
   -only-testing:projectM-iOSTests/CurveMappingAppTests CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES
   -default-test-execution-time-allowance 180` — passes; then the whole `projectM-iOSTests` bundle.
4. Repository checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
   `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`.

Expected: a band level of 0.5 bound through `easeIn(exponent: 2)` gives glow intensity 0.25; with
the Reduced sensory-safety profile and the band at 1, the intensity is capped at 0.5.
