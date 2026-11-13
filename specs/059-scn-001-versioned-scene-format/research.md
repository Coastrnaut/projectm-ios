# Research: SCN-001 Versioned Scene Format

Decisions are numbered `SCN-001-D1…` and cited by the plan, contract and code.

## SCN-001-D1 — Own canonical JSON reader and writer, not `JSONEncoder`/`JSONDecoder`

- **Decision**: A small JSON value type (`SceneJSON`), a bounded byte-level parser and a canonical
  writer, all plain Swift. Numbers keep the exact text they were written with (`SceneNumber`); typed
  fields convert that text with `Double(_:)`/`Int(_:)`, and doubles are written with Swift's
  `description` (shortest text that reads back to the same bits; Swift's own algorithm, identical on
  every host).
- **Rationale**: The acceptance needs byte-identical re-encoding of canonical input and verbatim
  preservation of unknown content. `JSONSerialization`/`JSONDecoder` lose the written form of numbers
  (`1` vs `1.0`, digits beyond double precision), accept duplicate keys silently, have no depth
  limit, and their number formatting has differed between Darwin and corelibs Foundation. Owning the
  writer pins key order, escaping and number text on Darwin and Linux alike, and the parser can
  enforce depth and duplicate-key rules while reading (SHD-011 style: bytes only).
- **Alternatives**: `JSONEncoder` with `.sortedKeys` (number text and key order are Foundation's,
  not ours; no verbatim unknown numbers); `Codable` with an `AnyCodable` bag (same loss);
  property lists (not human-readable, no canonical text).

## SCN-001-D2 — Version policy: refuse newer, migrate older later

- **Decision**: `format` must be `projectm-ios.scene`; `version` must be an integer ≥ 1. Version 1 is
  read; a higher version is refused whole (`newerVersion`), never partially shown and never
  rewritten. Within version 1, new optional fields may appear only where unknown fields are
  preserved (document, layer, binding, asset); anything else needs version 2 and an SCN-013
  migration.
- **Rationale**: A partial read of a newer document would show a scene that is not what was saved,
  and an autosave (SCN-002) could then overwrite the newer content. Refusing is the conservative,
  data-safe choice; SCN-013 owns migrations.
- **Alternatives**: read-only best-effort view (risk of silent loss); ignore the version (unsafe).

## SCN-001-D3 — Preserve unknown content at four levels

- **Decision**: Unknown keys of the document, of each layer, binding and asset are kept in an
  `extra` map and written back verbatim. Unknown layer kinds and unknown asset types are kept as
  typed `unknown` cases. The closed value objects (composite, transform, points, mapping, envelope,
  generator, connection, node) are strict: an unknown key there is a warning and is dropped.
- **Rationale**: Gives forward compatibility where features will grow (new layer kinds, new layer
  options, new binding options, new asset kinds) without making every small struct a bag.

## SCN-001-D4 — Assets: identifiers or small embedded documents, never paths

- **Decision**: Photo and video assets hold the app store's identifier (canonical uppercase UUID,
  the same rule `PhotoStore`/`VideoStore` apply to `settings.photo.id`/`settings.video.id`); the
  text overlay's settings (MED-009 version-1 JSON) and generator graph documents (SHD-002) are
  embedded and validated with their own decoders (`TextOverlaySpec.decodeStored`,
  `GeneratorGraphImporter.importGraph`, i.e. SHD-011's size, type and structure rules) on the
  canonical bytes of the embedded value. Asset keys are scene-local names.
- **Rationale**: A UUID syntax rule makes a path or URL impossible to express; the app resolves
  identifiers only inside its own folders. Embedding small, self-describing content keeps the scene
  one document (the row's observable behavior) while large media stays in its store (SCN-014 packs
  it).

## SCN-001-D5 — Parameter values follow MOD-001 restore semantics

- **Decision**: Values are MOD-001's tagged form keyed by ID. Validation runs each value through a
  scratch `ParameterStore` built on the given registry: unknown IDs are orphaned (warning, kept),
  kind mismatches and unknown enum cases are rejected (warning), clamping is reported (warning).
  The live state's snapshot carries the values as written; `ParameterStore.restore` applies them.
- **Rationale**: One definition of clamping (MOD-001 contract C3.2); MOD-013 flags orphans the same
  way.

## SCN-001-D6 — Bindings and modulation validated through MOD-002 and MOD-014

- **Decision**: Each binding is bound, in order, into a scratch `AudioFeatureModulator` (MOD-002
  contract C2, its messages); a second binding for the same target is an error. The valid bindings'
  edges plus the modulation section's connections and generators are validated with
  `ModulationGraph.validate(in:)` (MOD-014: unknown nodes, inputs, duplicates, self-loops and cycles
  with readable paths). An expression's source text compiles with `CompiledExpression(source:)`
  (SHD-009 limits) and is never evaluated by validation.
- **Rationale**: No second definition of what a valid binding or graph is.

## SCN-001-D7 — Live adapters and saved instance IDs

- **Decision**: `LayerStack` gains `init(restoring:)` (CMP-002 amendment): entries in order, IDs
  kept, duplicate IDs, stack and kind limits refused with `LayerStackError`, and the next new ID is
  the largest restored ID plus one. Materials and generator graphs get layer kinds next to their
  targets (`LayerKind.material`, `LayerKind.generatorGraph`; no instance limit), so every scene kind
  maps to a `LayerKind`. Unknown kinds are left out of the live stack.
- **Rationale**: Instance IDs are the identity later rows (undo, snapshots, OSC addressing) refer
  to; rebuilding with `add` would renumber them.

## SCN-001-D8 — Limits

- **Decision**: 1 MiB (1,048,576 bytes) before parsing; depth 32 while parsing; then before typed
  decoding: 8 layers (CMP-002), 32 bindings (MOD-002-R7), 1,024 parameter values, 16 assets, 64
  values per layer, 64 generators, 256 connections. Each embedded graph document is at most 64 KiB
  (SHD-011). Scene name 1…120 characters.
- **Rationale**: A realistic scene is a few kilobytes (the all-kinds fixture is under 4 KiB); the
  limits bound parse time and memory with a wide margin and mirror the runtime limits so a document
  can never ask for more than the app can hold.

## SCN-001-D9 — Package placement

- **Decision**: New package `Packages/SceneFormat`, one library target `SceneFormat` depending on
  the `ParameterGraph` and `Compositor` products, tests in `SceneFormatTests` (also using
  `VisualGenerators` for the visual parameter catalog). No app code changes in this row.
- **Rationale**: Keeps Compositor and ParameterGraph free of persistence (Constitution VI); the
  package builds on Linux like its dependencies (Linux shape on the Mac with
  `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`).
