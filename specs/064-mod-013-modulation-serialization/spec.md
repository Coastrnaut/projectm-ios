# Feature Specification: MOD-013 Modulation Serialization

**Feature Branch**: `feature/mod-013` (spec directory `064-mod-013-modulation-serialization`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement MOD-013 (Modulation serialization) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Persist graph connections by stable
IDs with migration rules." Acceptance, verbatim: "Round-trip restores every valid edge and flags
orphaned targets." P0, effort M, depends on MOD-001 (typed parameter registry) and SCN-001 (versioned
scene format)."

Identifiers in this feature carry the roadmap ID: requirements `MOD-013-R1…`, success criteria
`MOD-013-S1…`, tasks `MOD-013-T01…`. Other features' IDs are cited as they are: MOD-001 (stable
parameter IDs, retired IDs never reused), MOD-002 (audio feature bindings, 32 at most), MOD-014
(modulation graph validation, readable cycle paths), SHD-009 (expressions), SCN-001-R10/R11 (unknown
content kept; errors refuse a document).

## Baseline: what exists today (audit of 2026-11-13, commit `768a3b1`)

The row's gap status is "Gap candidate". SCN-001 already covers much of the storage; the gaps are
migration, per-edge restore and the report.

| Area | Today (SCN-001, MOD-001, MOD-014) | Gap for this row |
|---|---|---|
| Stable IDs in the document | Bindings store the audio feature ID and the parameter ID; modulation connections store each end by kind and stable ID. | None. |
| Encode → decode | Canonical, semantically lossless for every stored edge (SCN-001 round-trip and property tests). | None. |
| Unknown parameter target | A parameter value with an unknown ID is kept and flagged "orphaned"; a binding to an unknown parameter is an error (`invalidBinding`) that refuses the whole scene. | Orphaned edges must be flagged, kept and not applied, without refusing the scene. |
| Unknown audio feature | A binding or connection naming an audio feature this version does not know refuses decoding of the whole file. | Must be kept and flagged orphaned (forward compatibility). |
| Renamed or retired IDs | MOD-001 forbids renaming; a retired ID is listed in the catalog's retired set and never registered again. Nothing maps an old ID to its replacement. | A declarative migration table: renamed IDs rewritten, retired IDs dropped, both reported. |
| Invalid edge (bad range, duplicate target, bad expression, feedback loop) | An error that refuses the whole scene; a loop is reported at `$.modulation` only. | Each edge is judged on its own: an invalid edge is not applied and is reported at its own path; the rest of the scene opens. |
| Live restore | `liveState` hands back every binding as written; the modulation section is copied as is. | Only valid (and migrated) edges become live; the rest are reported and preserved. |
| Capture | Bindings and the modulation section are written from the live state. | Preserved (unapplied) edges must be written back, in a canonical order, so a round trip is a fixed point. |
| Report | Validation issues with code, path and message. | A per-edge restore report: restored, rewritten, dropped, orphaned and rejected, each with its path. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A saved scene comes back with all its working connections (Priority: P1)

A performer saves a scene whose parameters follow audio features and whose generators drive
parameters, then opens it later (or on another device with the same app version). Every connection
that was valid when saved is live again and moves its parameter exactly as before.

**Why this priority**: This is the row's acceptance: "Round-trip restores every valid edge".

**Independent Test**: Build a live set of bindings and connections, capture it as a document, encode,
decode and restore it, then drive the original and the restored set with the same audio sequence and
clock: the modulated values are identical, and capturing again gives the same document.

**Acceptance Scenarios**:

1. **Given** a scene with valid bindings (some with expressions, envelopes and every mix mode) and
   valid connections, **When** it is saved and restored, **Then** every edge is live, in the saved
   order, and the report lists each as restored.
2. **Given** a restored scene, **When** it is captured and saved again, **Then** the document is the
   same as the one loaded (a fixed point).

### User Story 2 - Connections to things this version does not have are flagged, not lost (Priority: P1)

