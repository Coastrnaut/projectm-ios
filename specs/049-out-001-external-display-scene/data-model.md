# Data Model: OUT-001 External Display Scene

Session state only; nothing is stored.

## ExternalDisplayRouting (PresentationLifecycle, value type)

| Field | Type | Meaning |
|---|---|---|
| `displays` | ordered list of `ExternalDisplay` | Connected external display scenes, oldest first |
| `visualizing` | Bool | The visualizer screen is shown (a visualization exists) |

`ExternalDisplay`: `id` (opaque string, the scene session's persistent identifier), `size`
(`ExternalDisplayGeometry`: width and height in points, scale), `foreground` (Bool).

`ExternalDisplayGeometry.isUsable`: width ≥ 1, height ≥ 1, scale > 0, and all three are finite.

### Events

`connected(id, geometry, foreground)`, `resized(id, geometry)`, `foreground(id, Bool)`,
`disconnected(id)`, `visualizing(Bool)`. An event for an unknown id is ignored, except
`connected`. A second `connected` with a known id acts as a resize plus a foreground change.

### Derived

- `active`: the first display in `displays` that is foreground with a usable geometry, or nil.
- `target`: `.external(id)` when `visualizing` and `active` exists; `.device` otherwise.
- `apply(_:) -> Bool`: true when `target` or the active display's geometry changed (the
  coordinator then places the visual again).

### Rules (OUT-001-S3)

| Situation | Target |
|---|---|
| no display | device |
| display connected, usable, foreground, visualizing | external |
| not visualizing (notice, chooser) | device (the external window stays black) |
| display size zero or non-finite | device until a usable size arrives |
| display in background | device until foreground |
| second display connects | first keeps it; the second takes over only when the first leaves |
| display disconnects | the next eligible display, else device |

## Output slots (app)

- `VisualSlotView`: a black container UIView; `role` is `.device` or `.external`.
- `ExternalDisplayCoordinator`: `routing`, a weak `deviceSlot`, external slots by id, a weak
  `visual` (the current visual view), `placements` (a count of moves, for tests), and
  `showsVisualExternally` (observable; drives the device note).
