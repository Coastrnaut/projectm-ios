# ADR-0028: Scene Document Format, Version 1

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: SCN-001 (`specs/059-scn-001-versioned-scene-format`)
- **Constitution**: VI (modular boundaries), X (evidence); Security (imported files are untrusted);
  Privacy (no user media in documents)
- **Builds on**: ADR-0012 (parameter registry), ADR-0013 and its CMP-002/003/005 amendments (layer
  stack, opacity, transforms), ADR-0018/0019 (materials, generator graphs), ADR-0020/0022 (stored
  photo and video), ADR-0021 (expressions), ADR-0024 (user content never runs as native code)
- **Number**: 0025 and 0026 are left to the rows the REC-003 ADR (0027) reserved them for.

## Context

The roadmap row SCN-001 asks for one local document holding all layers, parameters, asset
references and mappings, accepted when "decode and re-encode preserve semantic scene content".
Fourteen later SCN rows and MOD-013 store scenes in this form, scene files will be exchanged
(SCN-014), and every piece it holds already has its own rules (CMP-002 stack limits, CMP-005's saved
transform, MOD-001 restore semantics, MOD-002 binding checks, MOD-014 cycle refusal, SHD-011 import
rules). The format must add none of its own definitions of validity.

## Decisions

1. **Package.** `Packages/SceneFormat` (plain Swift, Linux-tested) depends on ParameterGraph and
   Compositor; neither of those knows about persistence. `LayerStack` gains `init(restoring:)` (saved
   instance IDs, next ID = largest + 1), and materials and generator graphs gain layer kinds
   (`material`, `generator.graph`) beside their targets.
2. **Document.** JSON, `format` `projectm-ios.scene`, `version` 1, scene ID (uppercase UUID), name,
   layers bottom first (instance, kind, values, composite with CMP-005's transform object, typed
   content per kind), MOD-001 tagged parameter values by ID, MOD-002 bindings (source, target, input
   and output ranges, mix, envelope, optional SHD-009 expression text), an optional modulation
   section (generators and connections by stable ID) and an asset table. Contract:
   `specs/059-scn-001-versioned-scene-format/contracts/scene-document.md`.
3. **Canonical encoding and equality.** The package owns a bounded JSON reader and a canonical
   writer: no white space, keys sorted by UTF-8 bytes, minimal escaping, doubles in Swift's shortest
   round-trip text, unknown numbers in their written text. Decode → encode reproduces canonical
   bytes exactly. Semantic equality is equality of the canonical JSON values: map key order never
   matters, layer, binding and connection order does, numbers compare by bits.
4. **Versions.** Newer versions are refused whole and the file is never rewritten; SCN-013 adds
   migrations from older versions once version 2 exists. Within version 1, new optional fields may
   be added only at the document, layer, binding and asset level, where unknown fields are kept
   verbatim; unknown layer kinds and asset types are kept as typed `unknown` cases; unknown fields
   in closed value objects are dropped with a warning.
5. **Assets.** Photos and videos are referenced by the app store's UUID identifier, never by a path
   or URL; text overlay settings and generator graph documents are embedded and checked with their
   own decoders (MED-009, SHD-011). A missing photo or video is a warning; a dangling or mistyped
   reference is an error.
6. **Untrusted input.** 1 MiB before parsing, depth 32 while parsing, duplicate keys refused, count
   limits (8 layers, 32 bindings, 1,024 values, 16 assets, 64 values per layer, 64 generators, 256
   connections) before typed decoding. Nothing in a document is executed or loaded: expressions are
   only compiled, graphs only checked, identifiers only resolved by the app's stores.
7. **Validation.** Readable issues with severity, stable code and location; errors block turning a
   document into live state, warnings do not. Parameter values follow MOD-001 restore semantics
   (orphaned and rejected values are warnings, clamping reported); bindings use MOD-002's checks;
   the modulation graph MOD-014's validator (cycles refused with their path).
8. **What a scene never holds.** Safety, accessibility, privacy, network and purchase state
   (Reduce flashing, performance overlay, preset scope, OSC switch and port, the library
   entitlement), and the app's visual choice.

## Consequences

