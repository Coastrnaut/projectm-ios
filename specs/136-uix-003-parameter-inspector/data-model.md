# Data Model: UIX-003 Context Parameter Inspector

No stored data (UIX-003-R11). In-memory values only.

| Value | Fields | Rules |
|---|---|---|
| `ParameterInspectorSummary` | name, id, group, unit, range, step?, defaultText; spoken forms | from one `ParameterDescriptor`; enum range = case names joined by ", "; boolean range = "On or Off" |
| `ParameterInspectorTarget` | `get: () -> ParameterValue`, `set: (ParameterValue) -> Void`, `choices: [ParameterValue]?` | one per inspectable ID; values of the wrong kind are ignored by `set` |
| `ParameterModulationReading` | effective: Double?, sources: [String], limitedBySafety: Bool | nil when nothing drives the parameter |
| `InspectedParameter` | id (Identifiable) | the sheet item |

Inspectable IDs: `effect.bloom.enabled`, `effect.bloom.intensity`, `effect.bloom.radius`,
`effect.bloom.threshold`, `visual.circularSpectrum.barCount`, `visual.linearSpectrum.orientation`,
`visual.linearSpectrum.spacing`. All other registry IDs are read-only.
