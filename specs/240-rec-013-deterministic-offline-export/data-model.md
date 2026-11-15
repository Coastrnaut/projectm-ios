# Data Model: REC-013 Deterministic Offline Export

- **OfflineFrameClock** (package): `fps` (30 or 60), `sampleRate` 44,100. `timeNanoseconds(frame:)`, `samplePosition(frame:)`, `frameCount(samples:)` = (samples × fps + 22,050) / 44,100.
- **OfflineFixtureAudio** (package): `samples(seed:seconds:)` → interleaved stereo Float32 at 44.1 kHz (D6).
- **OfflineAnalysisFrame** (package): bands (count = bar count), mono history (4,096), stereo history (4,096 interleaved), kick envelope, events of this frame (bus order).
- **OfflineExportManifest** (package, Codable, sidecar `formatVersion` 1): `visual`, `options` (string), `glow` (enabled, intensity, radius, threshold), `reduceFlashing`, `safetyProfile`, `width`, `height`, `fps`, `seed`, `audioSource` ("fixture" or the file name), `audioSHA256`, `audioFrames`, `gpu`, `osVersion`, `appVersion`, `frameCount`, `frameChecksums` [hex]. `sameFrames(as:)` compares the checksum lists.
- **OfflineExportJob** (app): visual, style, render values (REC-002 `SnapshotRenderValues`), reduce flashing, clamp, smoothing times, reduce motion, width, height, fps, seed (UInt32), audio source (`.fixture` / `.file(URL)`).
- **OfflineExportCoordinator.Phase** (app): idle → loading → rendering(frame, total) → finished | cancelled | failed(message) | stopped (left the screen); Done → idle (folder deleted).
