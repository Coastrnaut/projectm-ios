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
