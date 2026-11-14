# Implementation Plan: CMP-011 Layer Groups

**Branch**: `feature/cmp-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/109-cmp-011-layer-groups/spec.md`

## Summary

Groups are part of the plain-Swift `LayerStack` (membership per entry, group records beside the
entries), composed by the compositor as `group ∘ local` matrices and drawn as isolated groups,
flattened when that is exact; scenes save them as an optional top-level `groups` array.

In `Packages/Compositor`:

- `LayerGroup.swift` (new, target `Compositor`, plain Swift, builds on Linux): `LayerGroupID`,
  `LayerGroupSettings` (name, enabled, opacity clamped 0…1, `LayerTransform`), `LayerGroup`, and
  `LayerGroupComposition` (the composed matrix `G.matrix(aspect) * L.matrix(aspect)` in typed steps,
  and the isolation rule). A `LayerStack` extension adds `makeGroup`, `ungroup`, `setGroupSettings`,
  `moveGroup`, `group(_:)`, `members(of:)`.
- `LayerStack.swift` (small, additive): `LayerStackEntry.group: LayerGroupID?` (init default nil);
  `LayerStack.groups`, a group ID counter, membership upkeep in `add`/`duplicate`/`move`/`remove`
  (research CMP-011-D2), `init(restoring:groups:)` (default `[]`), new `LayerStackError` cases, and
  equality including groups. `entries` becomes `internal(set)` so the extension file can edit it.
- `Compositor.swift` (focused): one group record per group (opacity animator, transform, enabled),
  rebuilt at `apply`; records carry their group. Each frame: group animators advance; the "over"
  loop walks runs: a disabled or fully transparent group draws nothing; a flattenable group's
  children are drawn directly with their composed placement; otherwise the children are drawn into
  a pooled offscreen group composite (with its own blend-mode partner) and that is drawn over the
  composite with `cmp_over` at the group opacity. The per-layer drawing (identity, transformed,
  masked, blend ping-pong) moves into one helper used by both surfaces. New diagnostics:
  `isolatedGroupDraws`, `shownGroupOpacity(of:)`. No shader change: the composed matrix feeds the
  existing `cmp_over_transformed`, `cmp_over_masked` and `cmp_blend` parameter rows.

In `Packages/SceneFormat`:

- `SceneGroup` (id, name, enabled, opacity, transform, children as written, unknown fields) and
  `SceneDocument.groups`; decode of the optional top-level `groups` (counts checked before typed
  decoding: at most 8 groups and 8 children each, `tooMany`), encode only when non-empty;
  validation warning `invalidGroup`; repair action `repairGroups`; `liveState` builds stack groups
  from valid groups and keeps the others in `SceneLiveState.preservedGroups`; capture writes live
  groups (stack order) then preserved ones. Format version unchanged.

Docs: ADR-0039 (isolated group semantics, flattened when exact); amend ADR-0028 and the SCN-001
contract (top-level `groups`, `invalidGroup`), SCN-012's repair table (`repairGroups`); report
`docs/test-reports/layer-groups.md`. No UI (spec Clarifications).

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/layer-groups.md](contracts/layer-groups.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26).

**Primary Dependencies**: Metal (existing pipelines only). No new dependency.

**Storage**: the scene document (top-level `groups`, optional; version 1).

**Testing**: `Packages/Compositor`: `LayerGroupStackTests` (CPU, Linux: operations, membership
rules, restore validation, composed matrices against hand values, isolation rule);
`LayerGroupCompositeTests` (GPU read-back: move/scale/rotate a group of two coloured boxes, local
transforms unchanged; group opacity vs CPU reference; disabled group; flattened = ungrouped; masks,
fit and a screen child inside a group; group opacity fade; no allocation at a steady size;
opt-in GPU time bench `CMP011_BENCH=1`). `Packages/SceneFormat`: `SceneGroupTests` (round trips,
load/capture, old scenes unchanged, each degenerate structure, repair, `tooMany`). Regression:
SceneFormat (incl. QA-004 meta-test), RenderGoldens, ImportFuzz, ShowControl, SceneArchive, app
unit tests; Linux shape of Compositor and SceneFormat.

**Target Platform**: iOS 26+ (app), macOS host and Linux for the plain-Swift parts.

**Performance Goals**: no pass for flattened groups; one offscreen pass (plus one per non-normal
child) per isolated group. GPU time recorded on the Mac (CMP-011-S5), not device evidence.

**Constraints**: owner rule 7 (unit ~1-2 s, suite < 1 min); no wall-clock assertions; no per-frame
objects (offscreen pictures pooled, created at the first isolated draw at a size); additive edits
to shared Compositor files (UIX-015 runs in parallel); typed steps for matrix maths.

**Scale/Scope**: L. One model file, a stack extension, a compositor refactor of the draw loop,
scene format section, ADR.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Metal only; no new shader source | Pass |
| VI Modular boundaries | Model in `Compositor`; document in `SceneFormat`; no layer source changes | Pass |
| VII Real-time audio safety | No audio code touched | Pass |
| X Evidence | CPU references + GPU read-back on the Mac; GPU time labelled not device evidence | Pass |
| X ADR for decisions affecting every frame | ADR-0039 records isolated group semantics | Pass |
| Accessibility / flashing | Groups only move or attenuate light; the flash guard still runs on the finished composite | Pass |
| No networking, privacy | None added | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/109-cmp-011-layer-groups/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/layer-groups.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/LayerGroup.swift                  (new)
Packages/Compositor/Sources/Compositor/LayerStack.swift                  (membership, groups)
Packages/Compositor/Sources/Compositor/Compositor.swift                  (group records, run drawing)
Packages/Compositor/Tests/CompositorTests/LayerGroupStackTests.swift     (new)
Packages/Compositor/Tests/CompositorTests/LayerGroupCompositeTests.swift (new)
Packages/SceneFormat/Sources/SceneFormat/SceneGroup.swift                (new)
Packages/SceneFormat/Sources/SceneFormat/{SceneDocument,SceneDecoding,SceneEncoding,SceneValidation,SceneIssue,SceneLiveState,SceneRepair}.swift
Packages/SceneFormat/Tests/SceneFormatTests/SceneGroupTests.swift        (new)
docs/adr/0039-layer-group-isolation.md                                   (new)
docs/test-reports/layer-groups.md                                        (new)
```

**Structure Decision**: existing packages only; no new target.

## Complexity Tracking

None.
