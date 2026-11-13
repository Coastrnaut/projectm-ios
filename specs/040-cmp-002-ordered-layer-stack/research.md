# Research: CMP-002 Ordered Layer Stack

No open NEEDS CLARIFICATION remained after `/speckit-clarify`; these are the design decisions.

## CMP-002-D1: A value stack applied to the compositor, not a mutable compositor

- **Decision**: `LayerStack` is a plain `Equatable, Sendable` value edited by callers; the
  compositor takes a whole stack with `apply(_:makeLayer:)` and diffs it by instance ID.
- **Rationale**: a value can be compared (equal stack → no-op), saved later by scene rows, undone
  by the inspector (CMP-015) and tested on Linux; the compositor keeps one entry point for change.
- **Alternatives**: add/remove/move methods on `Compositor` (couples editing to Metal, untestable on
  Linux, no snapshot equality); rebuilding a compositor per edit (re-prepares every layer and
  recompiles pipelines: a stall).

## CMP-002-D2: Stable instance IDs, never reused within a stack

- **Decision**: `LayerInstanceID` wraps a `UInt64` taken from the stack's counter (starting at 1);
  removal never returns an ID to the pool. Stack equality compares entries only (not the counter).
- **Rationale**: the compositor's reuse rule ("same ID → same live layer") is safe only if an ID
  never names two different layers over time.
- **Alternatives**: UUIDs (not deterministic in tests; larger); indices (change on reorder).

## CMP-002-D3: Kinds are open identifiers declared by layer targets, with an instance limit

- **Decision**: `LayerKind` is an identifier string plus an optional `maximumInstances`; the
  `CameraLayer` target declares `.camera` (limit 1), `SpectrumLayers` declares `.circularSpectrum`
  and `.linearSpectrum` (no limit). The caller's factory maps kinds to live layers.
- **Rationale**: Compositor must not import the layer targets (Constitution VI), and future targets
  (materials, projectM, media) add kinds without touching it.
- **Alternatives**: a closed enum in Compositor (couples it to every layer); a generic stack over a
  caller's descriptor type (harder to save and compare across modules).

## CMP-002-D4: One camera per stack (refuse, not share)

See spec Clarifications. A second camera instance is refused with `kindLimitReached(.camera)`.

## CMP-002-D5: At most 8 layers

See spec Clarifications: bounds GPU memory (1–2 pictures per layer at drawable size) and per-frame
passes; the roadmap's performance check uses 4.

## CMP-002-D6: Apply semantics

- **Decision**: (1) equal stack → return; (2) refuse non-identity settings (CMP-001-R11) by index;
  (3) build the new record list in stack order, reusing records by ID and calling the factory for
  new IDs only; (4) refuse a factory result that is the same object as another record's; (5) commit;
  (6) if a size is known, create pictures and prepare the new layers now (allocation points of
  CMP-001: prepare and resize), otherwise at the first frame. Removed records are dropped, which
  releases their layer and pictures. Any refusal leaves the previous stack in place.
- **Rationale**: preparing at apply keeps the next frame's cost to rendering; reordering is a
  permutation of records, so slots, last good frame and pictures survive a move.
- **Alternatives**: preparing new layers lazily on the next frame (moves the allocation into the
  frame loop, against CMP-001-R9).

## CMP-002-D7: The flash guard keeps its history across applies

See spec Clarifications (CMP-002-R14).

## CMP-002-D8: Recording the decision

- **Decision**: an "Amendment: CMP-002" section in ADR-0013 instead of a new ADR.
- **Rationale**: it changes CMP-001's "fixed list" decision of that ADR; no new default is
  overridden, and a new number could collide with SHD-002 running in parallel.
