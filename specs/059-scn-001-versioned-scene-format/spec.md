# Feature Specification: SCN-001 Versioned Scene Format

**Feature Branch**: `feature/scn-001` (spec directory `059-scn-001-versioned-scene-format`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (SCN-001-T01-T22 verified on the Mac host and the Linux shape; no app change, no simulator or device task)

**Input**: User description: "Implement SCN-001 (Versioned scene format) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Save all layers, parameters, asset
references and mappings in one local document." Acceptance, verbatim: "Decode and re-encode preserve
semantic scene content." P0, effort L, depends on CMP-002 (ordered layer stack). Leave room for
SCN-002…SCN-015 and MOD-013 (modulation serialization) but implement only the format, its codec and
its validation."

Identifiers in this feature carry the roadmap ID: requirements `SCN-001-R1…`, success criteria
`SCN-001-S1…`, tasks `SCN-001-T01…`. Other features' IDs are cited as they are: CMP-002-R1 to R6
(ordered stack, instance IDs, 8 layers, kind limits), CMP-003 (opacity), CMP-005 (transform and its
saved form), MOD-001-R9 (parameter snapshot and restore), MOD-002-R7 (32 bindings), MOD-003 (linear
mapping), MOD-014-R9 (feedback cycles refused), SHD-009 (expressions), SHD-011 (import rules for
generator graph bytes), MED-001/MED-002 (stored photo and video identifiers), MED-009 (text spec).

## Baseline: what exists today (audit of 2026-11-13, commit `4af35a8`)

The row's gap status is "Gap candidate". The audit confirms a full gap: no scene document exists.

| Area | Today | Gap for this row |
|---|---|---|
| Layer stack | `LayerStack` (CMP-002): ordered entries, instance IDs, `LayerDescriptor` (kind + numeric parameters), `LayerCompositeSettings` (opacity, normal blend, transform). In memory only; IDs are assigned by the stack. | No saved form; a stack cannot be rebuilt with its saved instance IDs. |
| Transform | `LayerTransform` has its own versioned saved form (CMP-005, bit-exact). | Not part of any document. |
| Parameters | `ParameterSnapshot` (MOD-001, schema 1) with tagged values; `ParameterStore.restore` clamps, reports orphaned and rejected entries. | Written nowhere. |
| Modulation | `AudioFeatureBinding` (MOD-002) with `LinearMapping` (MOD-003), envelope and mix; `ModulationGraph` validation (MOD-014); expressions (SHD-009) compile from source text. | No serialized form of bindings, graph connections or expressions. |
| Assets | Photo and video stored by UUID identifier (UserDefaults `settings.photo.id`, `settings.video.id`); text overlay as versioned JSON (MED-009); generator graphs as JSON documents imported through SHD-011. | No document refers to them. |
| Layer kinds | `camera`, `spectrum.circular`, `spectrum.linear`, `photo`, `video`, `text` declared by their targets. | Procedural materials (SHD-001) and generator graphs (SHD-002) have no layer kind yet. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What does a scene file opened by an older app do when its format version is newer than the app knows? → A: It is refused whole with a readable reason ("saved by a newer version of the app"), nothing is loaded and the file is never rewritten. A read-only partial view would show a scene that is not what was saved; SCN-013 adds migration of older versions when version 2 exists.
- Q: How are content kinds the app does not know (a future layer kind, a future asset type, a future field) handled? → A: Kept verbatim, never dropped. An unknown layer kind stays in the document at its place in the order but is not shown (reported as a warning); unknown asset types and unknown fields at the document, layer, binding and asset level are carried through decode and encode unchanged. Unknown fields inside the small closed value objects (composite settings, transform, mapping, envelope) are reported and dropped, so a format addition there needs a new version.
- Q: Are media files (photos, videos) embedded in the scene or referenced? → A: Referenced by the app's own store identifier (a canonical UUID), never by a file path or URL. Small, self-describing content is embedded: the text overlay's settings and generator graph documents (each at most 64 KiB, checked with SHD-011's rules). Exporting a scene with its media is SCN-014.
- Q: What happens when a referenced photo or video is missing on this device? → A: A warning, not a failure: the scene opens, the layer keeps its place and draws its transparent fallback (CMP-001), and the report names the missing asset. A reference to an asset key the document does not define is an error (the document contradicts itself).
- Q: How are parameter values that do not match the current catalog treated? → A: As MOD-001's restore does: an ID not in the catalog is kept and flagged as orphaned (MOD-013 relies on this); a value of the wrong kind or an unknown enum case is reported as rejected (the parameter keeps its current value); an out-of-range number is reported and clamped when applied. None of these prevents opening. A malformed ID is an error.
- Q: Which app settings belong in a scene? → A: Only visual content: the layer stack and the registered parameters (spectrum bars, orientation, spacing, glow and material values are registry parameters). Never safety, accessibility, privacy, network or purchase state: Reduce flashing, the performance overlay, the preset scope, the OSC switch and port, and the library entitlement stay app settings. The app's visual choice is not stored; the layer list is the scene's visual.
- Q: What does "preserve semantic scene content" mean exactly? → A: Two documents are semantically equal when their scene ID, name, ordered layer list (instance ID, kind, layer values, composite settings, transform, content), parameter values, ordered bindings, modulation connections, assets and preserved unknown content are equal; numbers compare bit for bit (so 0.1 stays the same double and −0 differs from 0); the order of keys in an object and white space never matter. Decode → encode → decode must give a semantically equal document, and encoding a canonically encoded document must give the identical bytes.
- Q: What is the canonical encoding? → A: UTF-8 JSON without white space, object keys sorted by their UTF-8 bytes, strings escaped minimally (quote, backslash and control characters only), numbers in the shortest form that reads back to the same double (integers without a fraction), preserved unknown numbers exactly as they were written. One canonical byte sequence per document, on every host.
- Q: Which limits apply, and when? → A: At most 1 MiB, checked on the byte count before anything is parsed; nesting at most 32 levels, checked while parsing; then, before any typed decoding, at most 8 layers (CMP-002), 32 bindings (MOD-002), 1,024 parameter values, 16 assets, 64 numeric values per layer, 64 modulation generators and 256 connections. Nothing in the document is executed or loaded: identifiers are resolved later by the app's stores, expressions only compile to bytecode (SHD-009), graph documents only pass SHD-011's checks.
- Q: Are graph connections beyond audio bindings (LFOs, macros) stored? → A: The document has an optional modulation section (generators and connections by stable ID) that is validated with MOD-014 together with the bindings, so a cycle is refused with its readable path. Nothing runs it until the generator rows (MOD-007 onward); MOD-013 owns its migration rules and live wiring.
- Q: (clarify pass) What is a valid scene name? → A: 1 to 120 characters after removing leading and trailing white space, with no control characters; stored exactly as given (no trimming on write) so encode never changes it. An invalid name is an error; SCN-003 renames.
- Q: (clarify pass) Is the order of bindings part of the scene's meaning? → A: Yes. Bindings keep their order (MOD-002 evaluates them in the order first bound; MOD-012 reorders them), so a reordered list is a different scene. Parameter values, assets and layer values are maps: their key order never matters.
- Q: (clarify pass) Must the document's layer instance IDs be dense or start at 1? → A: No. Any unique IDs from 1 to 2^53 − 1 are valid, in any order; a live stack rebuilt from the document keeps them and gives the next new layer the largest saved ID plus one, so IDs are never reused (CMP-002-R2).
- Q: (clarify pass) Where does the format code live and who calls it? → A: A new package with no app dependency, so it builds and is tested on Linux; the app adopts it in SCN-002. It adds the two missing layer kinds (`material`, `generator.graph`) next to their layer targets, as CMP-002 requires of every kind.
- Q: Is saving, opening or listing scenes in the app part of this row? → A: No. This row delivers the format, its codec, its validation and adapters between the document and the live compositor stack, parameters and bindings. Files on disk, autosave, the scene list and every screen are later rows (SCN-002 to SCN-015, see the scope table).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A scene survives a save and reopen unchanged (Priority: P1) — MVP

A performer builds a scene: a camera at the bottom, a circular spectrum with a glow, a photo layer
moved and rotated at half opacity, a text overlay, a procedural material and a generator graph,
with the bass band driving the spectrum's gap. When the scene is written to its document and read
back, every layer is in the same order with the same identity, settings, values and content, every
parameter has the same value, and every mapping has the same source, target, range, envelope and mix.

**Why this priority**: It is the row's acceptance criterion; every later scene feature (autosave,
duplicate, snapshots, undo, templates, migration) stores scenes in this form.

**Independent Test**: A fixture document covering every layer kind, composite settings, transforms,
parameters, bindings with mapping and envelope, asset references and an unknown future layer kind is
decoded, encoded and decoded again: the two documents are semantically equal and the canonical bytes
are identical. A seeded property test does the same for random valid scenes.

**Acceptance Scenarios**:

1. **Given** the fixture document, **When** it is decoded and encoded, **Then** the bytes equal the fixture's canonical bytes and decoding them again gives a semantically equal document.
2. **Given** a live layer stack with parameters and bindings, **When** it is captured as a scene, encoded, decoded and turned back into a live stack, **Then** the stack (instance IDs, order, kinds, values, opacity, transform), the parameter values and the bindings equal the originals.
3. **Given** a document whose keys are in another order and that contains white space, **When** it is decoded, **Then** it is semantically equal to its canonical form.

---

### User Story 2 - A damaged, hostile or newer scene is refused or repaired with a readable report (Priority: P1)

A scene file is cut short, is not a scene at all, is enormous, was written by a newer app, or
contradicts itself (two layers with the same identity, a cycle in its mappings). The app never
crashes or half-loads it: it gets one typed refusal or a list of readable issues, each naming where
in the document it is and what is wrong.

**Why this priority**: Scene files are user content that will be imported and exchanged (SCN-014);
the constitution requires untrusted input to fail gracefully.

**Independent Test**: A validation table: each malformed document gives its exact refusal or issue
message; the valid control gives none.

**Acceptance Scenarios**:

1. **Given** bytes over 1 MiB, **When** they are decoded, **Then** they are refused on their size before parsing.
2. **Given** a document with format version 2, **When** it is decoded, **Then** it is refused as saved by a newer version.
3. **Given** two layers with the same instance ID, a binding whose target is not modulatable, or a modulation cycle, **When** it is validated, **Then** each is an error with its message and the document cannot be turned into a live scene.
4. **Given** an unknown parameter ID, an out-of-range value or a missing photo, **When** it is validated, **Then** each is a warning and the scene still opens.

---

### User Story 3 - Future versions can extend the format without losing data (Priority: P2)

A later app version adds a new layer kind, a new asset type or a new field. Today's app keeps that
content untouched when it decodes and re-encodes the document.

**Why this priority**: The format must outlive this row; SCN-013 and MOD-013 build on it.

**Independent Test**: Documents with an unknown layer kind, an unknown asset type and unknown fields
at each extensible level round-trip byte for byte.

**Acceptance Scenarios**:

1. **Given** a layer of kind `particles.v9` with arbitrary content, **When** the document is decoded and encoded, **Then** the layer and its content are unchanged and in the same place.
2. **Given** an unknown field inside a layer's transform, **When** it is decoded, **Then** a warning names it and the field is dropped.

### Edge Cases

- Empty layer list: valid (a scene with nothing to draw); an empty name is an error.
- The same photo referenced by two layers: invalid by kind limit (one photo layer per stack, MED-001).
- Numbers: very small and very large doubles, −0, integers near 2^53, and integer parameters written as `3.0` (refused: not an integer).
- Strings with quotes, backslashes, control characters, non-ASCII letters and emoji round-trip exactly; invalid UTF-8 is refused.
- Duplicate keys in one object are refused (a reader could otherwise pick either value).
- A layer instance ID of 0 or above 2^53 − 1 is an error (IDs start at 1 and must survive any JSON reader).
- A binding written twice for the same target: error (a target has one binding, MOD-002).
- A binding with an expression that does not compile: error with the expression's message.

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-001-R1**: One document MUST hold a whole scene: format name `projectm-ios.scene`, format version 1, a scene ID (canonical uppercase UUID), a name, the ordered layer list (bottom first), parameter values by registry ID, audio bindings, an optional modulation section and an asset table.
- **SCN-001-R2**: Each layer MUST carry its instance ID (1 … 2^53 − 1, unique in the document), its kind as a namespaced identifier, its own numeric values, its composite settings (opacity 0…1, blend mode, transform in CMP-005's saved form) and its kind's content: none for camera and spectra, an asset key for photo, video, text and generator graph, a material ID for procedural materials, and content kept verbatim for unknown kinds.
- **SCN-001-R3**: Parameter values MUST use MOD-001's tagged value form (kind and value; colors as four components) keyed by parameter ID.
- **SCN-001-R4**: Each binding MUST store its audio source ID, target parameter ID, input range, output range, mix mode and envelope, and MAY store an expression's source text (SHD-009).
- **SCN-001-R5**: The modulation section MUST store generators (ID, name, inputs) and connections (source node, target node, input) by stable ID.
- **SCN-001-R6**: Assets MUST be referenced by store identifier (photo, video: canonical UUID) or embedded (text overlay settings, generator graph documents). No file path, URL or absolute location may appear; anything else is refused.
- **SCN-001-R7**: Encoding MUST be canonical as defined in Clarifications; decoding then encoding a canonical document MUST reproduce its bytes exactly.
- **SCN-001-R8**: Decoding MUST refuse, with one typed reason and a readable message: more than 1 MiB (before parsing), invalid JSON or UTF-8, nesting deeper than 32, duplicate keys, a document that is not a scene, a newer or invalid format version, and counts over the limits (before typed decoding).
- **SCN-001-R9**: Validation MUST report every issue with a severity (error or warning), a stable code, the location in the document and a readable message: duplicate instance IDs, layer and kind limits, ill-formed IDs and names, invalid numbers, dangling or mistyped asset references, invalid embedded text or graph documents, orphaned, rejected and out-of-range parameter values, binding errors (MOD-002 contract C2), duplicate binding targets, expression compile errors, modulation graph issues including cycles with their path (MOD-014), unknown kinds and asset types, dropped unknown fields, missing assets and unused assets.
- **SCN-001-R10**: Unknown layer kinds, unknown asset types and unknown fields at the document, layer, binding and asset level MUST be preserved verbatim through decode and encode.
- **SCN-001-R11**: A document with any error MUST NOT be turned into a live scene; warnings MUST NOT prevent it.
- **SCN-001-R12**: Adapters MUST capture a live layer stack (with each layer's content), parameter snapshot, bindings and modulation graph as a document, and turn a valid document back into a live stack with the saved instance IDs and order, a parameter snapshot, bindings and the graph; unknown kinds are left out of the live stack and reported.
- **SCN-001-R13**: Semantic equality MUST be defined as in Clarifications and be available to callers and tests.
- **SCN-001-R14**: The format code MUST be plain Swift, read no files, use no network and execute nothing from the document, and build and pass its tests on Linux.

### Key Entities

- **Scene document**: format, version, scene ID, name, layers, parameters, bindings, modulation, assets, preserved unknown fields.
- **Scene layer**: instance ID, kind, numeric values, composite settings, typed content, preserved unknown fields.
- **Scene asset**: a photo or video store identifier, embedded text settings, an embedded generator graph document, or an unknown type kept verbatim.
- **Scene binding**: audio source, target parameter, mapping, mix, envelope, optional expression.
- **Scene issue**: severity, code, location, message.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SCN-001-S1**: The all-kinds fixture and 500 seeded random valid scenes decode → encode → decode to semantically equal documents with identical canonical bytes (0 failures).
- **SCN-001-S2**: A live stack with every layer kind, parameters and bindings round-trips through a document to an equal live state (instance IDs, order, settings, values, bindings).
- **SCN-001-S3**: Every refusal and issue in the validation table produces its exact message; no malformed input crashes or traps.
- **SCN-001-S4**: Unknown kinds, asset types and fields round-trip byte for byte.
- **SCN-001-S5**: The package's tests run in under 1 minute on the Mac and pass on the Linux shape.

## Scope: what later rows add

| Row | Builds on this format by |
|---|---|
| SCN-002 autosave | Writing canonical bytes atomically, debounced; merging unknown layers it did not create instead of dropping them. |
| SCN-003 duplicate/rename | New scene ID and name; layer IDs and asset keys stay valid (they are scene-local). |
| SCN-004/005 folders, tags | Library metadata kept outside the document (or as new optional document fields). |
| SCN-006 preview image | A preview stored beside the document, keyed by scene ID; never inside it. |
| SCN-007 transitions | New optional fields; a version bump only if a closed object changes. |
| SCN-008/009 snapshots, A/B | Additional parameter maps in MOD-001's tagged form. |
| SCN-010 undo/redo | Semantic equality and canonical bytes as the history's comparison. |
| SCN-011 templates | Bundled canonical documents instantiated with a new scene ID. |
| SCN-012 validation report UI | Shows this row's issues (codes, locations, messages) before opening. |
| SCN-013 migration | Migrations from version N to the current version, with backup; this row refuses newer versions. |
| SCN-014 dependency pack | Exports referenced photo and video files beside the document; references stay identifiers. |
| SCN-015 lock mode | A new optional field. |
| MOD-013 modulation serialization | Migration rules and live wiring of the modulation section; orphan flagging already here. |

## Assumptions

- The app's catalogs (visual parameters, material parameters) are combined into one registry when validating; tests use those catalogs.
- One photo, one video and one text layer per stack (MED-001, MED-002, MED-009 kind limits) stay in force.
- Procedural material values are the material's registry parameters (`material.<name>.<parameter>`), shared by layers of the same material; per-instance material values are a later row.
- No app screen changes in this row, so no simulator or device run is needed; evidence is package tests on the Mac host and the Linux shape.
