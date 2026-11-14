# Data Model: AUD-010 Channel Balance

## MonitorBalance (AudioCore)

| Field / function | Type | Rule |
|---|---|---|
| `range` | `ClosedRange<Double>` | −1…1 |
| `detent` | `Double` | 0.03 |
| `validated(_:)` | `Double → Double` | NaN → 0; clamp; round to 0.01; \|b\| ≤ detent → 0 |
| `gains(_:)` | `Double → (left: Float, right: Float)` | left = min(1, 1 − b), right = min(1, 1 + b) |

## PlaybackBalanceSetting (app)

| Field | Type | Rule |
|---|---|---|
| `positionKey` | `"settings.playbackBalance.position"` | Double; missing / not a Double → 0 |
| `position` | `Double` | always `MonitorBalance.validated`; stored on every set; `onChange` pushes it to the source |
| `reset()` | | position = 0 |
| `isAvailable(for:)` | `AudioSourceMode? → Bool` | true only for `.inAppPlayback` |
| `text(for:)` | `String` | "Centered", "30% left", "30% right" |

## Playback graph (CaptureKit)

`player → mainMixerNode ─(tap: PCMSink)→ balanceNode → outputNode`; `monitorBalance` sets the pan
of `mainMixerNode`'s destination `balanceNode`. Not part of scenes.
