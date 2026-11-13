# Contract: Parameter registry (MOD-001)

The public contract of `Packages/ParameterGraph` and of the app catalog
(`VisualGenerators/VisualParameters`), for MOD-*, MIDI, OSC, SCN, SHOW-008, UIX-003/004/009 and
ACC-005. Types and fields: [data-model.md](../data-model.md). Decisions: ADR-0012.

## C1. Identity

1. A parameter ID is `domain.subject.name` (≥ 2 segments, each `[a-z][A-Za-z0-9]*`, ≤ 128 characters).
2. Once shipped, an ID is never renamed, reused for another meaning, or given another kind. A
   changed meaning gets a new ID; the old one is added to the catalog's retired list and can never
   be registered again (validation fails with `retiredID`).
3. Consumers persist and route by ID only (scenes, MIDI/OSC bindings, modulation edges). They never
   persist array positions or display names.

## C2. Descriptors and catalog

1. A catalog is built once per build from an ordered descriptor list and is immutable.
2. Building a catalog validates it as a whole and throws `ParameterRegistryError` listing every
   issue (data-model `Problem` cases). A duplicate ID's message names the ID and both
   registrations' display names and sites (`file:line`).
3. Enumeration (`descriptors`, `descriptors(inGroup:)`, `ids`, `groups`) is in registration order
   and identical across calls and builds.
4. Every default is finite and inside its range (enforced by validation).

## C3. Value store

1. Starts with every parameter at its default.
2. `set` clamps finite continuous values to range (no snapping), snaps integers to the nearest step
   from the minimum (ties toward the maximum) then clamps, clamps color components to 0…1; it rejects unknown IDs, wrong kinds,
   non-finite numbers and unknown enum case IDs with `ParameterStoreError`, leaving state, change
   count and observers untouched.
3. An effective change (stored value differs) increments `changeCount` by one and then calls
   every observer synchronously on the caller's thread, after the store's lock is released, in
   registration order of the observers. Setting an equal value is not a change.
4. Safe from any thread. Not for the real-time audio callback (it takes a lock).

## C4. Snapshots

1. `snapshot()` returns every current value keyed by ID with `schemaVersion` 1.
2. `restore(_:)` applies entries in ID order with C3 rules and reports applied, orphaned (unknown
   ID) and rejected entries; it never throws for individual entries. A snapshot with a newer
   `schemaVersion` is rejected whole (nothing applied).
3. JSON encoding is stable (sorted keys; each value tagged with its kind).

## C5. Modulation policy (for MOD-002/MOD-011)

1. A parameter that is not modulatable lists no mix modes; MOD-002 must refuse to bind a source
   to it.
2. `add` and `multiply` appear only on continuous and integer parameters.
3. `allowsExternalControl` gates MIDI/OSC manual sets (MIDI-003, OSC-003).

## C6. App catalog

1. `VisualParameterCatalog.descriptors` lists the 14 parameters of data-model.md in that order;
   `makeRegistry()` returns the validated registry.
2. Ranges, defaults and enum cases are read from the configuration types; a package test fails if
   any differs.
3. Not registered (by decision): Reduce flashing (safety; never modulatable or externally
   controllable), performance overlay, preset scope, the visual choice, length scales (dependent
   range), angles and ring direction, palettes and colors.
