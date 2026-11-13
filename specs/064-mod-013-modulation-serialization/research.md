# Research: MOD-013 Modulation Serialization

## Audit: acceptance mapped onto what exists (commit `768a3b1`)

| Acceptance part | Covered by SCN-001 / MOD-014 | Missing (this row) |
|---|---|---|
| Edges stored by stable IDs | `SceneEncoder.binding`, `.modulation`; `AudioFeatureSource.id`, `ModulationNode.id` | — |
| Encode/decode lossless | `SceneRoundTripTests`, `ScenePropertyTests` (500 seeded scenes) | — |
| "restores every valid edge" | `liveState` returns bindings as written | Only valid edges applied; migrated IDs; evaluation equal to the original; fixed point through capture |
| "flags orphaned targets" | Orphaned parameter *values* (`orphanedParameter`); a binding to an unknown ID is an *error* refusing the scene; an unknown audio feature refuses decoding | Orphaned edges flagged per path, kept, not applied, preserved on re-save |
| "migration rules" | MOD-001 retired set (never reused); nothing maps old → new | Migration table, chaining, idempotence, loop refusal, catalog checks |
| Feedback loops | MOD-014 validator refuses with a readable path, reported at `$.modulation` | The closing connection named at its own path; the rest live |

## MOD-013-D1: where the migration table lives and its format

- **Decision**: `ModulationIDMigrations` in ParameterGraph, carried by `ParameterRegistry` (built with
  the catalog, like `retiredIDs`). Format version 1: an ordered list of rules
  `{from, change: renamed(to) | retired, since}`; `since` is the table version that added the rule
  (≥ 1, non-decreasing down the list); the table's `version` is the largest `since` (0 when empty).
  Rules for audio feature IDs are those whose `from` starts with `audio.`; all others are parameter
  IDs.
- **Composition across app versions**: append-only. Version N's table is version N−1's plus new rules
  at the end. A rename chain (A → B in v2, B → C in v3) resolves A to C; resolution of a resolved ID is
  itself (idempotent: a chain's end has no rule). Refused on construction: a duplicate `from`, a
  self-rename, a rename across kinds, `since` < 1 or decreasing, malformed IDs, and loops (each ID has
  at most one rule, so the renames form a functional graph; walking from each rule with a visited set
  finds any loop in linear time, named as `a → b → a`). MOD-014's validator is not reused: it needs
  a registry and its node kinds; a functional-graph walk is simpler and exact.
- **Catalog checks** (`ParameterRegistry.init`): a parameter rule's `from` must be in `retiredIDs` and
  not registered (MOD-001: a shipped ID is never reused, so a rename is "retire old + register new +
  rule"); a rename chain must end at a registered or retired ID; audio rules: `from` must not be a
  feature this version knows, and a rename chain must end at one it knows.
- **Resolution with the registry**: rules first, then the retired set: a chain (or a plain ID) that
  ends at a retired ID resolves to "retired". So retiring a parameter needs no rule; retiring an audio
  feature (not in any registry) does.
- **Alternatives**: a table in SceneFormat (rejected: MIDI, OSC and presets will store the same IDs);
  rewriting documents by format version (that is SCN-013, for structure, not IDs); allowing ID reuse
  after retirement (rejected by MOD-001).

## MOD-013-D2: per-edge restore categories and precedence

- **Decision**: each binding and each modulation connection gets exactly one outcome, checked in this
  order: (1) **rejected** if an ID is malformed; (2) **dropped** if either end resolves to retired;
  (3) **orphaned** if either end is well-formed but unknown (parameter not registered, audio feature
  unknown); (4) **rejected** if invalid in this version (binding: duplicate target after migration,
  expression does not compile, MOD-002 bind refusal; connection: any MOD-014 issue when added to the
  accepted edges, a loop included); (5) **rewritten** if an ID changed, else **restored**.
- **Rationale**: dropped beats orphaned because a retired ID can never return; orphaned beats invalid
  because the edge cannot be judged without its end; malformed IDs are never orphans (no version can
  know them). A connection to an undeclared generator is rejected (the document defines its own
  generators).
- **Issues**: rewritten → `migratedReference`; dropped → `retiredReference`; orphaned →
  `orphanedBinding` / `orphanedConnection`; rejected → `invalidBinding`, `duplicateBindingTarget`,
  `invalidExpression` (existing, now warnings) or `rejectedConnection` (new). Generator-declaration and
  graph-size problems stay `invalidModulation` errors.

## MOD-013-D3: feedback loops

- **Decision**: greedy acceptance in document order: binding edges first (audio features have no
  inputs, so they never close a loop), then each connection is validated together with the accepted
  edges and the declared generators; any issue rejects it with the issue's message (for a loop, the
  readable path ending with the closing connection). At most 256 connections × one linear validation.
- **Alternatives**: reject every edge on the loop (loses more than needed); refuse the document
  (SCN-001's behavior, contrary to "restores every valid edge").

## MOD-013-D4: preserved edges and canonical capture order

- **Decision**: the live state carries `preserved` (orphaned and rejected bindings and connections,
  verbatim with unknown fields). Capture writes applied bindings in live order, then preserved
  bindings in document order; generators as live; applied connections in live order, then preserved
  connections. Dropped edges are not written. After the first capture the cycle capture → encode →
  decode → restore → capture is byte-identical, because each edge's outcome depends only on the
  edges before it and applied edges keep their relative order ahead of preserved ones.
- **Known limit**: unknown fields of *applied* bindings are not carried through the live state
  (SCN-001 behavior; `AudioFeatureBinding` has no room for them). Recorded in ADR-0028.

## MOD-013-D5: unknown audio features in the document

- **Decision**: decoding no longer refuses `audio.band.128` or `audio.somethingNew`: a binding keeps
  `sourceID` as text; a connection end of kind `audio` keeps its ID (`SceneNodeRef.audio(String)`).
  Unknown node *kinds* stay decode errors (structural).
- **Rationale**: a newer version with more bands or features must not make older apps refuse the
  whole scene (SCN-001-R10 spirit).

## MOD-013-D6: expressions

- **Decision**: expression text is never rewritten by migration. It is compiled (never evaluated) as
  in SCN-001; a binding whose expression does not compile is rejected. Expressions of applied bindings
  are keyed by the migrated target.
