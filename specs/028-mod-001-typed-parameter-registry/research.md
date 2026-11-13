# Research: MOD-001 Typed Parameter Registry

All Technical Context unknowns are resolved below. Decisions were made by Claude under owner
rule 4 (conservative, local-first); ADR-0012 records the model.

## MOD-001-D1: Where the model and the catalog live

- **Decision**: The model is a new Foundation-only package `Packages/ParameterGraph` (the
  roadmap's proposed layout). The app's catalog is a new target `VisualParameters` in
  `Packages/VisualGenerators`, depending on `ParameterGraph`, `VisualGenerators` and
  `VisualEffects`, added to the package's one library product.
- **Rationale**: The catalog must read the configuration types' constants (single source of
  truth), so it cannot live in `ParameterGraph` without that package depending on rendering code
  (Constitution VI). Putting it in the app would make the drift test an app test (simulator only,
  slow) instead of a host/Linux package test. One product keeps CI's `-scheme VisualGenerators`
  covering every target, as the package header requires.
- **Alternatives**: making the configuration types read their ranges from the registry (inverts the
  dependency: VisualGenerators would depend on ParameterGraph for its own clamps; a larger change to
  three tested types for no behavior gain); a catalog in the app (drift test only on a simulator).

## MOD-001-D2: ID syntax and stability rule

- **Decision**: `domain.subject.name`: two or more segments separated by `.`, each matching
  `[a-z][A-Za-z0-9]*`, total length ≤ 128. Domains in use: `visual` (native visuals), `effect`
  (post-processing). IDs are never renamed or reused; a retired ID goes into the catalog's retired
  list, and registering it fails validation. Group IDs use the same syntax with one or more
  segments. Enum case IDs match `[a-z0-9][A-Za-z0-9]*`.
- **Rationale**: Dotted lower-camel names match the existing `settings.*` key style, are valid
  OSC address parts after a `.`→`/` swap (OSC-003), readable in scene files (SCN-001) and safe as
  JSON keys. ASCII only avoids Unicode normalization ambiguity.
- **Alternatives**: UUIDs (stable but unreadable in scenes and routes); integer IDs (collide across
  features); reverse-DNS with the bundle ID (verbose, no benefit inside one app).

## MOD-001-D3: Value kinds

- **Decision**: continuous (Double; min < max finite; optional step > 0 as a presentation hint;
  curve hint linear / logarithmic / exponential; logarithmic requires min > 0), integer (Int;
  min < max; step ≥ 1), boolean, enum (ordered cases with stable IDs and display names), color
  (linear, straight-alpha RGBA Doubles in 0…1). Values are stored as Double even for Float-backed
  parameters (bloom), converted with `Double(Float)` so ranges and defaults stay exactly comparable.
- **Rationale**: Covers every existing option and the kinds the roadmap names (color for SHOW-008
  keyframes, enums for MIDI program choices). Double avoids precision loss when mapping
  (MOD-003/004).
- **Alternatives**: generic `Parameter<Value>` types only (cannot be stored in one ordered
  catalog without type erasure; persistence needs a closed set anyway).

## MOD-001-D4: Validation

- **Decision**: `ParameterRegistry.init(descriptors:retiredIDs:) throws(ParameterRegistryError)`
  checks every descriptor and the whole set, collects all issues in registration order, and throws
  one error listing them. Each descriptor records its registration site (`#fileID`, `#line`) so a
  duplicate names both registrations.
- **Rationale**: One readable report per broken catalog; typed throws keep call sites precise.
  The acceptance ("Duplicate IDs fail validation and defaults remain in range") becomes two tests
  over representative fixtures (owner rule 7).
- **Alternatives**: `precondition` at registration (crashes, untestable); first-error-only (slower
  fix loop).

## MOD-001-D5: Store isolation and notification

- **Decision**: `ParameterStore` is a `final class` conforming to `Sendable`, holding its state in
  a `Mutex` (Synchronization). Observers are `@Sendable (ParameterChange) -> Void` closures
  registered with `observe(_:)`, which returns a token whose `cancel()` (or deinit) removes them.
  After an effective change the store copies the observer list under the lock, releases it, then
  calls observers synchronously on the caller's thread. A `changeCount` (UInt64) increments per
  effective change.
- **Rationale**: Consumers sit on different executors (SwiftUI on the main actor, MIDI on a CoreMIDI
  thread, a render loop on its own thread); a lock with no actor hop is deterministic in tests and
  usable from a render loop. Synchronous calls make test ordering exact. `Mutex` is public API on
  every target platform (iOS 18+, macOS 15, Linux).
- **Alternatives**: `@MainActor` store (forces hops for MIDI/render consumers); an `actor`
  (async access from a render loop); `AsyncStream` notifications (scheduling-dependent tests).

## MOD-001-D6: Clamping and invalid values

- **Decision**: see Clarifications Q4: non-finite rejected; continuous clamp, no snap; integer
  snap-then-clamp; color per-component clamp; wrong kind, unknown ID and unknown enum case
  rejected via `ParameterStoreError`. Setting an equal value is not a change.
- **Rationale**: Matches the existing configuration types' clamping, keeps modulation continuous,
  and never invents a value for NaN.

## MOD-001-D7: Snapshot format (persistence hand-off and rollback)

- **Decision**: `ParameterSnapshot { schemaVersion: Int = 1; values: [ParameterID: ParameterValue] }`
  encoded as JSON with sorted keys; `ParameterValue` encodes as `{"kind": "...", "value": ...}`
  (`continuous`, `integer`, `boolean`, `enum`, `color` with `[r,g,b,a]`). Restore applies each
  entry like `set` and returns `ParameterRestoreReport` (applied, orphaned IDs, rejected entries
  with reasons); a newer `schemaVersion` is rejected as a whole. Nothing is written to disk.
- **Rationale**: SCN-001 persists values by ID; MOD-013 needs orphan reporting. Explicit kind tags
  keep integer 1 and continuous 1.0 distinct across JSON round trips.
- **Alternatives**: raw `[String: Double]` (loses kind; enums and colors need encoding anyway).

## MOD-001-D8: What the catalog registers

- **Decision**: Clarifications Q2 and Q3: 14 parameters (3 circular, 6 linear, 5 bloom). Units:
  bar counts `count`; inner radius `fractionOfOutput` (radius units, half the shorter side; the
  display name says so); gap and spacing `normalized` (fraction of the slot/pitch); cap thickness
  `fractionOfOutput`; peak hold `seconds`; peak fall `perSecond`; bloom intensity, threshold, knee
  `normalized`; bloom radius `fractionOfOutput`; bloom enabled `none`. Continuous parameters get
  step hints matching the UI's slider precision (0.01; 0.001 for the bloom radius and cap thickness).
- **Rationale**: Every value is read from the types; only units, names and step hints are new
  metadata.
