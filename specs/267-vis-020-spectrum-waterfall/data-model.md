# Data Model: VIS-020 Spectrum Waterfall

## SpectrumWaterfallHistory (pure Swift, every platform; not Sendable)

| Field | Meaning |
|---|---|
| `columns` = 256, `rows` = 512 | Fixed size; `byteCount` = 131,072. |
| `levels` | `UnsafeMutablePointer<UInt8>`, rows × columns, allocated in `init`, never reallocated. |
| `sequences` | Per ring row, the row's sequence number since the last clear (−1 = never written). |
| `newestRow` | Ring index of the newest row (−1 before the first). |
| `rowsWritten` | Total rows since the last clear. |
| `epochStart`, `rowsInEpoch`, `spanNanoseconds` | Row clock (60 s or 120 s span). |
| `sum`, `frames`, `latest` | Running sum (256 floats), frames in the current row, the newest frame's columns. |
| `pending` | Ring rows written since the last `drainPending` (capped at 512). |

Transitions: `clear()` → empty, clock unanchored; `advance(bands:timeNanoseconds:reduceMotion:)` anchors on the first
frame, re-anchors on time backwards, commits ≤ 512 rows when boundaries are crossed, then adds the frame.

## WaterfallFlashCells

Per ring row 8 group colour sums (`LinearColor`), recomputed for pending rows or all rows on a palette change; 64
cell colours for the newest-at-top picture.

## NoiseFieldConfiguration

VIS-013's, plus `waterfall: Bool` (true forces `wedges` 0 and `tunnelPace` 0).
