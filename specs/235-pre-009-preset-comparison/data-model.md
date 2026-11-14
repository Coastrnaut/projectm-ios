# Data Model: PRE-009 Preset Comparison (in memory only)

| Entity | Fields | Rules |
|---|---|---|
| `PresetComparisonTick` | `index: Int`, `frameTime: Double`, `firstSample: Int64`, `samples: [Float]` (interleaved stereo) | `frameTime = index / rate`; `firstSample` = sum of earlier ticks' frame counts; `frameCount = samples.count / 2` |
| `PresetComparisonTimeline` | `rate`, next index, next sample | `stamp(samples)` returns the next tick; indexes and sample ranges are contiguous |
| `PresetComparisonBatch` | `firstTick`, `lastTick`, `frameTime`, `firstSample`, `samples`, `droppedTicks`, `duration` | joins waiting ticks in order; `frameTime` = last tick's; `duration = (lastTick - previous lastTick) / rate` |
| `PresetComparisonMailbox` | waiting ticks, cap 6, dropped count | thread-safe; `post` drops the oldest above the cap; `take` returns all waiting ticks as one batch or nil |
| `PresetComparisonDelivery` | `firstTick`, `lastTick`, `frameTime`, `firstSample`, `frameCount`, `checksum` | equal for A and B for every batch (S1) |
| `PresetComparisonRecorder` | per side list of deliveries | test instrument, nil in the app |
| `PresetComparisonPick` (app) | `preset: IndexedPreset`, `scope: PresetScope` | A waits in `pending`; a session holds A and B (different presets) |
| `PresetComparisonPane` (app) | `image: UIImage?`, `state: loading / showing / failed(message)` | failed after a load error or no frame within 20 s |
