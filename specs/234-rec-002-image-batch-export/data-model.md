# Data Model: REC-002 Image Batch Export

All values are in memory; nothing is stored.

## SnapshotBatchSize (enum)

| Case | Pixels |
|---|---|
| `landscape` (default) | 1920 × 1080 |
| `portrait` | 1080 × 1920 |
| `square` | 1080 × 1080 |

## SnapshotRenderValues

`barCount: SpectrumBarCount`, `orientation: LinearSpectrumOrientation`, `spacing: Double`, `glow: BloomParameters`.
Built from a `[ParameterID: ParameterValue]` map of the seven SCN-008 parameters (missing or wrong-kind values keep
the base).

## SnapshotBatchItem

`position` (1-based), `snapshotIndex`, `name` (the snapshot's), `fileName`, `values: SnapshotRenderValues`.

## SnapshotBatchJob

`visual: VisualChoice`, `style: NativeSpectrumStyle` (built per item from the visual and the item's linear options),
`reduceFlashing: Bool`, `clamp: SafetyClamp`, `size`, `items`.

## SnapshotBatchExportCoordinator.Phase

`idle` → `rendering(done, total)` → `finished([URL])` | `cancelled` | `failed(String)`; `finished` → `idle` on Done
(folder deleted). Starting a new export from any phase but `rendering` deletes the previous folder.
