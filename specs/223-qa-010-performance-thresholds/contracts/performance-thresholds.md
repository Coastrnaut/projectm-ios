# Contract: performance thresholds checker (QA-010)

## C1 Command

```
python3 scripts/check_performance_thresholds.py REPORT [REPORT...] [--thresholds FILE]
    [--thresholds-version N] [--device D1|D2|D3] [--model ID] [--simulator] [--out FILE] [--json]
```

- `REPORT`: a PERF-012 report (`kind` `projectM-iOS.performanceReport`, `schemaVersion` 1), an AutomationRunner
  `perf001` report (has `fpsTimerOff`), or an `sc015` sample list (JSON array of seconds).
- `--device` names the class's model for inputs without one (`DEVICES` of `run_device_tests.py`); `--model` gives
  it directly; `--simulator` forces the `simulator` class.
- Exit: 0 pass, 1 fail or incomplete, 2 error.

## C2 Errors (nothing judged, `overall` `error`)

| Case | `error` starts with |
|---|---|
| thresholds `schemaVersion` ≠ 1 or structure invalid | `unsupported thresholds` / `invalid thresholds` |
| `--thresholds-version` ≠ file's `thresholdsVersion` | `thresholds version mismatch` |
| unreadable or unrecognised input | `unrecognised input` |
| PERF-012 report `schemaVersion` ≠ 1 | `unsupported report` |
| inputs name different models | `mixed device models` |
| no model at all | `no device model` |
| model in no class | `unknown device class` |

## C3 Extraction

| Metric | Source | Not measured when |
|---|---|---|
| `fps1sP5` | `perf001.fpsTimerOff`: nearest-rank 5th percentile (rank ⌈0.05 n⌉) | no samples |
| `frameIntervalP50Ms` / `P95Ms` | PERF-012 `frames.p50Ms` / `p95Ms` | key absent (sampleCount 0) |
| `droppedFramePercent` | `frameDrops.outputs[output == device]`: 100 × skipped ÷ (submitted + skipped) | no device output, a count absent, or zero slots |
| `peakMemoryMB` | PERF-012 `resources.memory.peakFootprintBytes` ÷ 1,000,000 | absent |
| `audioAgeP95Ms` | an AutomationRunner report's top-level `audioAgeP95Ms` (additive key; no mode writes it yet) | absent (so today always) |
| `coldLaunchMs` | max(`sc015` samples) × 1000 | empty list |

A non-numeric, non-finite or negative value is not measured with reason `invalid value`. Two inputs giving one
metric: the worse value (higher for max, lower for min); an invalid value in any input makes it not measured. Values are rounded to 3 decimals.

## C4 Verdict

See data-model.md. JSON, `sort_keys`, 2-space indent, trailing newline. Text form: one line per metric
`<metric>: <verdict> (<value> vs <direction> <limit>)` then `overall: …`, and `not evidence` for the simulator
class.

## C5 Runner step

`python3 scripts/run_device_tests.py thresholds (--device D1|D2|D3 | --simulator UDID) [--run] [--repeat N]
[--report FILE ...] [--thresholds-version N]`: with `--run`, installs unless `--no-install`, runs `perf001`
(pulls `automation-perf001-*.json`) and `sc015` launches (pulls `sc015.json`); then judges the newest of
`automation-perf001-*.json`, `sc015.json`, `performance-*.json` in the target's export folder plus the `--report`
files, and writes `performance-verdict.json` there. `--dry-run` prints device commands and judges what exists without writing the verdict file.
