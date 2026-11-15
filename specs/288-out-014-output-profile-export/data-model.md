# Data Model: OUT-014 Output Profile Export

## OutputProfile (C1)
| Field | Type | Rule |
|---|---|---|
| fit | `ExternalOutputFit` | known raw value |
| shape | `ExternalOutputShape` | known raw value |
| pixelAspect | `ExternalPixelAspect` | known raw value (`auto`, `1.0`, `0.9`, `1.2`) |
| resolution | `ExternalResolutionMode` + percent `Int` | mode known; percent integer in 50…100 |
| outputMode | `ExternalOutputMode` | known raw value |
| cornerPin | `CornerPin` | four points, `CornerPin.isValid` (OUT-007) |
| calibration | gamma, red, green, blue `Double` | gamma 0.5…2.5, trims 0.5…1.5, finite (OUT-009) |
| display | `OutputDisplayClass?` | optional |

## OutputDisplayClass
| Field | Type | Rule |
|---|---|---|
| nativeWidth, nativeHeight | `Int` | ≥ 1, ≤ 32768 |
| pixelAspect | `Double` | 0.5…2 |
| refreshRate | `Int?` | 1…1000 when present |
| gamut | `OutputReadings.Gamut?` | `sRGB` or `displayP3` when present |

## OutputDisplayClassMatch
`same` · `different([Difference])` (resolution, pixelAspect, gamut) · `unknown`.

## Document (version 1)
```json
{
  "display" : { "gamut" : "sRGB", "nativeHeight" : 1080, "nativeWidth" : 1920, "pixelAspect" : 1, "refreshRate" : 60 },
  "format" : "org.projectmios.output-profile",
  "settings" : {
    "calibration" : { "blue" : 1.2, "gamma" : 1.5, "green" : 1, "red" : 0.8 },
    "cornerPin" : [ { "x" : 0.08, "y" : 0.04 }, { "x" : 0.95, "y" : 0 }, { "x" : 1, "y" : 0.97 }, { "x" : 0.02, "y" : 0.9 } ],
    "fit" : "fit", "outputMode" : "sameScene", "pixelAspect" : "auto",
    "resolution" : "native", "resolutionPercent" : 75, "shape" : "display"
  },
  "version" : 1
}
```
`display` is absent without a connected display. No other key is allowed at any level.
