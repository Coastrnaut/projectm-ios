# Analysis: PRE-012 (speckit-analyze, 2026-11-12)

Read-only pass over spec.md, plan.md and tasks.md against the constitution; the fixes were then
applied under the run's standing instruction ("apply the fixes").

| ID | Category | Severity | Location | Finding | Fix applied |
|----|----------|----------|----------|---------|-------------|
| C1 | Coverage | HIGH | spec R21 | "Limits of containment MUST be documented" had no task. | Added PRE-012-T32 (test report with a Limitations section). |
| C2 | Coverage | MEDIUM | spec R24, US1 scenario 6 | Removing an imported preset had a UI task but no test. | T14 now tests removal, including that the playing preset stays. |
| C3 | Coverage | MEDIUM | spec S5 | The 5 s bound had no assertion. | T16 asserts the row within 5 s. |
| I1 | Inconsistency | LOW | spec R27 vs data-model | "1,000 user presets" vs "1,000 non-quarantined". | R27 says "waiting or playable". |
| I2 | Inconsistency | LOW | contracts UI identifiers | Two names for the playable row. | One: `preset:<name>`. |
| U1 | Underspecification | MEDIUM | plan Design | Whether user presets go to the warm-up engine was not stated. | Plan: they do not. |
| P1 | Privacy | LOW | tasks T30 | New file storage could change the privacy-manifest scan. | T30 runs `check_privacy_manifest.py` on the merged build. |

No constitution conflict. Licensing: no third-party preset enters the repository; fixtures are
synthetic; imports honor the takedown list (R6) and copies of built-in presets are refused (R5),
so ADR-0007's basis is not widened. Privacy: R30 amends FR-065, T26 updates the policy.
Cross-feature: PRE-007's file format and golden fixture are untouched (T08); PERF-011: the trial
is a presentation-bound resource (T13, T20); the other active feature edits `CaptureKit`,
`CaptureUI` and the controls overlay, none of which this feature touches; shared files
(`AppCoordinator.swift`, `project.yml`, `docs/privacy-policy.md`) get small, localized edits.

Coverage: 31 requirements, 7 success criteria; every one maps to at least one task (R31 → T28).
32 tasks; 0 critical issues remain.
