# Research: CMP-011 Layer Groups

## CMP-011-D1: Group opacity semantics (ADR-0039)

- **Decision**: a group is an isolated group: children combine on transparent in an offscreen
  `rgba16Float` picture, which is drawn over the composite with premultiplied "over" × the group
  opacity. The compositor flattens (draws children straight onto the composite) exactly when the
  result is the same: group opacity exactly 1 and every visible child in normal mode.
- **Rationale**: premultiplied "over" is associative, so `(cₙ over … over c₁) over B` equals
  `cₙ over (… over (c₁ over B))`; the flattened path differs only by half-float rounding of the
  intermediate (≤ 1/1024 relative). Non-normal modes are not associative with "over", so any group
  with a visible non-normal child is drawn isolated at every opacity: fading never changes which
  backdrop a child blends with (no jump at the start of a fade).
- **Alternatives**: per-child opacity multiplication (overlaps show through; wrong "group opacity");
  pass-through at 1 and isolated below 1 (jump); always isolated (a pass per group even when exact
  flattening is free).

## CMP-011-D2: Membership and the unbroken-run rule

- **Decision**: membership is a field of each stack entry; groups are records beside the entries.
  After `add` (index) and `move`, the placed entry joins group H when both of its neighbours are in
  H; otherwise it leaves its own group when that group is no longer one unbroken run. `duplicate`
  places the copy right above the original with the original's group. `remove` drops groups left
  empty. `moveGroup` moves the whole run and refuses an index strictly inside another group.
- **Rationale**: removing an entry from a run keeps every run unbroken; inserting breaks a run only
  when placed strictly between two of its members, which the join rule covers. So every operation
  keeps the invariant without refusing edits that worked before groups existed.
- **Alternatives**: refuse edits that break a run (older callers would start failing); explicit
  child lists per group (two sources of order).

## CMP-011-D3: Composed placement

- **Decision**: the drawn placement of a grouped layer is the matrix `G(a) · L(a)` (CMP-005's
  `LayerTransformMatrix *`, r first), with `a` the output aspect, computed per frame in typed
  `Double` steps and fed to the existing inverse-matrix shader rows. When the group transform is the
  identity, the layer's own path (and its exact bytes) is used.
- **Rationale**: the product of two CMP-005 matrices can shear (rotation over a non-uniform scale),
  so it is not a `LayerTransform`; the shaders already take a general inverse affine. The group's
  anchor is in output fractions of the output (groups have no picture of their own; the anchor is the
  pivot on the output, centre by default).
- **Alternatives**: bake the group into each child's `LayerTransform` (loses local transforms,
  cannot represent shear).

## CMP-011-D4: Saved form

- **Decision**: top-level `groups` array, written only when non-empty; every field in full;
  unknown group fields kept; children as written (instance numbers; anything else kept and flagged).
- **Rationale**: SCN-001 keeps unknown top-level fields verbatim, so an older app's decode → encode
  keeps groups; composite fields are closed (dropped). One record per group keeps its own fields
  together.
- **Alternatives**: a `parent` field per layer (group fields need a home anyway); a version bump
  (QA-004 row, older apps refuse the file).

## CMP-011-D5: Degenerate structures

- **Decision**: one warning code `invalidGroup` per problem, path at the group or the child; first
  valid claim wins in document order; invalid groups are drawn ungrouped and preserved for re-save;
  repair `repairGroups` drops bad child references (missing, repeated, claimed earlier, not a layer
  number), then removes groups that are still invalid (empty, gap, bad ID). Counts over 8 are the
  existing `tooMany` refusal (checked before typed decoding like layers).
- **Rationale**: a group never carries content, so a damaged one must not block a scene; no new
  decode-error case keeps QA-004's error table unchanged.

## CMP-011-D6: Offscreen pictures

- **Decision**: two pooled pictures (group composite and its blend partner), taken from the
  texture pool at the first isolated draw at a size, reused by every isolated group in the frame
  (groups do not nest, so one is open at a time), returned at size change and release, fenced by the
  last command buffer like every picture.

## CMP-011-D7: Disabled groups keep rendering

- **Decision**: a switched-off group's children still render each frame (not composited), as a
  layer at opacity 0 does (CMP-003); their opacity fades keep advancing.
- **Rationale**: video clocks, last-good frames and fades stay current; re-enabling shows a current
  frame at once. Saving GPU for hidden layers is CMP-012/CMP-013 territory.
