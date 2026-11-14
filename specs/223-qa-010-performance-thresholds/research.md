# Research: QA-010 Performance budget thresholds

## QA-010-D1 Evaluator language

Decision: Python, standard library. Rationale: the device runner and every other report checker
(`check_capturelab_export.py`, `run_render_soak.py`) are Python and run on the Mac on pulled files; a Swift
evaluator in Diagnostics would ship code the app never runs. Alternative: Swift in `Diagnostics` — rejected (no app
consumer; would need a host tool target).

## QA-010-D2 Metric sources

Decision: PERF-012 report (`frames.p50Ms`, `frames.p95Ms`, `frameDrops.outputs[device]`,
`resources.memory.peakFootprintBytes`); AutomationRunner `perf001` (`fpsTimerOff` 1 s samples, `frameDrops`);
`sc015.json` (seconds list). Audio age: no report carries it (only the "Normalized residency" signpost), so it is
declared and reads "not measured". Rationale: no app change; every source already exists.

## QA-010-D3 Dropped-frame share

Decision: 100 × skipped ÷ (submitted + skipped) on the device output. Rationale: PERF-007 defines `skipped` as
refresh slots with no new frame and counts it on every path; `late` and `discarded` are unavailable on projectM.

## QA-010-D4 Combining inputs

Decision: one model per check; a metric from two inputs is judged on its worse value. Rationale: conservative; no
input can hide a bad figure from another.

## QA-010-D5 Determinism

Decision: verdict JSON with sorted keys, metrics in catalogue order, input base names only, no timestamps.
Rationale: S1 asks for identical output; base names keep paths (user names) out.

## QA-010-D6 Simulator class

Decision: models `arm64`, `x86_64` plus a `--simulator` override (simulators report the simulated model);
`evidence: false`; D1's targets. Rationale: lets the step be rehearsed without ever counting as evidence.
