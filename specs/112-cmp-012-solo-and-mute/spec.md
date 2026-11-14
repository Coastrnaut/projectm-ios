# Feature Specification: CMP-012 Solo and Mute

**Feature Branch**: `feature/cmp-012` (spec directory `112-cmp-012-solo-and-mute`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement CMP-012 (Solo and mute) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Allow non-destructive solo and mute of layers." Acceptance, verbatim:
"Solo isolates selected layer without changing saved enable flags." Verification: unit tests,
snapshots and GPU performance. P1, size S. Depends on CMP-002 (layer stack); works with CMP-011
(layer groups), SCN-001 (scene format), SCN-002 (autosave), SCN-010 (undo)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-012-R1…`, success criteria `CMP-012-S1…`, tasks `CMP-012-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `35179456`)

The row's gap status is "Gap candidate". The audit confirms a full gap: nothing can solo or mute a
layer without editing the saved scene.

| Area | Today | Gap for this row |
|---|---|---|
| Layer stack (CMP-002, `LayerStack`) | An ordered list of at most 8 entries, each with an ID, a descriptor, composite settings and (CMP-011) an optional group. Its header notes that "solo/mute will add fields". | No solo, no mute. |
| Per-layer "enabled" | **No layer has an enabled flag.** A layer is hidden today only by opacity 0 (CMP-003) or by a switched-off group. | The only saved enable flags are the groups' `enabled` (CMP-011); the layer values that decide visibility are each layer's saved opacity. |
| Groups (CMP-011, ADR-0039) | A group record (enabled, opacity, transform) over one unbroken run. A disabled group draws nothing, but its layers keep rendering. A group is drawn isolated unless flattening is exact. | Nothing shows one layer of a group alone, or hides a group, without editing the group. |
| Compositor draw loop | Every layer renders every frame; a layer is composited when it has a picture and its shown opacity is above 0. | No transient per-layer visibility. |
| Scene format (SCN-001, ADR-0028 and CMP-006/007/011 amendments) | The document stores each layer's composite (opacity, blend, transform, fit, mask) and the groups' `enabled`. | Must not change. |
| Autosave (SCN-002) | Captures `SceneInputs` (the visual choice and Settings values) into a document; no live stack is captured. | Must never capture solo or mute. |
| Undo (SCN-010) | Whole-document snapshots (canonical bytes); a record whose bytes equal the current state is suppressed. | Must never record solo or mute. |
| Show cues (SHOW-*) and scene archives (FILE-*) | Store scene documents. | Must never carry solo or mute. |
| UI | The visual hosts build fixed stacks; no screen edits a layer stack (re-checked for this row: CMP-006, CMP-007, CMP-011 found none). | None required. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the recommended, conservative option.

