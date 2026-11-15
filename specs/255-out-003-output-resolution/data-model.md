# Data Model: OUT-003 Independent Output Resolution

## ExternalResolutionMode (enum, raw values are stored)

`native` (default), `1080p`, `720p`, `custom`.

## ExternalOutputResolution (value)

| Field | Type | Rule |
|---|---|---|
| mode | ExternalResolutionMode | default `native` |
| percent | Int | clamped to 50…100; default 75; used only by `custom` |

## ExternalPixelBudget (value)

| Field | Type | Rule |
|---|---|---|
| maxSide | Int | ≥ 2 |
| maxPixels | Int | ≥ 4 |

`.unlimited` for tests that check only the choice. The app passes REC-014's `RecordingOutputCap.device` values.

## ResolvedExternalOutput (value)

| Field | Type | Meaning |
|---|---|---|
| scale | Double | display scale the visual reads (native scale × factor) |
| pixelWidth, pixelHeight | Int | drawable before FR-049's render scale |
| clamped | Bool | the budget was the limiting factor |
| isNative | Bool | factor is 1 (no override needed) |

Invalid input (zero or non-finite size or scale): `isNative`, scale = native scale (or 0), pixel size 0.

## Storage

| Key | Values | Backup |
|---|---|---|
| `settings.externalDisplay.resolution` | `native`, `1080p`, `720p`, `custom` | excluded (display hardware) |
| `settings.externalDisplay.resolutionPercent` | Int 50…100 | excluded |
