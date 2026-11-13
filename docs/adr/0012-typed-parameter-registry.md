# ADR-0012: Typed parameter registry

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4; feature MOD-001)
- **Date**: 2026-11-13
- **Spec**: `specs/028-mod-001-typed-parameter-registry/` (research MOD-001-D1 to D8, contract
  `contracts/parameter-registry.md`)
- **Constitution**: I, VI, VII, IX, X; Privacy

## Context

The roadmap's parameter boundary (architecture item 3) requires "a typed registry [that] provides
stable parameter IDs, units, ranges, default, current manual value and modulation policies", with
graph edges persisted by stable IDs. Modulation (MOD-002…017), MIDI, OSC, scenes (SCN-001, MOD-013),
keyframes (SHOW-008), parameter UI (UIX-003/004/009) and accessibility (ACC-005) all build on it.
Before MOD-001 each visual's options lived in its own configuration type with ranges as Swift
constants, and the app stored a subset under `settings.*` keys.

## Decisions

1. **Module.** `Packages/ParameterGraph`: Foundation and Synchronization only, no dependency,
   Linux-tested. The app's catalog is the `VisualParameters` target in `Packages/VisualGenerators`,
   next to the types it describes (D1).
2. **Identity.** IDs are dotted ASCII names, `domain.subject.name`, each segment
   `[a-z][A-Za-z0-9]*`, ≤ 128 characters (`visual.circularSpectrum.innerRadius`,
   `effect.bloom.radius`). Shipped IDs are never renamed, reused or re-kinded; retired IDs stay in
   a retired list and can never be registered again. Everything that persists or routes uses IDs
   (D2).
3. **Kinds.** continuous (Double, range, optional step hint, curve hint), integer (range, step),
   boolean, enum (stable case IDs), color (linear RGBA in 0…1). Values travel as a tagged
   `ParameterValue`; Float-backed parameters are converted with `Double(Float)` (D3).
4. **Validation.** A catalog is validated as a whole when built and rejected with every issue
   listed: duplicate IDs (naming both registrations' names and source sites), malformed IDs,
   groups or enum cases, non-finite numbers, empty ranges, bad steps, defaults out of range,
   contradictory modulation policies, retired IDs (D4).
5. **Values.** `ParameterStore` is a lock-protected `Sendable` class usable from any thread
   (never from the audio callback). Sets clamp (integers snap to step; continuous never snaps),
   reject non-finite numbers, wrong kinds and unknown IDs/cases, and notify observers
   synchronously after the lock is released; a change counter supports polling (D5, D6).
6. **Snapshots.** A versioned `Codable` snapshot keyed by ID is the hand-off to scene persistence
   and the rollback mechanism; restore reports orphaned and rejected entries. MOD-001 writes
   nothing to disk (D7).
7. **Modulation policy.** Per parameter: modulatable or not, allowed mix modes (replace, add,
   multiply; add/multiply only for numeric kinds), and whether MIDI/OSC may set the manual value.
   Continuous visual parameters are modulatable; bar counts, orientation and bloom on/off are
   manual only (external control allowed).
8. **Scope of the first catalog.** 14 parameters of the circular and linear spectra and the bloom,
   with ranges and defaults read from the configuration types and a drift test. Reduce flashing is a
   safety setting and is never registered, so no modulation, MIDI, OSC or scene can change it. The
   app's settings keep their own storage; routing them through the store is left to the first
   consumer that needs live values.

## Consequences

- Later rows bind, map and persist by ID with no new identity scheme; MOD-013 inherits orphan
  reporting; MOD-014 adds edges and cycle checks on top of this registry.
- Parameters with dependent ranges (the spectra's length scales) and unbounded ones (angles) need a
  follow-up rule before they can be registered.
- Adding a parameter means one descriptor in the catalog; the drift test and validation run in CI
  on every host.

## Alternatives rejected

- Registering inside the app (drift test only on simulators).
- Making the configuration types read their ranges from the registry (inverts dependencies,
  touches three tested types for no behavior change).
- A main-actor or actor-isolated store (forces hops for MIDI and render consumers).
- UUID or integer IDs (unreadable in scenes, collide across features).

## Amendment 2026-11-13 (MOD-013, ID migration table)

Decided under the owner's standing approval (owner rule 4); specs/064-mod-013-modulation-serialization
(research MOD-013-D1, contract M1, M2).

- The registry carries an append-only `ModulationIDMigrations` table (format version 1): rules
  "old renamed to new" or "old retired", each tagged with the table version that added it. Rules are
  never edited or removed; renames chain and resolution is idempotent; loops, self-renames,
  duplicate rules, cross-kind renames (parameter ↔ audio feature) and decreasing versions are refused
  when the table is built.
- Identity rules are unchanged: a shipped ID is still never reused. Replacing a parameter means
  retiring the old ID, registering a new one and appending a rename rule; the registry refuses a rule
  whose old ID is registered or not retired, and a chain that ends at an ID neither registered nor
  retired. Audio feature IDs (`audio.` prefix) have no registry, so retiring one needs a rule.
- `resolveParameter` applies the rules, then the retired set; consumers that store IDs (scenes now,
  MIDI and OSC maps later) resolve through it. `VisualParameterCatalog.migrations` is empty: nothing
  has been renamed yet.
