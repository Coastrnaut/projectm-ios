# Quickstart: validating MOD-005

1. Package tests on the host (each suite under 1 minute):
   - `swift test --package-path Packages/ParameterGraph --filter EnvelopeStepResponseTests` — the
     acceptance (contract E1-E3) and edge cases (E2, E5, E6).
   - `swift test --package-path Packages/ParameterGraph` and
     `swift test --package-path Packages/SceneFormat` — no regressions; `SceneEnvelopeTests` covers E7.
2. App unit test on the private simulator (see `.autonomous/AGENT_RULES.md` for the xcodebuild flags):
   `-only-testing:projectM-iOSTests/EnvelopeBindingAppTests` — slow attack, fast release on the glow
   intensity matches the analytic values.
3. Repository checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
   `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`.

Expected: all pass; no device step.
