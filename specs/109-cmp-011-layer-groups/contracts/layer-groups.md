# Contract: Layer groups (CMP-011)

## Stack operations (`LayerStack`, plain Swift)

| Operation | Effect | Refusals (stack unchanged) |
|---|---|---|
| `makeGroup(_ ids:, settings:) -> LayerGroupID` | the listed layers (any order) become one group | empty list → `emptyGroup`; unknown → `unknownLayer`; already grouped → `layerAlreadyGrouped`; not one unbroken run → `layersNotContiguous` |
| `ungroup(_:) -> LayerGroup` | members become ungrouped; their own settings are untouched | `unknownGroup` |
| `setGroupSettings(_:of:)` | replaces name, enabled, opacity, transform | `unknownGroup` |
| `moveGroup(_:to:)` | the run's bottom lands at `index` of the stack without the run | `unknownGroup`, `indexOutOfRange`, `splitsGroup` |
| `add`, `duplicate`, `move`, `remove` | as before, plus the membership rule (research CMP-011-D2) | as before |
| `init(restoring:groups:)` | rebuilds a saved stack | `duplicateGroup`, `unknownGroup` (entry names a missing group), `emptyGroup`, `groupNotContiguous`, plus the old refusals |

## Drawing (`Compositor`)

1. A layer with no group, or whose group has the identity transform, uses its own placement
   exactly as before. Otherwise its placement is `G(a) · L(a)`.
2. A group that is disabled or whose shown opacity is 0 draws nothing; its children still render.
3. A group whose shown opacity is exactly 1 and whose visible children are all normal is drawn
   flattened (no extra pass).
4. Any other group: children (with their own opacity, blend mode, mask, fit and composed placement)
   are drawn in order onto a cleared offscreen picture (blend modes ping-pong within it); then the
   picture is drawn over the composite with premultiplied "over" × the group's shown opacity.
   `isolatedGroupDraws` counts these per frame.
5. Group opacity changes at `apply` fade with `opacityTransition`; transform and enabled changes
   show from the next frame; nothing is re-created.
6. Offscreen pictures come from the texture pool at the first isolated draw at a size and return at
   size change and release.

## Scene document (SCN-001 version 1, optional top-level `groups`)

```json
"groups": [
  {"id": 1, "name": "Logo", "enabled": true, "opacity": 1,
   "transform": {"version": 1, "translation": {"x": 0.25, "y": 0}, "scale": {"x": 1, "y": 1},
                 "rotation": 0, "anchor": {"x": 0.5, "y": 0.5}},
   "children": [3, 4]}
]
```

- Written only when the scene has groups; every field written; groups in stack order of their first
  child, children in stack order. Unknown group fields are kept.
- Validation warnings `invalidGroup` (first valid claim wins, document order):
  `$.groups[g].id` repeated or out of range; `$.groups[g].children[c]` not a layer instance of the
  scene, repeated, or claimed by an earlier group; `$.groups[g].children` empty or not one unbroken
  run of `$.layers`.
- Invalid groups: drawn ungrouped, kept in `preservedGroups`, written back after the live groups.
- Repair `repairGroups`: drop child references that are not layer numbers, are missing, repeated or
  claimed earlier; then remove groups still invalid. Idempotent.
- More than 8 groups or more than 8 children in a group: `tooMany` refusal.
