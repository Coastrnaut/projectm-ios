# Data Model: SHOW-009 Keyframe Easing

## ShowKeyframeInterpolation (ShowControl, extended)

| Case | Raw (`easing` name) | Stored `interpolation` | `easing` written | Segment to the next key |
|---|---|---|---|---|
| `linear` | `linear` | `linear` | no | straight line |
| `stepped` | `stepped` | `hold` | no | this key's value; jump at the next key |
| `hold` | `hold` | `hold` | `"hold"` | this key's value; and the segment arriving at it holds the previous value |
| `ease` | `ease` | `ease` | no | smoothstep 3u² − 2u³ |
| `cubic` | `cubic` | `ease` | `"cubic"` | monotone cubic Hermite (research D2); colours: smoothstep |

Default: `linear`. Display names: Linear, Stepped, Hold, Ease, Cubic.

## Keyframe (SHOW-008, unchanged shape)

`time` (ms), `value` (number or colour), `interpolation` (the mode above).

## Read rules (show.json)

1. `easing` is a known mode → that mode.
2. else `interpolation`: `linear`, `hold` (→ Stepped), `ease`; also accepts `stepped`, `cubic`.
3. `interpolation` missing → Linear.
4. otherwise the keyframe is dropped (`droppedKeyframes`).