A scene refers to a parameter or audio feature this version does not know (made by a newer version,
or naming a parameter that was removed). Opening it does not fail: the scene opens, the unknown
connections are listed as orphaned with where they are in the document, they have no effect, and
saving the scene again keeps them.

**Why this priority**: The second half of the acceptance: "flags orphaned targets".

**Independent Test**: A document with connections to an unknown parameter and from an unknown audio
feature opens; the report lists both as orphaned at their paths; re-saving keeps both verbatim.

**Acceptance Scenarios**:

1. **Given** a binding to an unknown parameter and one from an unknown audio feature, **When** the
   scene opens, **Then** both are reported as orphaned with their paths, neither is applied, the other
   edges are live, and a re-save keeps both unchanged.
2. **Given** a connection in the modulation section to an unknown parameter, **When** the scene
   opens, **Then** it is reported as orphaned and kept.

### User Story 3 - Renamed and retired IDs follow migration rules (Priority: P2)

When a later version replaces a parameter or audio feature (new ID, old one retired), scenes saved
before keep working: connections to the old ID are rewritten to the new one and reported; connections
to an ID that was retired without replacement are dropped and reported. Rules added over several
versions compose: an ID renamed twice reaches its latest name.

**Why this priority**: Required by the row ("with migration rules"); no ID has been renamed yet, so it
protects future versions rather than today's scenes.

**Independent Test**: A test catalog renames one ID twice across versions and retires another; a
document saved with the oldest names restores with the newest, the report shows each rewrite and drop,
and a table with a loop is refused.

**Acceptance Scenarios**:

1. **Given** a rule "A renamed to B" and a later rule "B renamed to C", **When** a scene bound to A
   opens, **Then** the binding is live on C and reported as rewritten from A to C; re-saving writes C.
2. **Given** an ID retired without replacement, **When** a scene bound to it opens, **Then** the
   binding is dropped, reported, and not written on re-save.
3. **Given** a migration table where A becomes B and B becomes A, **When** the catalog is built,
   **Then** it is refused with the loop named.

### User Story 4 - Invalid connections do not block the scene (Priority: P2)

A scene holds a connection that this version refuses (an out-of-range mapping, a second binding of
the same parameter, an expression that does not compile, a connection that closes a feedback loop).
The scene opens with every other edge live; the refused edge is reported at its own path with the
reason (a loop with its readable path) and kept in the document.

**Why this priority**: Per-edge restore is what makes "every valid edge" true when some edges are not
valid.

**Independent Test**: A document with a feedback loop and an invalid binding opens; the report names
the closing connection with the loop path and the binding with its reason; all other edges are live.

**Acceptance Scenarios**:

1. **Given** connections A → B and B → A, **When** the scene opens, **Then** the first (in document
   order) is live and the second is reported as rejected with the loop's path.

### Edge Cases

- An ID renamed to an ID that was later retired: the edge is dropped (the chain ends retired).
- An edge rewritten onto a parameter another binding already targets: the first in document order is
  live; the other is rejected as a duplicate target and kept.
- A document with every category at once: each edge appears exactly once in the report.
- An empty migration table: every ID resolves to itself; behavior equals plain restore.
- Malformed IDs (bad syntax): rejected, never orphaned (no version can ever know them).
- A generator declaration that is itself invalid (malformed ID, duplicate): the document is
  contradictory and refused as SCN-001 refuses errors.
- Expression text that names a renamed audio feature is not rewritten; if it no longer compiles the
  binding is rejected.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-013-R1**: Every connection (binding or modulation-section connection) is stored by the stable
  IDs of its ends (audio feature ID, parameter ID, generator ID) and its input name, never by a
  position or display name (already true; kept).
- **MOD-013-R2**: The parameter catalog carries a declarative migration table: append-only rules, each
  "ID renamed to ID" or "ID retired", each tagged with the table version that added it, covering
  parameter IDs and audio feature IDs.
- **MOD-013-R3**: Migration rules compose: resolving an ID follows renames to the end of the chain;
  resolving an already-resolved ID changes nothing (idempotent); a table whose renames form a loop, rename
  an ID to itself, name one ID twice, or mix parameter and audio feature IDs in one rule is refused when
  the catalog is built, with a readable reason.
