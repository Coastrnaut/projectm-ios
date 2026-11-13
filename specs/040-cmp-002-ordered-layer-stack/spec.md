# Feature Specification: CMP-002 Ordered Layer Stack

**Feature Branch**: `feature/cmp-002` (spec directory `040-cmp-002-ordered-layer-stack`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (CMP-002-T01-T14 verified on the Mac: host, Linux shape and iOS 27.2 simulator; device task T15 `{device}` open)

**Input**: User description: "Implement CMP-002 (Ordered layer stack) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Add, remove, duplicate and
reorder visual layers." Acceptance, verbatim: "Reordering overlapping red and blue layers changes
topmost color." Depends on CMP-001 (integrated: Packages/Compositor, ADR-0013). Leave room for
CMP-003 (opacity), CMP-004 (blend modes), CMP-005 (transforms), CMP-011 (groups), CMP-012 (solo and
mute) and CMP-014 (transition bus); implement only CMP-002."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-002-R1…`, success criteria `CMP-002-S1…`, tasks `CMP-002-T01…`. Requirements
of other features are cited by their own IDs: CMP-001-R6 to R11 (pictures, fallback, allocation
points, composite settings), CAM-001-R7 (the camera runs only while shown), CAM-012-R4 and R6 (Stop
camera).

## Baseline: what exists today (audit of 2026-11-13, commit `f8069ae`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Compositor | CMP-001's compositor composites a list of layers fixed when it is built, bottom to top, with premultiplied "over"; it rejects the same layer object twice and any non-identity composite settings. Pictures are created and layers prepared before the first frame and on a size change. | The list cannot change after creation: no add, remove, duplicate or reorder. |
| Layers | Spectra (VIS-001, VIS-002), the rear camera (CAM-001) and five procedural materials (SHD-001) are layers; projectM is a layer in ANGLERendering. | Nothing describes a layer independently of its live object, so a stack cannot be edited, compared or (later) saved. |
| App | The Camera visual (CAM-001) builds a fixed two-layer list: camera at the bottom, circular spectrum on top. Its notes say CMP-002 takes this over. | The app has no stack model. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What happens when a caller duplicates the camera layer or adds a second camera? → A: The stack refuses it with "kind limit reached": a layer kind declares how many instances a stack may hold and the camera kind allows one, so the app never asks for a second capture session (one rear camera, one session, one privacy indicator; CAM-001, CAM-012). Rejected: sharing one capture session between two camera layers (two views of the same picture add nothing until transforms and masks exist, and the camera's start/stop and Stop camera would need reference counting across layers); a later row can lift the limit to one session shared by several layers.
- Q: How many layers may a stack hold? → A: At most 8 (CMP-002-R5). Each layer holds one or two full-size pictures (a half-float picture at iPhone 15's full drawable is about 24 MB) and costs a render pass plus a composite draw per frame; 8 bounds that memory and the per-frame work while leaving room for typical scenes (projectM or a material at the bottom, camera, spectra, overlays). The roadmap's performance check uses a 4-layer stack. Rejected: no limit (unbounded GPU memory) and 4 (too tight for groups and masks later).
- Q: Where does a duplicate go and what does it copy? → A: Directly above the original, with a new instance ID and an equal description (kind and parameters) and composite settings; the duplicate's live layer is a new object made by the caller's factory, prepared like any new layer. It does not copy the original's last picture.
- Q: Does changing the stack reset the composite flash guard's history? → A: No. A stack edit is not a new scene: the guard keeps its history, so removing or reordering layers that changes the picture abruptly is still limited by the strobe envelope (FX-019-R11 applies the reset only to a new scene).
- Q: Does this row add a layer editor that people can use? → A: No. The stack is exposed to code only and the app's one stack (the Camera visual) is built through it unchanged. Editing by hand belongs to the layer inspector (CMP-015) and the editing UI rows; saving stacks belongs to the scene rows.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reorder changes what is on top (Priority: P1)

A caller (later: a layer editor or a scene) holds a stack with two overlapping opaque layers, red
and blue. It moves one above the other and hands the new stack to the compositor; from the next
frame the topmost color is the other layer's.

**Why this priority**: It is the row's acceptance.

**Independent Test**: Build a stack red-below-blue; composite one frame; read back blue. Move red to
the top; composite; read back red.

**Acceptance Scenarios**:

1. **Given** a stack [red, blue] (index 0 is the bottom), **When** a frame is composited, **Then**
   every output pixel is blue.
2. **Given** that stack, **When** red is moved to the top and the new stack is applied, **Then** the
   next frame's pixels are red, and neither layer was prepared again.

---

### User Story 2 - Add, remove and duplicate layers (Priority: P1)

A caller adds a layer at a position, removes a layer, or duplicates one (the copy sits directly
above the original with the same kind, parameters and composite settings and its own identity).
Invalid requests (an unknown layer, a position outside the stack, a full stack, a second camera)
are refused with a typed reason and leave the stack unchanged.

**Why this priority**: The rest of the observable behavior.

**Independent Test**: Unit tests on the stack value alone (no GPU), on every host including Linux.

**Acceptance Scenarios**:

1. **Given** an empty stack, **When** three layers are added at the top, at index 0 and at index 1,
   **Then** their order is as requested and each has a distinct identity.
2. **Given** a stack, **When** a layer is duplicated, **Then** the copy is directly above the
   original, has a new identity and equal kind, parameters and settings.
3. **Given** a full stack, **When** a layer is added or duplicated, **Then** the request is refused
   and the stack is unchanged.
4. **Given** a stack with a camera layer, **When** a second camera is added or the camera is
   duplicated, **Then** the request is refused.

---

### User Story 3 - Edits apply between frames without stalls (Priority: P1)

The compositor takes a new stack between frames. Layers that are still in the stack keep their
prepared state and pictures; only new layers are created and prepared; removed layers are released.
Applying the same stack again changes nothing. Frames at a steady size allocate no pictures.

**Why this priority**: An edit must not make the visual stutter or leak GPU memory.

**Independent Test**: Count each test layer's preparations and the compositor's picture
creations across applies and a 60-frame loop; hold a weak reference to a removed layer.

**Acceptance Scenarios**:

1. **Given** an applied stack of two prepared layers, **When** a stack with a third layer is
   applied, **Then** only the third is created and prepared.
2. **Given** an applied stack, **When** the same stack is applied again, **Then** no layer is
   created, prepared or released.
3. **Given** an applied stack, **When** a layer is removed and the stack applied, **Then** the
   compositor no longer holds the removed layer.
4. **Given** an applied stack at a steady size, **When** 60 frames are composited, **Then** no
   picture is created.

---

### User Story 4 - The Camera visual is unchanged (Priority: P2)

A viewer who chooses the Camera visual sees exactly what they saw before: the camera picture with
the circular spectrum on top, the camera indicator and Stop camera working as before.

**Why this priority**: The app wiring moves to the stack model but must not change behaviour.

**Independent Test**: The existing Camera UI tests and app unit tests pass unchanged.

### Edge Cases

- An empty stack composites to transparent (and the output is black on screen, as today with no
  layers).
- The factory cannot create a layer for an entry (an unknown kind, no GPU resources): the apply is
  refused with a typed error and the compositor keeps the previous stack.
- A new layer's preparation fails: it is shown as unavailable (CMP-001 fallback); other layers are
  unaffected.
- A stack is applied before the first frame: layers are created now and prepared with the first
  frame's size.
- The output size changes after an apply: every layer is prepared again at the new size (CMP-001).
- The factory returns the same object for two entries or one already in use by another entry: the
  apply is refused.
- An entry asks for composite settings CMP-001 cannot draw yet (opacity below 1): the apply is
  refused (CMP-003 lifts this).
- Moving a layer to its own index is a no-op.
- A stack edit makes the picture change abruptly (a bright layer removed or moved to the top): the
  composite flash guard keeps its history and limits it as for any other change.

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-002-R1**: A layer stack MUST be an ordered value: index 0 is the bottom layer and the last
  index is drawn on top; compositing MUST follow that order exactly.
- **CMP-002-R2**: Each entry MUST have a stable instance identity that is unique within the stack
  and never reused by it, a layer descriptor (its kind and its parameters) and its composite
  settings.
- **CMP-002-R3**: The stack MUST support adding a layer at any index from 0 to its count (default:
  the top), removing a layer, duplicating a layer (copy directly above the original, new identity,
  equal descriptor and settings) and moving a layer to any valid index.
- **CMP-002-R4**: Every refused operation MUST report a typed reason (unknown layer, index out of
  range, stack full, kind limit reached) and leave the stack unchanged.
- **CMP-002-R5**: A stack MUST hold at most 8 layers.
- **CMP-002-R6**: A layer kind MAY limit how many instances a stack holds; the camera kind MUST be
  limited to one, so a stack never asks for a second capture session.
- **CMP-002-R7**: The compositor MUST accept a new stack between frames. Layers whose identity is
  still present MUST keep their layer object, pictures, prepared state and last good frame; new
  identities MUST be created through a caller-supplied factory and prepared at the current size
  (or at the first frame's size before any frame); identities no longer present MUST be released.
- **CMP-002-R8**: Applying a stack equal to the applied one MUST create, prepare and release nothing.
- **CMP-002-R9**: An apply MUST be atomic: if any entry cannot be created or is not supported, the
  compositor MUST keep the previous stack and report a typed error naming the entry's index.
- **CMP-002-R10**: Compositing at a steady output size MUST create no pictures, whatever stacks were
  applied before.
- **CMP-002-R11**: Until CMP-003, CMP-004 and CMP-005 extend the compositor, an entry's composite
  settings MUST be the identity values; others MUST be refused at apply.
- **CMP-002-R12**: The stack model and its rules MUST build and be tested on Linux.
- **CMP-002-R13**: The Camera visual MUST build its layers through the stack (camera bottom,
  circular spectrum top) with unchanged appearance and camera behaviour (CAM-001-R7, CAM-012-R4,
  R6).
- **CMP-002-R14**: Applying a stack MUST NOT reset the composite flash guard's history.
- **CMP-002-R15**: The per-layer frame cost of a 4-layer stack MUST be measured on D1-D3 (device
  stage).

### Key Entities

- **Layer instance ID**: the stable identity of one entry; never reused within a stack.
- **Layer kind**: what sort of layer an entry is (camera, circular spectrum, …) and how many
  instances a stack may hold.
- **Layer descriptor**: a kind plus the layer's parameters.
- **Layer stack entry**: an instance ID, a descriptor and composite settings.
- **Layer stack**: the ordered entries, bottom first, and the next free identity.
- **Layer factory**: the caller's function that turns a new entry into a live layer.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-002-S1**: Swapping the order of overlapping opaque red and blue layers changes the topmost
  color of every output pixel, exactly within 1/255 (the acceptance).
- **CMP-002-S2**: 100% of stack operations, valid and refused, behave as specified in unit tests on
  macOS and in the Linux shape.
- **CMP-002-S3**: Reapplying a stack with one added layer prepares exactly one layer; reapplying
  an equal stack prepares none; a removed layer is released.
- **CMP-002-S4**: 0 pictures are created over 60 frames at a steady size after stack changes.
- **CMP-002-S5**: The Camera visual's existing UI tests and the app unit tests pass unchanged.
- **CMP-002-S6**: The per-layer frame cost of a 4-layer stack is recorded for D1, D2 and D3
  (device stage).

## Assumptions

- A user-facing layer editor (add, remove, duplicate, reorder by hand) belongs to a later row: the
  layer inspector (CMP-015) and the editing UI rows; this row exposes the stack to code only and
  changes nothing a user sees.
- Saving stacks with scenes belongs to the scene and persistence rows; the stack is a plain value
  so it can be saved later.
- Opacity (CMP-003), blend modes (CMP-004), transforms (CMP-005), groups (CMP-011) and solo/mute
  (CMP-012) extend the entry later; this row keeps their slots (composite settings) at identity.
