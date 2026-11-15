# Data Model: OUT-011 Output Connection Diagnostics

## OutputReadings (value, PresentationLifecycle)

| Field | Type | Source | nil when |
|---|---|---|---|
| nativeWidth, nativeHeight | Int? | screen.nativeBounds | not ≥ 1 |
| nativeScale | Double? | screen.nativeScale | ≤ 0 / non-finite |
| pointWidth, pointHeight | Double? | screen.bounds | not ≥ 1 |
| scale | Double? | screen.scale | ≤ 0 / non-finite |
| maximumFramesPerSecond | Int? | screen.maximumFramesPerSecond | ≤ 0 |
| gamut | Gamut? (.sRGB, .displayP3) | screen.traitCollection.displayGamut | unspecified |
| potentialEDRHeadroom, currentEDRHeadroom | Double? | screen | ≤ 0 / non-finite |
| mirrored | Bool? | screen.mirrored != nil | no screen |
| overscan | Overscan? (.scale, .insetBounds, .off) | screen.overscanCompensation | unknown case |
| drawableWidth, drawableHeight | Int? | slot.resolvedOutput (visual in that slot) | visual elsewhere |
| pixelAspect | Double? | correction.pixelAspect.resolved(screen:) | ≤ 0 / non-finite |
| outputMode | String? | ExternalOutputSetting.title(outputMode) | — |

Readings are normalised by `OutputReadings.sanitized()` (the nil rules above).

## OutputDiagnostics (enum)

- `.disconnected` → rows: one row ("Status", "No external display connected"); `text` = that line; `summary` = "disconnected".
- `.connected(OutputReadings)` → ten rows in order: Native resolution, Size, Refresh rate, Color gamut, EDR headroom,
  Mirroring, Drawable, Overscan, Pixel aspect, Output. `summary` = "connected native=W×H pt=W×H@s fps=N drawable=W×H".

No state transitions are stored: each read is a fresh value.
