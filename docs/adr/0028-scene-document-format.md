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
  list of drawn blend names.
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
