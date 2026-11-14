# Feature Specification: CMP-011 Layer Groups

**Feature Branch**: `feature/cmp-011` (spec directory `109-cmp-011-layer-groups`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement CMP-011 (Layer groups) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Group multiple layers for shared transform, opacity and enable
state." Acceptance, verbatim: "Moving group shifts all children and preserves local transforms."
Verification: unit tests, snapshots and GPU performance. P1, size L. Depends on CMP-005 (transforms,
integrated); works with CMP-003 (opacity), CMP-004 (blend modes), CMP-006 (fit), CMP-007 (masks) and
SCN-001 (scene format), SCN-012 (repair report), SCN-013/QA-004 (migration matrix)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-011-R1…`, success criteria `CMP-011-S1…`, tasks `CMP-011-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `b75c685f`)

The row's gap status is "Gap candidate". The audit confirms a full gap: layers cannot be grouped.

| Area | Today | Gap for this row |
|---|---|---|
| Layer stack (CMP-002, `LayerStack`) | A flat, ordered list of at most 8 entries (bottom first), each with an ID, a descriptor and composite settings. Its header notes that "groups … will add fields". | No group, no membership. |
| Composite settings (CMP-001 contract) | Per layer: opacity (CMP-003, animated), blend mode (CMP-004), transform (CMP-005), fit (CMP-006), mask (CMP-007). | Nothing shared by several layers. |
| Compositor draw paths | One open premultiplied "over" pass on an `rgba16Float` composite; transformed layers sampled through the inverse placement matrix; masked layers multiply coverage in the same pass; each non-normal blend mode ends the pass and blends into a pooled second composite (ping-pong). | No way to combine a shared transform with a layer's own, and no way to fade several layers as one (group opacity). |
| Transforms (CMP-005) | Four values per layer giving one affine matrix per output aspect; matrices compose (`*`). | A composed group × local placement is in general not one `LayerTransform` (shear), so it must be drawn as a matrix. |
| Scene format (SCN-001, ADR-0028) | Version 1. Unknown top-level and layer fields are kept verbatim; `composite` is closed (unknown keys dropped). CMP-006 and CMP-007 added optional fields without a version bump. | No place for groups. |
| Repair report (SCN-012), migration matrix (SCN-013, QA-004) | Every issue code maps to a group and an optional repair action; the QA-004 meta-test scans the decode-error and migration-error enums. | Degenerate group structures need issues and a repair. |
| UI | No screen edits a layer stack's composite settings (CMP-006 and CMP-007 confirmed; re-checked for this row). | None required. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative option.

- Q: May groups contain other groups, and how is membership kept consistent with the stack order?
  → A: **No nesting in this version** (depth 1: a group contains layers only). A group's layers are
  **one unbroken run** of the stack and its child order is the stack order; membership is stored per
  stack entry, and add, duplicate, move and remove follow one rule that keeps every run unbroken
  (CMP-011-R4). Rationale: a stack holds at most 8 layers, so nesting buys little while it would
  need a stack of offscreen pictures, nested opacity rules and recursive repair. A nested child from
  a newer version is a degenerate structure (CMP-011-R12). Rejected: nesting to depth 4 (cost and
  test surface out of proportion to 8 layers); non-contiguous groups (an isolated group would
  reorder its layers relative to the layers between them).
- Q: What does group opacity mean: multiply each layer's opacity, or fade the group as one picture?
  → A: **The group is an isolated group** (W3C Compositing "isolation"): its layers are combined
  among themselves on transparent, and the result is drawn over what lies below at the group's
  opacity. **Flattening is an optimisation only**, used exactly when it gives the same result:
  group opacity exactly 1 and every visible child in normal mode (premultiplied "over" is
  associative), so such groups cost no pass. Otherwise the group is drawn into a pooled offscreen
  picture first (one extra pass, plus its blend-mode passes inside). Consequences: overlapping
  children never show through each other when faded; a non-normal child blends with the group's
  layers below it, not with layers under the group, at every opacity, so fading never makes the
  picture jump. Rejected: per-child multiplication (cheap but overlaps show through, and it is not
  what "group opacity" means in any editor); "pass-through" at opacity 1 and isolated below 1 (a
  screen or multiply child would jump when a fade starts). Recorded in ADR-0039.
