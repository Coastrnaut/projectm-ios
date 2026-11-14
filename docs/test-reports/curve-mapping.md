# MOD-004 Curve Mapping — test report

Spec: `specs/129-mod-004-curve-mapping/` (tasks MOD-004-T01-T13). Date: 2026-11-14, Mac Studio
(Xcode 27.2, Swift 6.4.2), worktree branch `feature/mod-004`. No device step; simulator results are
never device evidence (Constitution X).

## What changed

- `MappingCurve` (ParameterGraph): linear, ease-in, ease-out, ease-in-out (exponent 1 < p ≤ 8),
  logarithmic and exponential (strength 0 < k ≤ 1000), piecewise (≤ 8 interior points, straight
  lines through implicit (0, 0) and (1, 1)). Every curve, valid or not: f(0) = 0, f(1) = 1, output in
  0…1, non-decreasing, deterministic; NaN and ±∞ read 0, negatives 0, values above 1 read 1.
  Validation names the first fault; a one-line text form for MIDI-004 (`;curve=<form>`).
- Bindings: `AudioFeatureBinding.curve` (default linear); the modulator resolves
  `mapping.interpolate(curve.apply(signal))` after the envelope and refuses invalid curves
  (`invalidCurve`). Linear is bit-identical to before. `ExpressionMapping.curve` (SHD-009).
- Scenes: optional binding field `curve` (omitted for linear; no version change). Unreadable curves
  are kept verbatim and their binding is rejected with the new warning `unsupportedCurve`; readable
  but invalid curves reject the binding with `invalidBinding`.
- No UI: no user-facing binding editor exists to host a curve picker.

## Evidence

| Check | Result | Log (`.build/scratch/mod-004/`) |
|---|---|---|
| Baseline (T01) | ParameterGraph 118 tests (1 skipped), SceneFormat 117, 0 failures | `T01-*.log` |
| Acceptance: 26 valid fixtures × (1,001 grid + 600 adjacent inputs) and edge inputs, two runs bit-identical | pass, 0.014 s | `T03.log` |
| Invalid curves: 21 fixtures (11 piecewise faults) refused, still bounded and monotonic | pass | `T03.log` |
| Text form round trip; 15 malformed texts read as nil | pass | `T03.log` |
| Curved bindings, refusal, linear bit-identity (7 ranges × 10,009 signals) | pass | `T07.log` |
| ParameterGraph package | 133 tests (1 skipped, as before), 0 failures | `T07.log` |
| SceneFormat package (QA-004 meta-test included) | 124 tests, 0 failures, 2.2 s | `T11.log` |
| App: CurveMappingAppTests + binding and safety suites, private iOS 27.2 simulator | 17 tests, 0 failures | `T08.log` |
| App: whole `projectM-iOSTests` bundle | 612 tests, 0 failures, 0 skipped, 92 s | `T08-all.log` |
| Dependent packages on the host: VisualGenerators, PerformanceControl, Compositor, SceneArchive, ShowControl, LibraryBackup, ImportFuzz, RenderGoldens | all exit 0, 0 failures (VisualGenerators 69 s and Compositor 138 s wall including build) | `T12-*.log` |
| Repository checks (compliance, docs, motion, permissions, status events) | OK | `check_*.log` |
| Script tests | 153 run, OK (1 skipped) | `test_scripts.log` |
| PosterBoard reports | 25 before, 25 after | — |

## Not verified here

- The Linux job itself: no container runtime on this Mac. The changed code is Foundation-only
  (`pow`, `log1p`, `expm1`) and already in packages CI tests on Linux; CI's `host-tests-linux` job is
  the evidence once the branch is pushed.
- Any device run (none needed: no device-only behavior).
