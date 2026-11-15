# Data Model: SHD-012 Authoring Preview Fixture

## AuthoringPreviewFixture (value, Sendable, Equatable)
| Field | Type | Rule |
|---|---|---|
| seed | UInt64 | REC-013 fixture seed; the editor offers 1…99 (default 1) |
| seconds | Double | > 0; default 4 |
| fps | Int | > 0; default 30 |
Derived: `frameCount` = `OfflineFrameClock(fps).frameCount(samples: round(seconds × 44,100))` (120 by default);
`audio()` = `OfflineFixtureAudio.samples(seed:seconds:)`.

## AuthoringPreviewRequest (value, Sendable, Equatable)
| Field | Type | Rule |
|---|---|---|
| values | MaterialParameterValues | the base (manual) values; carries the material definition |
| bindings | [AudioFeatureBinding] | validated against the material's registry (`AudioFeatureModulator.replaceBindings`) |
| fixture | AuthoringPreviewFixture | |
| frameCount | Int? | nil = the fixture's frame count; ≥ 0 |

## AuthoringPreviewFrame (value)
| Field | Type |
|---|---|
| index | Int |
| timeNanoseconds | UInt64 (from the run start; the renderer adds 1 s) |
| bands | [Float] (the analysis bands this frame) |
| values | MaterialParameterValues (effective values the GPU reads) |
| phase, audioLevel | Double (`MaterialMotion` after this frame) |

## AuthoringPreviewTrajectory (value, Equatable)
| Field | Type |
|---|---|
| parameters | [ParameterID] (bound targets in binding order, unique) |
| values | [[Double]] (per parameter, one value per frame) |
| phase, audioLevel | [Double] (one per frame) |
| timeNanoseconds | [UInt64] |

## AuthoringPreviewRecording (value, Apple)
| Field | Type |
|---|---|
| trajectory | AuthoringPreviewTrajectory |
| checksums | [String] (64 hex characters each, one per frame) |
| runDigest | String (SHA-256 hex of the concatenated frame digests) |
| frames | [RGBA8Image] (only when requested, for display) |

## State (app): FixturePreviewStore
`idle` → `rendering` → `ready(recording)` (looping when playing) → `idle` on a settings change.