- Q: Where do solo and mute live, and are they ever saved? → A: In a **transient view-state overlay
  kept outside the layer stack and the document**: a separate value handed to the compositor. They
  are **never saved** (not in scenes, autosave, undo history, show cues or archives) and **never
  written** to any layer's opacity or any group's enabled flag. Because the overlay is not part of
  the stack, anything that saves or compares the stack cannot see it. Rationale: "non-destructive"
  is the acceptance; solo and mute are performance-time monitoring, like a mixer's solo buttons.
  Rejected: fields on the stack entry (every capture path would have to remember to drop them; the
  stack's equality would change), a saved per-layer `muted` flag (destructive by definition).
- Q: What is the visibility rule, and which wins when a layer is both soloed and muted? → A: A layer
  is **drawn** when its own conditions hold (it has a picture, its opacity is above 0, its group if
  any is switched on with opacity above 0), **and** it is **not muted**, its **group is not muted**,
  **and** either **no solo is active**, or the layer is soloed, or its group is soloed. Several solos
  combine as a **union**. **Mute wins over solo**: a soloed and muted layer is hidden. A solo still
  counts as active while its layer is muted (the other layers stay hidden), so muting a soloed layer
  never suddenly brings the whole stack back. A solo or mute that names a layer or group no longer
  in the stack is ignored (it cannot black out the picture). Rationale: matches mixing-desk and
  editor conventions (mute is the stronger, explicit "off").
- Q: How do solo and mute work with groups? → A: **Soloing a group** shows all its layers (each
  still subject to its own mute). **Soloing a layer inside a group** shows the group with only that
  layer: the group's opacity and transform still apply, and the group is drawn isolated exactly
  when the CMP-011 rule says so for its remaining visible layers. **Muting a group** hides all its
  layers. A switched-off group stays hidden whatever is soloed (solo never overrides a saved enable
  flag). Groups do not nest (CMP-011), so there is no deeper case.
- Q: Do hidden layers keep running, including expensive sources (camera, video)? → A: **Yes.** A
  muted or unsoloed layer is skipped only when compositing; its source keeps rendering every frame
  (as a layer at opacity 0 and the layers of a disabled group do), so un-muting shows a current
  frame immediately with no prepare, restart or reload. The cost is the hidden layers' render work,
  the same as today's for opacity 0; the composite work drops. Recorded, not changed.
- Q: Is solo or mute undoable, and is there a UI? → A: **Not undoable**: undo history holds scene
  documents only, and solo and mute never change the document, so recording one is suppressed by the
  existing byte-equality rule. **No UI and no launch argument** in this row: no screen edits a layer
  stack, so there is no user-visible surface to drive; the behaviour is tested at the package level
  (CPU model and GPU read-back). The layer inspector (CMP-015) will add the buttons. Loading a
  different scene into a compositor clears the overlay (the caller's duty, documented in the
  contract), because a restored scene reuses its saved instance IDs.
- Q: Does a solo or mute change take effect at once or fade in and out? → A: **At once, from the
  next frame, with no fade** (like a transform or group on/off change). A running opacity fade of a
  hidden layer continues underneath. The composite flash guard (FX-019) still limits an abrupt
  change in brightness, and its history is kept (solo is not a new scene). Rationale: monitoring
  needs an immediate answer; an opacity-style fade would need a second animator per layer and would
  make "bit-identical after clearing" depend on timing. Rejected: a fixed 100 ms fade.
- Q: What can tests and diagnostics read? → A: The compositor reports, per layer index, whether the
  overlay hides that layer in the next frame, and the number of layers the overlay hid in the last
  frame; the overlay value itself is readable. Nothing is logged (performance-time state, no
  telemetry).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Solo a layer to see it alone, without changing the scene (Priority: P1) 🎯 MVP

A performer or scene author solos one layer to check what it contributes. Only that layer is drawn.
The scene itself is untouched: every layer's saved opacity and every group's saved on/off flag are
unchanged, saving or autosaving stores nothing about the solo, and un-soloing shows exactly the
picture from before.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: A stack of three coloured layers; solo the middle one; read the pixels back and
find only its colour. Encode the scene before, during and after the solo and compare the bytes;
compare every layer's opacity and every group's enabled flag. Un-solo and compare the frame with the
one from before, bit for bit.

**Acceptance Scenarios**:

1. **Given** three opaque layers, **When** the middle one is soloed, **Then** the read-back shows
   only that layer.
2. **Given** a soloed layer, **When** the scene is encoded, **Then** the bytes equal those before
   the solo, and every saved opacity and group enabled flag is unchanged.
3. **Given** a soloed layer, **When** solo is cleared, **Then** the frame is bit-identical to the
   frame before the solo, and the scene's bytes are still unchanged.
4. **Given** two soloed layers, **When** composited, **Then** both and only both are drawn, in stack
   order.

---

### User Story 2 - Mute a layer, and combine mute with solo (Priority: P1)

A performer mutes a layer to hide it for a moment. The scene is untouched, the layer keeps running,
and un-muting brings it back at once, current. Mute wins over solo.

**Why this priority**: "Solo and mute" is the row's behaviour.

**Independent Test**: Read-back with one layer muted; with a layer soloed and muted; un-mute and
compare with the previous frame; count the layer's preparations across mute and un-mute.

**Acceptance Scenarios**:

1. **Given** three layers, **When** the top one is muted, **Then** the read-back equals the stack
   without it.
2. **Given** a soloed layer that is also muted, **When** composited, **Then** nothing of it is drawn
   and the other layers stay hidden.
3. **Given** a muted layer, **When** frames advance, **Then** it keeps rendering; **When** it is
   un-muted, **Then** it is drawn from the next frame with no new preparation.

---

### User Story 3 - Solo and mute with groups (Priority: P2)

Soloing a group shows its layers; soloing one layer of a group shows it through the group's opacity
and transform; muting a group hides it.

**Why this priority**: Groups (CMP-011) must keep working with the overlay.

**Independent Test**: GPU read-back for a group solo, a solo of one child of a faded and moved
group, and a group mute.

**Acceptance Scenarios**:

1. **Given** a group of two layers and a layer outside it, **When** the group is soloed, **Then**
   only the group's layers are drawn.
2. **Given** a moved group at opacity 0.5, **When** one of its layers is soloed, **Then** only that
   layer is drawn, moved and at half opacity, matching the reference.
3. **Given** a group, **When** it is muted, **Then** none of its layers is drawn and they keep
   rendering.
4. **Given** a switched-off group, **When** one of its layers is soloed, **Then** nothing is drawn
   (solo never overrides a saved flag).

### Edge Cases

- A solo on a layer that is unavailable or at opacity 0: the solo is active, nothing of that layer
  shows, the others stay hidden (a black or transparent frame) — the performer sees that the soloed
  layer is empty.
- A solo or mute naming a layer or group that was removed from the stack: ignored.
- Solo and mute while an opacity fade runs: the fade continues while hidden; un-hiding shows its
  current value.
- A stack edit (add, move, remove) while a solo is active: the overlay is kept for IDs still present.
- The flash guard keeps working: a solo that changes the picture abruptly is limited like any other
  change (solo is not a new scene; its history is kept).
- Layers given to the compositor without a stack ID (CMP-001 fixed lists) cannot be soloed or muted.

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-012-R1**: The system MUST offer solo and mute for each layer and each group of the applied
  stack, set, cleared and queried between frames, plus a clear-all.
- **CMP-012-R2**: Solo and mute MUST be kept outside the layer stack and the scene document: they
  MUST NOT change any layer's settings or any group's settings, the stack's equality, or the encoded
  scene.
- **CMP-012-R3**: A layer MUST be drawn only when its existing conditions hold and it is not muted,
  its group is not muted, and no solo is active or it or its group is soloed. Solos combine as a
  union; mute wins over solo; a solo stays active while its layer is muted.
- **CMP-012-R4**: Solo and mute entries naming layers or groups not in the applied stack MUST be
  ignored.
- **CMP-012-R5**: Soloing a group MUST show its layers; soloing a layer of a group MUST show it with
  the group's opacity and transform; muting a group MUST hide its layers; a switched-off group MUST
  stay hidden whatever is soloed.
- **CMP-012-R6**: A hidden (muted or unsoloed) layer MUST keep rendering every frame; changing solo
  or mute MUST NOT prepare, re-create or release any layer, picture or source.
- **CMP-012-R7**: Clearing solo and mute MUST restore exactly the previous output (bit-identical
  frame for deterministic layers).
- **CMP-012-R8**: Autosave, undo history, show cues and scene archives MUST never contain solo or
  mute (they store scene documents only).
- **CMP-012-R9**: With no solo and no mute, every frame MUST be drawn exactly as before (existing
  goldens unchanged); a group's isolation decision MUST consider only its layers that are drawn.
- **CMP-012-R10**: Changing solo or mute MUST allocate nothing at a steady size.
- **CMP-012-R11**: A solo or mute change MUST show from the next frame without a fade; running
  opacity fades continue, and the composite flash guard's history is kept.
- **CMP-012-R12**: The compositor MUST report which layers the overlay hides and how many it hid in
  the last frame (tests and diagnostics; nothing is logged).

### Key Entities

- **Solo/mute overlay**: the transient sets of soloed layers, muted layers, soloed groups and muted
  groups; never saved.
- **Effective visibility**: whether a layer is composited this frame (existing conditions plus the
  overlay).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-012-S1**: With one layer soloed, 100 % of read-back pixels show only that layer; the encoded
  scene and every saved opacity and group enabled flag are byte-identical before, during and after
  the solo.
- **CMP-012-S2**: Mute, multi-solo, solo plus mute and the three group cases each match their
  reference (exact for identity placements, within 0.01 for faded and moved groups).
- **CMP-012-S3**: Clearing solo or mute restores a bit-identical frame in 100 % of the tested cases.
- **CMP-012-S4**: 0 preparations and 0 picture allocations are caused by solo or mute changes.
- **CMP-012-S5**: 0 undo steps and 0 autosave changes are caused by solo or mute.
- **CMP-012-S6**: The frame time with half the layers muted versus none is measured on the Mac and
  recorded as not device evidence.

## Assumptions

- No layer-editing screen exists, so no UI is added (re-checked for this row); CMP-015 will add the
  buttons.
- Layers have no enabled flag of their own; "saved enable flags" means the groups' saved `enabled`
  and, as the layers' saved visibility, their saved opacity. Adding a per-layer enabled flag is out
  of scope (it would be a format change and is not what the row asks).
- Solo and mute are per compositor (per visual host); there is one visible compositor at a time.