- Q: Does the group itself get a blend mode or a mask, and what does a switched-off group do?
  → A: **Neither, for now**: each child keeps its own opacity, blend mode, mask and fit (CMP-011-R10);
  a group blend mode or mask can be added later on the same offscreen path. A **switched-off group**
  hides all its children; the children **keep rendering** (as a layer at opacity 0 does, CMP-003),
  so their clocks and last-good frames stay current and switching the group on shows a current
  frame immediately. Group opacity 0 likewise draws nothing of the group. Group opacity is animated
  with the same transitions as layer opacity; transform and on/off changes show from the next frame.
- Q: How are groups saved in the scene document? → A: As an optional **top-level `groups` array**,
  written only when the scene has groups (format version stays 1; scenes without groups encode
  byte-identically; QA-004 gains no row): each item
  `{"id": <1…2^53−1>, "name": "<text>", "enabled": <bool>, "opacity": <0…1>, "transform": <CMP-005
  form>, "children": [<layer instance IDs>]}`, every field written in full, groups in stack order of
  their first child, children in stack order. Missing optional fields read defaults (name "",
  enabled true, opacity 1, identity transform); opacity and transform are clamped with
  `valueClamped`; unknown group fields are kept verbatim. Rationale: an older app keeps an unknown
  top-level field verbatim on decode → encode, whereas unknown `composite` keys are dropped, and a
  per-layer `parent` field would scatter the group's own fields (name, opacity, transform) over its
  children. Rejected: a `parent` field on layers; a version bump.
- Q: What happens with degenerate group structures, and is there a UI? → A: **Warnings, never
  refusals**: validation reports a new warning `invalidGroup` (a repeated or out-of-range group ID,
  a child that is not a layer instance of the scene, a layer repeated or claimed by an earlier
  group, an empty group, children that are not one unbroken run). The first valid claim wins, in
  document order. A damaged group is **drawn ungrouped** and kept verbatim for re-save; SCN-012
  lists it under "Damaged file" as a problem with the new repair **"Fix layer groups"**
  (`repairGroups`), which drops the bad child references and then removes groups still invalid.
  More than 8 groups, or more than 8 children in one group, are a `tooMany` refusal (the existing
  case; the QA-004 meta-test is unchanged). **No UI**: no screen edits a layer stack's composite
  settings (re-checked 2026-11-14; the layer inspector, CMP-015, will add one).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Move a group and all its layers move together (Priority: P1) 🎯 MVP

A scene author (or a show cue, or code) puts several layers into a group and then moves, scales or
rotates the group. Every layer in the group moves with it, as one rigid picture, while each layer
keeps its own placement inside the group. Removing the group's transform (or ungrouping) puts every
layer back where it was.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: Two small coloured layers at known positions inside a group; move, scale and
rotate the group; read the pixels back and find each colour where the combined placement predicts.
Check that each layer's own placement is unchanged in the stack and after a save and reload.

**Acceptance Scenarios**:

1. **Given** a group with a red and a green layer at known positions, **When** the group is moved
   right by a quarter of the output, **Then** both colours appear a quarter of the output further
   right and nothing else changes.
2. **Given** the same group, **When** it is scaled or rotated about its anchor, **Then** each colour
   appears where the group placement applied after the layer's own placement predicts.
3. **Given** a moved group, **When** the stack is inspected, **Then** every child's own transform
   equals what it was before the move.
4. **Given** a moved group, **When** the scene is saved and reopened, **Then** the group's transform
   and every child's own transform are unchanged.

---

### User Story 2 - Fade or hide a group as one (Priority: P1)

The author fades a group (its opacity) or switches it off. A faded group looks like one picture made
semi-transparent: where its layers overlap, the lower layer does not show through the upper one. A
switched-off group hides every layer in it, whatever their own settings.

**Why this priority**: Shared opacity and enable state are the rest of the row's behaviour.

