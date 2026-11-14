# Data model: PERF-007 Frame drop telemetry

| Entity | Fields | Rules |
|---|---|---|
| `FrameDropOutput` | `device`, `external`, `recording` | label = raw value |
| `FrameDropSession` | `generation: UInt16` | a new one per `beginSession`; wraps after 65,536 |
| `FrameDropTicket` | `session`, `frameID: UInt32`, `targetTime`, `refreshInterval` | issued by `submit`; IDs start at 1 per session and increase |
| `FrameDropCounts` | `submitted?`, `skipped?`, `presented?`, `late?`, `discarded?`, `stale` | nil = unavailable; `late ≤ presented`; displays: `presented + discarded ≤ submitted` |
| `FrameDropCounter` | atomic cells, `presentationMeasured` | lock-free; `beginSession(measuresPresentation:)` zeroes every cell |
| `DiagnosticsSnapshot.FrameDrops` | `outputs: [Output]` | known output names only, at most 3, non-negative values |

State: `idle` (no session: generation 0, all reads 0) → `counting(generation g)` → `beginSession` → `counting(g+1)`.
