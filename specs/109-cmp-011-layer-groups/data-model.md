# Data Model: CMP-011 Layer Groups

## LayerGroupID (Compositor)

- `rawValue: UInt64`; unique within a stack, never reused by it (own counter, separate from layer IDs).

## LayerGroupSettings (Compositor)

| Field | Type | Rule |
|---|---|---|
| `name` | String | free text (UI rows apply their own rule) |
| `isEnabled` | Bool | false hides every child |
| `opacity` | Double | clamped 0…1; non-finite reads 1 (as `LayerCompositeSettings`) |
| `transform` | `LayerTransform` | CMP-005; anchor in output fractions (pivot on the output) |

## LayerGroup (Compositor)

- `id: LayerGroupID`, `settings: LayerGroupSettings`.

## LayerStackEntry (amended)

- `group: LayerGroupID?` — nil: ungrouped.

## LayerStack (amended)

- `groups: [LayerGroup]` in order of their run's first index.
- Invariants: every `entry.group` names a group of `groups`; each group has ≥ 1 member; members are
  one unbroken run; no nesting.
- Errors (`LayerStackError`, new): `unknownGroup`, `duplicateGroup`, `emptyGroup`,
  `groupNotContiguous`, `layerAlreadyGrouped`, `layersNotContiguous`, `splitsGroup`.

## Effective composite (derived, per frame)

- placement `G(a) · L(a)` (a = output aspect), or the layer's own when G is the identity;
- isolation: `opacity < 1 || any visible child mode != normal`;
- visibility: group enabled and group opacity > 0.

## SceneGroup (SceneFormat)

| Field | Saved key | Default | Rule |
|---|---|---|---|
| `id` | `id` | required | integer 1…2^53−1, unique among groups (else `invalidGroup`) |
| `name` | `name` | `""` | string |
| `enabled` | `enabled` | true | bool |
| `opacity` | `opacity` | 1 | clamped 0…1 (`valueClamped`) |
| `transform` | `transform` | identity | CMP-005 form, clamped (`valueClamped`) |
| `children` | `children` | `[]` | `.layer(instance)` or `.other(JSON)` kept verbatim |
| `extra` | unknown keys | — | kept verbatim |

- `SceneDocument.groups: [SceneGroup]` (written only when non-empty).
- `SceneLiveState.preservedGroups: [SceneGroup]` (invalid groups, re-saved verbatim after live ones).
- `SceneIssue.Code.invalidGroup` (warning) → SCN-012 group "Damaged file", severity problem,
  action `repairGroups` ("Fix layer groups").