**Independent Test**: Two overlapping opaque layers in a group over a backdrop; set the group's
opacity to one half; compare the read-back with a plain reference calculation. Switch the group off
and check that only the backdrop remains.

**Acceptance Scenarios**:

1. **Given** a group of two overlapping opaque layers at opacity 0.5 over a backdrop, **When**
   composited, **Then** the overlap shows half the upper layer and half the backdrop (no trace of
   the lower layer), matching the reference.
2. **Given** a group at opacity 1 with only normal layers, **When** composited, **Then** the result
   equals the same layers ungrouped (within half-float rounding) and costs no extra pass.
3. **Given** a switched-off group, **When** composited, **Then** none of its layers is visible.
4. **Given** a group opacity change applied with a transition, **When** frames advance, **Then**
   the group fades to the new opacity like a layer does.

---

### User Story 3 - Layer settings keep working inside groups (Priority: P2)

Each layer in a group keeps its own opacity, blend mode, mask and fit. The group adds only its
transform, opacity and on/off state.

**Why this priority**: Groups must not break what exists.

**Independent Test**: GPU read-back of grouped layers with a mask, a fit and a non-normal blend mode,
compared with the reference.

**Acceptance Scenarios**:

1. **Given** a masked layer in a moved group, **When** composited, **Then** the mask moves with the
   layer (outside pixels stay exactly transparent).
2. **Given** a grouped layer with the screen blend mode, **When** composited, **Then** it blends with
   the layers below it inside the group, as the group semantics define.
3. **Given** a fitted photo in a group, **When** composited, **Then** the fit is unchanged and moves
   with the group.

---

### User Story 4 - Scenes keep groups, and damaged groups are reported (Priority: P1)

A scene stores its groups: name, on/off, opacity, transform and the layers in each. Opening and
saving keeps them exactly. A scene written before this feature is unchanged. A damaged group (a
missing layer, a layer in two groups, a gap in the group, a nested group from a newer version) does
not stop the scene from opening: it is reported, its layers are drawn ungrouped, and a repair
removes the damage.

**Why this priority**: "Preserves local transforms" includes persistence; robustness to bad files
is a project rule.

**Independent Test**: Decode → encode and decode → load → capture → encode of scenes with groups;
decode of scenes with each degenerate structure, checking the repair report and the repair.

**Acceptance Scenarios**:

1. **Given** a scene with a moved group of two layers, **When** decoded and encoded, **Then** the
   bytes are identical; **When** loaded and captured, **Then** the bytes are identical too.
2. **Given** a scene without groups, **When** decoded and encoded, **Then** the bytes are unchanged
   and the scene format version is unchanged.
3. **Given** a group that lists a layer the scene does not have, **When** opened, **Then** the
   repair report lists the problem, the scene opens with that group's layers ungrouped, and the
   repair drops the missing reference and keeps the rest of the group.
4. **Given** groups that overlap, leave a gap or nest, **When** opened, **Then** each damaged group
   is reported and drawn ungrouped, and the repair removes it.

### Edge Cases

- A group whose layers are all unavailable or at opacity 0: nothing is drawn, as today.
- A group at opacity 0: nothing of the group is drawn; its layers keep rendering.
- A switched-off group whose layers have their own fades running: the fades continue; switching
  the group on shows their current values.
- A layer added, moved or duplicated next to or inside a group: membership follows one rule
  (requirement CMP-011-R4) so a group always occupies one unbroken run of the stack.
- Removing the last layer of a group removes the group.
- Ungrouping keeps each layer's own transform and opacity (the group's are not baked in).
- An output size change: groups keep their relative placement (transforms are in output fractions).
- A group whose composed placement shears a layer (group rotation over a non-uniformly scaled
  layer): drawn exactly by the composed matrix.

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-011-R1**: The layer stack MUST support groups: each has a stable ID, a name, an on/off flag,
  an opacity (0…1) and a transform (the CMP-005 representation), and contains one or more layers.
- **CMP-011-R2**: A group's layers MUST occupy one unbroken run of the stack, in stack order (the
  group's child order is the stack order). Groups MUST NOT nest in this version.
