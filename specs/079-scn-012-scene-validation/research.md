# Research: SCN-012 Scene Validation

## SCN-012-D1: Where the report lives

- **Decision**: In SceneFormat, next to `validate`, Foundation-free (`SceneRepair.swift`).
- **Rationale**: The report is a pure function of a document and its issues; Linux CI tests it and
  every opener (show, recovery, archive, a future browser) shares it.
- **Alternatives**: in the app (no Linux tests, duplicated per path); in ShowControl (wrong layer).

## SCN-012-D2: How repairs find their targets

- **Decision**: Each action re-runs `validate` (and `restoreModulation` for mappings) on the current
  document and acts on the paths of the issue codes it owns; actions run in one canonical order
  (rename → renumber → remove broken layers → remove extra layers → drop invalid values → drop invalid
  modulation → drop missing media → drop invalid mappings → keep unknown content).
- **Rationale**: one definition of validity (SCN-001 rule "no second definition"); recomputing after
  each step makes the result independent of the order the caller lists actions in and makes repairs
  idempotent (a clean document yields no targets).
- **Alternatives**: acting on the report's stored paths (stale after an earlier action changes
  indexes); a separate validity check in the repair code (two definitions drift).

## SCN-012-D3: Renumbering

- **Decision**: Keep the first layer with each valid ID; give every later duplicate or out-of-range
  layer the smallest positive ID not yet used, in document order.
- **Rationale**: deterministic, keeps existing IDs stable (bindings to layer parameters stay valid),
  and small IDs never exceed the limit.
- **Alternatives**: max + 1 (can overflow near the limit); renumbering all layers (changes valid IDs).

## SCN-012-D4: Mapping repair

- **Decision**: "Drop invalid mappings" keeps exactly the bindings and connections MOD-013 applies
  (outcome restored or rewritten, with their stored text) and drops orphaned, rejected and dropped
  ones. Rewritten edges are kept as written (the migration applies them on every open).
- **Rationale**: MOD-013's greedy per-edge restore is order-stable: removing a rejected edge never
  changes whether an earlier accepted edge is accepted, so the result is idempotent.

## SCN-012-D5: Presentation in the app

- **Decision**: One presenter (`.sheet(item:)`) driven by `SceneRepairCoordinator.pending`, attached to
  the visualizer and to the Settings sheet's content; only the topmost host binds it (Settings while it
  is shown, so a show editor "Go to Cue" gets the report over Settings).
  Only one request at a time: a newer request (another step) replaces a pending one (its cancel
  closure runs). A cue that needs review leaves the output unchanged until Open.
- **Rationale**: steps come from the visualizer controls, the keyboard and the show editor in
  Settings; one pending request keeps the performer in control.
- **Alternatives**: an alert (no room for grouped entries); a banner (no actions).

## SCN-012-D6: Which paths show the report

- **Decision**: Show cues and PERF-010 Reopen show the sheet; the archive import service returns the
  report in its result (SCN-014 will show it; there is no import screen yet); the launch autosave
  restore stays silent (SCN-002 already falls back on errors and logs; the user did not initiate it).
- **Rationale**: the conservative reading of the row: report before opening whenever the user asked
  to open; never interrupt a launch.

## SCN-012-D7: Fuzz

- **Decision**: A seeded linear congruential generator mutates encoded fixture bytes (flip, delete,
  duplicate a span, truncate) and document fields (duplicate IDs, unknown kinds, dangling assets,
  bad bindings); 500 cases; asserts a report for each, repaired documents encode and decode, and
  repairs are idempotent.
- **Rationale**: owner rule 7 (≤ 1 s); deterministic seed for reproducible failures.
