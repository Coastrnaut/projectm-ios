# Contract: Parameter inspector (UIX-003)

## P1 Entry

- Each inspectable Settings row offers "Inspect" (context menu and VoiceOver action) → sheet for its ID.
- DEBUG: `-uitestInspectParameter <id>` opens the sheet for a registered ID when Settings appears;
  an unknown ID opens nothing.

## P2 Sheet (accessibility identifiers)

| Identifier | Content |
|---|---|
| `parameterInspector` | the list; navigation title = display name |
| `parameterInspector.id` | the parameter ID |
| `parameterInspector.unit` | "Unit, Percent" (label, value) |
| `parameterInspector.range` | "0%…100%" |
| `parameterInspector.step` | "1%" (absent when no step) |
| `parameterInspector.default` | "50%" |
| `parameterInspector.value` | current base value text |
| `parameterInspector.slider` / `.toggle` / `.picker` | edit control of the kind (absent when read-only) |
| `parameterInspector.reset` | Reset button (absent when read-only) |
| `parameterInspector.modulation` | "Not modulated" or the effective value |
| `parameterInspector.source.<n>` | each source line |
| `parameterInspector.done` | Done |

## P3 Reset

`ParameterInspectorReset.reset(descriptor, target:)` sets `target` to `descriptor.defaultValue` and
returns "<name> reset to <spoken default>", announced on `AnnouncementKind.parameter`.
