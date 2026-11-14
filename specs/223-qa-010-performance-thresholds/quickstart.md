# Quickstart: QA-010 Performance budget thresholds

1. Tests (any OS): `python3 scripts/test_scripts.py` — the `PerformanceThresholdsTests` cases judge the fixtures
   in `scripts/fixtures/qa010/`.
2. Check one report by hand:
   `python3 scripts/check_performance_thresholds.py scripts/fixtures/qa010/perf012-d1-pass.json scripts/fixtures/qa010/perf001-d1-pass.json scripts/fixtures/qa010/sc015-pass.json --device D1`
   → every metric passes (the fixture `perf001` carries the additive `audioAgeP95Ms`). A real run today reads
   `audioAgeP95Ms: not measured` and overall `incomplete`: no mode writes audio age yet.
3. Final device stage `{device}` (QA-010-T12): on each of D1, D2, D3, with the measurement build installed and the
   device unlocked (Auto-Lock Never):
   `python3 scripts/run_device_tests.py thresholds --device D1 --run --report <exported performance JSON>`
   Export the PERF-012 report first (Settings → Performance → Export performance report, after ≥ 1 minute with
   the performance overlay shown) and save it on the Mac. The verdict lands in
   `docs/test-reports/exports/feature002/D1/performance-verdict.json`.
4. Changing a budget: edit `docs/performance/thresholds.json`, raise `thresholdsVersion` by one, update
   `updated`, and give the new limit a `basis`.