- **CMP-011-R3**: The stack MUST offer: group a run of ungrouped layers, ungroup, change a group's
  settings, and move a whole group; every operation succeeds or throws a typed error and leaves the
  stack unchanged.
- **CMP-011-R4**: Adding, duplicating, moving and removing layers MUST keep every group one unbroken
  run: a layer placed between two layers of the same group joins that group; a layer moved out of
  its group's run leaves it; a duplicate joins its original's group; a group left without layers is
  removed.
- **CMP-011-R5**: A grouped layer's drawn placement MUST be the group's placement applied after the
  layer's own (group ∘ local), for the current output aspect; the layer's own transform MUST stay
  unchanged in the stack. A group has no picture of its own, so its anchor (pivot) is in fractions
  of the output (centre by default).
- **CMP-011-R6**: A switched-off group MUST hide all its layers.
- **CMP-011-R7**: Group opacity MUST act on the group as one picture: the group's layers are
  combined first and the result is drawn over what lies below at the group's opacity (an isolated
  group). Inside a group, layers combine with each other only.
- **CMP-011-R8**: When the result is mathematically the same, the group MUST be drawn without an
  extra pass (group opacity 1 and only normal-mode layers visible), and layers outside groups and
  groups at identity, opacity 1 and on MUST draw exactly as before (existing goldens unchanged).
- **CMP-011-R9**: Group opacity changes MUST support the same transitions as layer opacity
  (CMP-003); transform and on/off changes show from the next frame without re-creating any layer.
- **CMP-011-R10**: Each grouped layer MUST keep its own opacity, blend mode, mask and fit; the group
  itself has no blend mode and no mask in this version.
- **CMP-011-R11**: The scene format MUST store groups as an optional top-level value written only
  when a scene has groups, with the format version unchanged; scenes without groups MUST encode
  byte-identically, and a scene with groups MUST round-trip byte for byte (decode → encode and
  load → capture → encode).
- **CMP-011-R12**: Degenerate group structures (a missing or repeated layer, a layer in two groups,
  a gap, an empty group, a repeated or out-of-range group ID, a nested or unknown child) MUST NOT
  refuse the scene: validation reports each as a warning, the damaged group is drawn ungrouped and
  kept for re-save, SCN-012's repair report lists it with a repair that removes the damage, and the
  QA-004 meta-test still passes.
- **CMP-011-R13**: Group offscreen pictures MUST come from the compositor's texture pool, be created
  only when first needed at a size, and be returned on size change and release; nothing is created
  per frame at a steady size.

### Key Entities

- **Layer group**: ID, name, on/off, opacity, transform, and the run of layers it contains.
- **Membership**: which group (if any) a stack entry belongs to.
- **Effective placement**: the composed group ∘ local matrix a grouped layer is drawn with.
- **Saved group**: the scene's record of a group: its fields and its layers' instance IDs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-011-S1**: For a group moved, scaled and rotated, each child colour's measured centre in the
  read-back is within 1 pixel of the predicted position, and 100 % of children keep their own
  transform unchanged in the stack and after save and reload.
- **CMP-011-S2**: Group opacity read-backs match the reference within 0.01 per channel; a
  switched-off group leaves 0 pixels of its layers.
- **CMP-011-S3**: Grouped layers with a mask, a fit and a non-normal blend mode match the reference
  within 0.01; flattened groups (opacity 1, normal layers) add 0 passes.
- **CMP-011-S4**: 100 % of group scene round trips are byte-identical; scenes without groups and
  existing golden renders are unchanged; every degenerate structure gives at least one repair-report
  entry and opens; QA-004's meta-test passes with no new format version.
- **CMP-011-S5**: The time of a 4-layer group, drawn flattened and drawn as one picture, is measured
  on the Mac and recorded as not device evidence.

## Assumptions

- No layer-editing screen exists, so no UI is added (re-checked for this row).
- Older app versions keep an unknown top-level field verbatim when they re-encode a decoded scene,
  and draw the layers ungrouped; a capture-and-save in an older app loses the groups, accepted as for
  other newer optional data.
- At most 8 layers per stack means at most 8 groups; nesting adds little at that size.