- **MOD-013-R4**: The table is checked against the catalog: a renamed or retired parameter ID must be
  in the catalog's retired set and not registered; a rename chain must end at a registered (or retired)
  ID; audio feature renames must end at a feature this version knows.
- **MOD-013-R5**: Restoring a scene judges each edge on its own, in document order, and puts it in
  exactly one category: restored (valid, IDs unchanged), rewritten (valid after migration), dropped
  (an end is retired), orphaned (an end is unknown to this version but well-formed), or rejected
  (malformed ID, invalid binding, duplicate target, expression that does not compile, structural
  problem, or a connection that would close a feedback loop).
- **MOD-013-R6**: Only restored and rewritten edges are applied to the live modulation; they evaluate
  exactly as they did before saving (same values for the same audio input and clock).
- **MOD-013-R7**: The restore returns a report listing every edge once with its document path,
  category, the edge as written, the edge as applied (rewritten), and a readable reason; it is also
  reflected in the scene's issues (warnings, so none of these refuses the scene).
- **MOD-013-R8**: A connection that would close a feedback loop is rejected and the loop path is named;
  edges are accepted greedily in document order, so earlier edges win.
- **MOD-013-R9**: Orphaned and rejected edges are preserved: capturing and saving the restored scene
  writes them back unchanged. Dropped edges are not written back. Rewritten edges are written with
  their new IDs.
- **MOD-013-R10**: Capture writes edges in a canonical order (live edges in their live order, then
  preserved edges in their document order), so capture → save → open → restore → capture gives the
  same document after the first capture.
- **MOD-013-R11**: A binding or connection naming an audio feature this version does not know is read,
  kept and flagged orphaned instead of refusing the file (forward compatibility).
- **MOD-013-R12**: Plain code with no app dependency, tested on every CI host including Linux; no
  simulator or device is needed (no app code changes).

### Key Entities

- **Migration rule**: an old stable ID, what became of it (renamed to a new ID, or retired), and the
  table version that added it.
- **Migration table**: the ordered, append-only rules of one catalog, with its version.
- **Restore report entry**: one edge's path, category, edge as written, edge as applied, reason.
- **Preserved edges**: the orphaned and rejected bindings and connections, kept verbatim for re-save.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-013-S1**: For a document with valid, renamed, retired, unknown-target, unknown-source,
  expression and feedback-loop edges, the report lists exactly the expected category and path for each
  edge (7 of 7 categories as specified), and the scene opens.
- **MOD-013-S2**: Every valid edge restored from a saved scene produces the same modulated values as
  the original for a fixed 64-frame input sequence and clock (100% bit-identical).
- **MOD-013-S3**: Capture → save → open → restore → capture is a fixed point for 100% of 200 seeded
  random documents, and every orphaned and rejected edge survives the re-save.
- **MOD-013-S4**: Every migration-table rule (chaining, idempotence, loop refused, self-rename,
  duplicate, cross-kind, catalog consistency) has a test; each unit test runs in under 2 s and each
  touched package's suite in under 1 minute, on the Mac host and the Linux shape.

## Assumptions

- No ID has been renamed or retired yet in the shipping catalog, so the app's table is empty; tests use
  a test catalog.
- Parameter values (the scene's `parameters` map) keep SCN-001's orphan handling; migrating stored
  values by the same table belongs to SCN-013 (scene migrations).
- Generators are not evaluated yet (MOD-007 onward); "live" for the modulation section means the
  validated graph the app will run.
- Expression text is stored as written; it is never rewritten by migration.

## Scope

| In this row | Later rows |
|---|---|
| Migration table, per-edge restore, report, preserving capture | SCN-002 calls restore from the app; SCN-012 shows the report |
| Forward-compatible unknown audio features | SCN-013 migrates scene format versions and parameter values |
| | MOD-007+ evaluate generators; MOD-012 shows and edits edges |
