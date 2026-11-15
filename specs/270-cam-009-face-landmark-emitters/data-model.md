# Data Model: CAM-009 Face Landmark Emitters

All entities are memory only except the two preference keys.

| Entity | Fields | Rules |
|---|---|---|
| `FaceFeature` | `present`, `x`, `y`, `size`, `roll`, `yaw`, `mouth`, `eyes` | raw value is the source ID suffix |
| `FaceFeatureValues` | eight `Double`s | each finite 0…1; `neutral` = present 0, x/y/roll/yaw 0.5, size/mouth/eyes 0 |
| `FacePoint` | `x`, `y` (`Double`) | normalised to the face box |
| `FaceObservationSample` | box `x, y, width, height`; `roll?`, `yaw?`; `innerLips`, `leftEye`, `rightEye: [FacePoint]` | one per analysis; dropped after ingest |
| `FaceFeatureTracker` | smoothed values, last time, snap flag | `ingest(sample?, mirrored:, timeNanoseconds:)`, `reset()` |
| `FaceAnalysisSchedule` | interval, in flight, last start | `offer(at:)`, `finish()`, `reset()` |
| `FaceTrackingGate` | `switchOn`, `consented`, `cameraAuthorized` | `allowsAnalysis` = all three |
| `FaceTrackingStatus` | `off`, `needsCamera`, `unavailable`, `ready` | what the row says |
| Preference `settings.camera.faceTracking` | Bool | default false; excluded from backup |
| Preference `settings.camera.faceTrackingConsent` | Bool | default false; excluded from backup |

State: off → (switch on) → consent sheet → confirm → on (consented) → switch off → off (consented); cancel → off.
