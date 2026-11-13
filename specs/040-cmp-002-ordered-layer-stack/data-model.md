# Data Model: CMP-002 Ordered Layer Stack

All types are value types in the `Compositor` module, `Sendable`, and build on Linux.

## LayerInstanceID

| Field | Type | Rule |
|---|---|---|
| rawValue | UInt64 | ≥ 1; unique within a stack; never reused by it |

Hashable, Comparable.

## LayerKind

| Field | Type | Rule |
|---|---|---|
| identifier | String | stable, e.g. `camera`, `spectrum.circular` |
| maximumInstances | Int? | nil: no limit beyond the stack's; the camera kind is 1 |

Declared by the layer targets: `.camera` (CameraLayer), `.circularSpectrum`, `.linearSpectrum`
(SpectrumLayers).

## LayerDescriptor

| Field | Type | Rule |
|---|---|---|
| kind | LayerKind | |
| parameters | [String: Double] | the layer's own values; copied by duplicate |

## LayerStackEntry

| Field | Type | Rule |
|---|---|---|
| id | LayerInstanceID | |
| descriptor | LayerDescriptor | |
| settings | LayerCompositeSettings | CMP-001 type; identity until CMP-003/004/005 |

## LayerStack

| Field | Type | Rule |
|---|---|---|
| entries | [LayerStackEntry] | index 0 bottom; count ≤ `maximumLayerCount` (8) |
| (next ID) | UInt64 | private counter; not part of equality |

Operations (each either succeeds or throws and leaves the stack unchanged):

| Operation | Result | Errors |
|---|---|---|
| `add(_:settings:at:)` (at nil = top) | new ID | `stackFull`, `indexOutOfRange` (0…count), `kindLimitReached` |
| `remove(_:)` | removed entry | `unknownLayer` |
| `duplicate(_:)` | new ID at index + 1 | `unknownLayer`, `stackFull`, `kindLimitReached` |
| `move(_:to:)` | — | `unknownLayer`, `indexOutOfRange` (0…count − 1) |

## LayerStackError

`unknownLayer(LayerInstanceID)`, `indexOutOfRange(index: Int, validRange: ClosedRange<Int>)`,
`stackFull(limit: Int)`, `kindLimitReached(LayerKind)`.

## Compositor record (internal, Metal)

One per applied entry: id (nil for layers given to `init(device:layers:)`), layer object,
`LayerSlots`, pictures, outcome, prepare error, picture shown this frame. Transitions on apply:
kept (same ID, moved to the new index), created (new ID: factory → unprepared → prepared if a size
is known), released (ID gone).
