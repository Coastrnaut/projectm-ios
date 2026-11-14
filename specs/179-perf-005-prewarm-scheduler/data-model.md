# Data model: PERF-005

| Entity | Fields | Rules |
|---|---|---|
| `PrewarmKey` | `kind` (photo, video, logo), `id` (String; the file URL path for photos) | Hashable identity of an asset. |
| `PrewarmItem` | `key`, `rank` (0 = next cue, 1 = the one after), `source` (URL?) | A plan lists items in priority order; duplicates keep the lowest rank. |
| `PrewarmCache.Entry` | `bytes`, `rank`, `lastUse` (tick), `payload` (AnyObject) | Σ bytes ≤ budget. |
| `PrewarmStats` | `loadsStarted`, `loadsAdmitted`, `cancelled`, `releasedEntries`, `evictions`, `rejected`, `heldBytes`, `peakHeldBytes` | Test readout only. |
| Pause reasons | `presentation`, `thermal` | Work runs only with none set. |

State of an item: queued → in flight → (admitted to the cache | released when cancelled, stale, refused or over budget) → (taken by the live scene | released by replan, eviction, suspension, memory pressure, shutdown).
