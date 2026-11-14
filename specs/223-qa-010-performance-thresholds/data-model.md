# Data Model: QA-010 Performance budget thresholds

## Thresholds file (`docs/performance/thresholds.json`)

| Field | Type | Rule |
|---|---|---|
| `schemaVersion` | integer | 1; the checker refuses any other |
| `thresholdsVersion` | integer ≥ 1 | raised whenever a limit, class or metric changes |
| `updated` | date string | day of the last change |
| `metrics` | object | metric id → `{unit, direction ("max"\|"min"), description}`; ids from the fixed catalogue |
| `classes` | array | device classes (below); ids unique; no model in two classes |

Device class: `id` (`D1`, `D2`, `D3`, `simulator`), `name`, `models` (hardware model identifiers), `evidence`
(bool), `targets` (metric id → `{limit: number, basis: string}`; every catalogue metric present).

Metric catalogue (fixed order): `fps1sP5` (fps, min), `frameIntervalP50Ms` (ms, max), `frameIntervalP95Ms` (ms,
max), `droppedFramePercent` (%, max), `peakMemoryMB` (MB, max), `audioAgeP95Ms` (ms, max), `coldLaunchMs` (ms,
max).

## Measurement (in memory)

metric id → `{value, source}` where source is the input's base name; plus `model`.

## Verdict (`kind` `projectM-iOS.performanceVerdict`, `verdictSchemaVersion` 1)

| Field | Rule |
|---|---|
| `thresholdsVersion`, `thresholdsSchemaVersion` | from the file |
| `model`, `deviceClass`, `evidence` | resolved class; absent on errors that precede resolution |
| `overall` | `pass` \| `fail` \| `incomplete` \| `error` |
| `error` | reason, only when `overall` is `error` |
| `metrics` | catalogue order: `{metric, direction, limit, verdict (pass\|fail\|not measured), value?, source?, reason?}` |
| `inputs` | input base names, sorted |

State rules: fail if any metric fails; else incomplete if any is not measured; else pass. A value equal to the
limit passes.