- SCN-002 writes `encoded()` atomically and must merge unknown layers rather than drop them;
  SCN-012 shows the issues; SCN-013 adds migrations; MOD-013 wires the modulation section.
- CMP-004 (blend modes) must extend the capture adapter's blend switch (it stops compiling) and the
  list of drawn blend names. Done 2026-11-14 (ADR-0037): `normal`, `add`, `screen`, `multiply`,
  `overlay`, `difference` are drawn; any other name is kept (through load → capture too) and warned
  about; format version unchanged.
- CMP-006 (aspect fitting, 2026-11-14, specs/101-cmp-006-aspect-fitting) adds the optional
  `composite.fit` (`mode`, `anchor`), written only when set, so existing scenes encode
  byte-identically; unknown mode names are kept and warned (`unsupportedFitMode`); format version
  unchanged (no QA-004 matrix row). An older version drops `fit` with `droppedField`.
- CMP-007 (shape masks, 2026-11-14, specs/104-cmp-007-shape-masks) adds the optional
  `composite.mask` (shape, its parameters, feather, inverted and the mask's own transform), written
  only when set, so existing scenes encode byte-identically; unknown shapes are kept verbatim and
  warned (`unsupportedMaskShape`); unusable polygons drop the mask with `droppedField`; format
  version unchanged (no QA-004 matrix row). An older version drops `mask` with `droppedField` and
  shows the layer unmasked.
- Procedural material values are registry parameters shared by layers of the same material until a
  later row adds per-instance values.

## Amendment 2026-11-13 (MOD-013, modulation serialization)

Decided under the owner's standing approval (owner rule 4); specs/064-mod-013-modulation-serialization
(research MOD-013-D2 to D5, contract M3 to M6).

- **Per-edge restore narrows decision 7 for modulation.** Each binding and modulation connection is
  judged on its own and gets one outcome: restored, rewritten (IDs migrated by ADR-0012's table),
  dropped (an end is retired), orphaned (an end is well-formed but unknown) or rejected (malformed,
  invalid binding, duplicate target, expression that does not compile, MOD-014 problem, a feedback
  loop included). `invalidBinding`, `duplicateBindingTarget` and `invalidExpression` become warnings;
  new warnings `migratedReference`, `retiredReference`, `orphanedBinding`, `orphanedConnection`,
  `rejectedConnection`. One bad edge no longer refuses the scene. Invalid generator declarations
  stay `invalidModulation` errors (the document contradicts itself).
- **Loops**: connections are accepted greedily in document order; the one that closes a loop is
  rejected at its own path with the loop's readable path.
- **Preserved edges**: orphaned and rejected edges are kept verbatim in the live state and written
  back on capture; dropped edges are not (a retired ID never returns); rewritten edges are written
  with their new IDs. Capture writes live edges first (live order), then preserved edges (document
  order), so a document that interleaves them is reordered once and capture → encode → decode →
  restore → capture is byte-identical afterwards. Unknown fields of *applied* bindings are still not
  carried through the live state.
- **Unknown audio features** (`audio.band.128`, a future feature) are decoded and kept instead of
  refusing the file; unknown node kinds remain decode errors.
- `liveState` returns the per-edge `modulationReport`; `SceneLiveState.apply(to:)` and
  `validatedGraph(registry:)` wire the modulator and the MOD-014 graph. Parameter values keep
  decision 7's orphan handling; migrating stored values is SCN-013's.

## Amendment 2026-11-13 (SCN-002, scene autosave)

Decided under the owner's standing approval (owner rule 4); specs/067-scn-002-scene-autosave
(research SCN-002-D1 to D8, contracts/scene-autosave.md). No default is overridden; this records how
the app uses the format.

- **Current scene.** The app autosaves one document for the shown visual: the visual's fixed stack
  (Circular, Linear, Photo, Video, Text; projectM has no compositor layer; Camera records the visual
  chosen before it), the seven registered values the app holds (bar count, linear orientation and
  spacing, glow on, intensity, radius, threshold), the `text`, `photo` and `video` assets, and the
  native spectrum's live bindings. The visual choice itself stays a setting (decision 8).
- **Files.** `Library/Application Support/Scenes/current.scene` and one backup, `current.scene.bak`.
  A save writes `current.scene.tmp`, `F_FULLFSYNC`s it (`fsync` if refused), hard-links the known-good
  main file as the backup, `rename`s the temporary file over the main file and `fsync`s the folder, so
  a committed scene exists at every step. `Data.write(options: .atomic)` is not used (no flush promise).
- **Load.** Main, then backup, through `decode` and `liveState` (decision 7, MOD-013); a damaged file is
  an event, never an error or a blocked launch; a file of a newer version is set aside once as
  `<name>.newer` and never written (decision 4's "never rewritten").
- **Which wins.** A valid committed scene is applied over the settings at launch (MOD-001 restore,
  then AppSettings' setters), so a kill never shows a mix of committed and uncommitted edits. Edits
  commit 1 s after the last change (5 s at most), at once on a visual change, when Settings closes, on
  background and on terminate.
- **Unknown content (Consequences, first bullet).** The restored document is carried: its ID, name and
  unknown fields, layers of kinds the app does not build at their index (renumbered on a collision,
  dropped beyond 8 with an event), matched layers' instances and composites, their assets and assets
  of unknown types, parameter values the app does not hold, bindings, expressions, the modulation
  section and MOD-013's preserved edges.
- **Later rows.** The scene library (SCN-004…006) stores named copies of this document; SCN-003
  duplicates under a new ID; SCN-010 keeps its history over the same capture; SCN-015 locks edits.

## Amendment 2026-11-13 (SCN-003, duplicate and rename)

Decided under the owner's standing approval (owner rule 4); specs/074-scn-003-scene-duplicate-and-rename
(research SCN-003-D1 to D7, contracts/scene-duplicate-rename.md). No default is overridden.

- **Operations.** `SceneDocument.duplicated(newID:name:)` and `renamed(to:)` (SceneEditing.swift) copy
  the value and set only `name`, and `id` for a duplicate. "Kept exactly" is defined on canonical
  bytes: the result's `encoded()` with the original's `id` and `name` put back equals the original's.
  So layers and their instance IDs, parameters, bindings, modulation generators and connections,
  assets (store IDs shared, embedded text and graph documents copied with the value) and unknown
  content at every level are unchanged. Neither validates the rest (a copy keeps the original's
  warnings).
- **IDs.** A duplicate needs a canonical uppercase UUID different from the original's; callers pass
  `UUID().uuidString`, tests fixed IDs. Collisions with other stored scenes are the store's check.
- **Name rule.** One function, `isValidName` (in SceneValidation.swift, the module's only Foundation
  file), used by the validator and by editing: 1…120 characters once white space is trimmed from both
  ends, no control characters. Edited names are stored trimmed (`normalizedName`); decoded names are
  still stored exactly as written. A copy is named `copyName(_:)`: "<name> copy" within 120.
- **References.** Scene IDs are what other documents use (cues, archives, the library later): rename
  keeps them; duplicate gives a new one and never moves an existing reference. Layer instance IDs,
  asset keys and generator IDs are scene-local and stay valid in the copy.

## Amendment 2026-11-13 (SCN-010, undo and redo)

SCN-010 (specs/077-scn-010-scene-undo-redo) keeps a bounded history of the current scene's edits
(research SCN-010-D1 to D7, contracts/scene-history.md). No default is overridden.

- **Model.** `SceneHistory<Value>` (SceneHistory.swift, plain Swift, Linux) stores snapshots: each
  state is the scene's canonical bytes plus the caller's value that re-creates it. Equality of states
  is byte equality, as this ADR defines semantic equality. Snapshots, not diffs or inverse commands:
  app scenes are a few KB and a snapshot cannot drift.
- **Rules.** An edit whose bytes equal the current state is not recorded. Records with the same
  non-nil key coalesce until a boundary (`endCoalescing`, undo, redo, another key); a coalesced edit
  that returns to its starting state drops the step. A new step empties redo. At most 50 steps and
  4 MB of stored bytes (current, undo and redo), the oldest undo steps evicted first, then the
  farthest redo steps. No clock.
- **App.** The value is SCN-002's `SceneInputs`; the bytes are SCN-002's capture over a carry
  snapshot taken when the history (re)starts, so they cover the ordered layer stack and every
  app-held parameter. Undo and redo apply through the Settings/cue path; SCN-002 then commits the
  change under its own rules. The history is in memory only and empty at launch. A cue, Reopen and a
  photo or video replacement restart it; the audio source, safety and accessibility settings, OSC,
  blackout and the camera are outside scenes and never undone.

## Amendment 2026-11-13 (SCN-012, scene validation and repair report)

SCN-012 (specs/079-scn-012-scene-validation) reports a scene's problems before it opens and offers
repairs (research SCN-012-D1 to D7, contracts/scene-repair-report.md). No default is overridden.

- **Report.** `SceneRepairReport` (SceneRepair.swift, plain Swift without Foundation, Linux) maps each
  decode refusal, decode warning, validation issue and MOD-013 per-edge problem to an entry: one of
  six groups (damaged file, unsupported version, missing media, invalid mappings, unknown content
  kept, values adjusted), a severity (note, problem, needs repair, cannot open), the item in plain
  words, the problem, what happens if opened anyway, and its repair actions. No second definition of
  validity: every entry comes from an existing code. An error with a repair is "needs repair"; an
  error without one (an invalid scene ID) and every refusal (newer version, damaged bytes, limits)
  is "cannot open". Warnings the user should see before opening are missing media, invalid mappings
  and unknown layer kinds; the rest are notes that open silently as before.
- **Repairs.** Nine actions in one canonical order (rename, renumber layers, remove damaged layers,
  remove extra layers, drop invalid values, remove invalid generators, drop missing media, drop
  invalid mappings, keep unknown content). Each re-validates the document it is given and acts only on
  its own codes' paths, so repairs are deterministic, independent of the order given and idempotent.
  Renumbering keeps the first valid holder of an ID and gives the others the smallest free IDs.
  Mappings keep exactly what MOD-013 applies. The scene ID, unknown layer kinds, unknown fields and
  unknown parameter values are never removed.
- **App.** A show step whose scene needs review, and PERF-010's Reopen whose held scene does, present
  the report first (Open with repairs, Open as is only without errors, Cancel or Close). Repairs apply
  to the live output only; the stored file is never written. The archive import result carries the
  report for the SCN-014 screen; the launch restore stays silent (SCN-002 already falls back).

## Amendment 2026-11-13 (SCN-013, scene migration)

SCN-013 (specs/081-scn-013-scene-migration) adds the mechanism that brings an older format version to
the current one, keeps the original file and records what changed (research SCN-013-D1 to D8,
contracts/scene-migration.md). No default is overridden.

- **History.** Version 1 is the only scene format version ever written: `currentVersion` has been 1
  since the package was created (`7b620b7`), the encoder's output shape has not changed since (only
  Swift type names), and every writer uses the one canonical encoder. No earlier shape is invented.
- **Chain.** `SceneMigrator` (SceneMigration.swift, plain Swift without Foundation, Linux) runs
  `SceneMigrationStep`s (version N to N+1) on the raw document object before typed decoding. A step
  keeps every field it does not name, records each renamed, added, removed or transformed value, and
  never writes `version`; the migrator writes it after each step and returns the audit log (step,
  versions, change, JSON path). `SceneMigrator.standard`, the app's chain, is empty. Every
  `SceneDocument.decode` runs it, so autosave restore, show scenes, archives, the repair report and the
  golden render scenes all read through it; the result carries `migration`. Refusals: a newer version
  and an invalid version are unchanged; a version below the target with no step, or a failing step,
  is `migrationFailed` (SCN-012: "Cannot open", unsupported version).
- **Files.** Opening never writes. Before the first save that replaces (or, for the autosave `.bak`,
  removes) a stored file whose content was migrated, its original bytes are written once to
  `<file name>.v<N>.backup` beside it (exclusive create; an existing backup is never overwritten). If
  that fails, the save is refused (autosave step `keepOriginal`; ShowStore `writeFailed`) and the
  original stays. Show scene backups are removed with their scene; autosave backups stay. Archives
  are read-only sources and get no backup. Diagnostics events carry versions, counts and fixed file
  names only.
- **Report.** A migrated document's SCN-012 report has one note "Updated from an older format" (group
  `formatUpdated`); a note never makes the report appear.
- **Fixtures.** `Packages/SceneFormat/Tests/SceneFormatTests/Fixtures/legacy/manifest.json` lists every
  golden legacy fixture (version, source, expected current-schema document, coverage); today 11
  version-1 shapes (the 7 QA-002 scenes, all layer kinds, an unknown audio feature, the empty scene,
  a hand-written scene). Each must decode to its expected bytes with no input value lost. QA-004 runs
  this manifest.
- **Procedure for the next format version.** Raise `currentVersion`; append one step to
  `SceneMigrator.standard` that records every change; list it here; keep every existing fixture,
  regenerate its expected document through the new step and review the diff; add the new version's
  real shapes as fixtures.

## Amendment 2026-11-13 (QA-004, scene migration matrix)

QA-004 (specs/084-qa-004-scene-migration-matrix) runs every supported and just-unsupported format
version through every place a scene is stored and documents every refusal. No default is overridden;
the only production change is a defaulted `migrator` parameter on `SceneArchiveReader.read` (a test
seam like ShowStore's and the autosave store's).

- **Matrix.** `Packages/SceneFormat/Tests/SceneFormatTests/Fixtures/legacy/matrix.json` (beside
  SCN-013's `manifest.json`; schema in contracts/migration-matrix.md): 17 rows × 6 containers
  (`SceneDocument.decode`, `SceneRepairReport.open`, `ShowStore.scene`/`load`, `SceneArchiveReader.read`,
  `SceneAutosaveStore.load`, `GoldenSceneRenderer.document(from:)`). Version 1 (every historical
  fixture) is current; 0, −1, 2, Int64.max, beyond 64 bits, `1.5`, `1.0`, `1e0`, `"1"`, `null`, missing
  and a wrong format are refused; test-only chains (labelled, never registered) prove a migration with
  its audit log, a failing step and a gap. Every cell compares its outcome exactly (refusal case and
  message, migration log, canonical bytes); the golden harness's test-chain cells are not applicable
  (no chain seam), with the reason in the matrix.
- **Error table.** [contracts/scene-decode-errors.md](../../specs/084-qa-004-scene-migration-matrix/contracts/scene-decode-errors.md)
  lists every `SceneDecodeError` (report code `refusal.<case>`, when, user-facing message, SCN-012
  group, "if opened" text, covering rows or tests), the `SceneMigrationError` mapping and how each
  container surfaces a refusal. `matrix.json` `errors` is its data copy.
- **Enforcement.** `SceneMigrationMatrixMetaTests` scans the two error enums' source and keeps
  exhaustive switches over them, and fails when a case, a supported version, oldest−1, current+1, a
  production step, a historical fixture version or a container lacks its row, table entry, contract
  row or runner, or when a report text drifts from the table. Each runner carries a byte-identical
  copy of `SceneMigrationMatrixSupport.swift` (checked) and asserts it ran exactly its matrix cells.
- **Checklist: adding a scene format version N+1** (extends SCN-013's procedure above):
  1. Raise `SceneDocument.currentVersion` to N+1 and append the step `vN-to-vN+1` to
     `SceneMigrator.standard`, recording every change; list the step in this ADR.
  2. Keep every `manifest.json` fixture; regenerate each `expected/` document through the new step and
     review the diff; add the new version's real shapes under `v<N+1>/` with manifest rows.
  3. In `matrix.json`: set `currentVersion` (and `oldestSupportedVersion` if it changes); change the
     version-N row over every fixture to `migrated` with its exact log, add a version-N+1 row over every
     fixture (`current`), move the "current + 1" row to N+2 and update its message, and update the
     standard chain's `steps` and `target`.
  4. If the change adds or changes a refusal (`SceneDecodeError` case, message or report text), update
     contracts/scene-decode-errors.md and `matrix.json` `errors`, and give the case a sample in
     `SceneMigrationMatrixMetaTests`.
  5. Run the six runners (SceneFormat, ShowControl, SceneArchive, RenderGoldens packages and
     projectM-iOSTests `SceneAutosaveMigrationMatrixTests`); the meta-test names anything missed.
