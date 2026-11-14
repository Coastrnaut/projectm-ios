# ADR-0039: Layer Groups Are Isolated, Flattened Only When Exact

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: CMP-011 (`specs/109-cmp-011-layer-groups`)
- **Constitution**: VI (modular boundaries), X (evidence-based quality; an ADR for a rule that affects
  every frame)
- **Builds on**: ADR-0013 (unified layer protocol: linear premultiplied `rgba16Float` pictures and
  composite), CMP-003 (opacity), CMP-005 (transforms), ADR-0037 (blend modes), CMP-007 (masks),
  ADR-0028 (scene document)
- **Amends**: ADR-0013's composite contract gains groups; ADR-0028 gains the top-level `groups`

## Context

CMP-011 groups several layers for a shared transform, opacity and enabled state. Group opacity has two
common meanings. Multiplying each member's opacity is free but wrong where members overlap: the lower
member shows through the upper one, which no editor calls "group opacity". Fading the group as one
picture (W3C Compositing "isolation", a precomposition) is right but needs the members combined first,
an extra pass. Blend modes complicate it: a screen or multiply member of a "pass-through" group blends
with the layers under the group, but once the group is drawn on its own it blends only with the
group's other members, so switching between the two when a fade starts would make the picture jump.

## Decision

1. **A group is an isolated group.** Its members (with their own opacity, blend mode, mask and fit,
   placed by `G(a)·L(a)`) are combined in order on a cleared picture, which is then drawn over what
   lies below with premultiplied "over" × the group's (animated) opacity. Inside a group, members blend
   with each other only, at every opacity.
2. **Flattening is an optimisation, used only when exact**: group opacity exactly 1 and every visible
   member in normal mode. Premultiplied "over" is associative, so drawing the members straight onto
   the composite gives the same result (within half-float rounding of the intermediate) and costs no
   pass. The rule lives in `LayerGroupComposition.needsIsolation`.
3. **Disabled or opacity-0 groups draw nothing**; their members keep rendering (as a layer at opacity
   0 does), so clocks, last-good frames and fades stay current.
4. **The group itself has no blend mode and no mask** in this version; both could later be applied when
   its picture is drawn, on the same path.
5. **No nesting**: one group picture (and its blend-mode partner) is open at a time; both come from the
   texture pool at the first isolated draw at a size and return at a size change and release.

## Consequences

- Faded groups look like one picture; overlaps never show through. GPU read-back matches the CPU
  reference exactly (`LayerGroupCompositeTests`, docs/test-reports/layer-groups.md).
- Grouping a layer with a non-normal blend mode changes what it blends with (the group's members, not
  the layers under the group), and such a group always costs one pass more. Documented in the
  contract; an editor can explain it when the layer inspector (CMP-015) shows groups.
- Normal-only groups at opacity 1, and every stack without groups, draw exactly as before (existing
  goldens unchanged).
- Mac GPU time of a 4-layer group at 1080p: flattened as ungrouped, isolated about 0.06 ms more per
  frame (not device evidence).

## Alternatives rejected

- Per-member opacity multiplication: overlaps show through.
- Pass-through at opacity 1, isolated below 1: a non-normal member would jump when a fade starts.
- Always isolated: a pass per group even when flattening is exact and free.
