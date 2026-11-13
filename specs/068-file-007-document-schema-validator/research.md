# Research: FILE-007 Document Schema Validator

## FILE-007-D1: Where the validator lives

- **Decision**: `LocalPortability` (new files `BoundedJSON.swift`, `DocumentSchema.swift`).
- **Rationale**: it has no dependencies, is already imported by both archive readers (SceneArchive,
  PresetLibrary), runs in the Linux CI lane and is described as the home of local import/export.
  A new package would have to be added to five CI loops and the project for no extra reuse today.
- **Alternatives**: a new `Packages/BoundedJSON` (rejected: churn, no extra consumer); reusing
  SceneFormat's `SceneJSONParser` (rejected: it builds a value tree and SceneFormat depends on
  Compositor, too heavy for LocalPortability's consumers).

## FILE-007-D2: Validate only, do not build values

- **Decision**: a structural validator that returns a summary (deepest nesting, values, bytes examined)
  and lets the existing `Codable` types decode afterwards.
- **Rationale**: the documents already have tested `Codable` models; replacing the decoder would be a
  rewrite. Once the shape is bounded (depth ≤ 8, elements ≤ a few thousand, strings ≤ 16 KiB, bytes
  capped) the platform decoder's cost is bounded too. Cost: one extra linear pass.
- **Alternatives**: a full bounded parser feeding a custom `Decoder` (rejected: large, duplicates
  SCN-001's reader).

## FILE-007-D3: Algorithm

- One forward pass, explicit stack of frames (`array` / `object` with expected-token state and element
  count), so depth is never recursion. Strings are scanned in place with strict UTF-8 (RFC 3629: no
  overlongs, no encoded surrogates, ≤ U+10FFFF), escapes checked (`\uXXXX` surrogate pairs must pair),
  control characters refused. Keys are decoded to bytes only when duplicate keys are refused, and kept
  in a per-object `Set<[UInt8]>` popped with the frame.
- Each byte index advances monotonically; the counter `bytesExamined` is the furthest index read, so
  "work ≤ offset + 1" is checkable. Total-size limit is checked before the first byte.

## FILE-007-D4: Shape before version

- **Decision**: shape check first, then the format/version check (spec Clarifications).
- **Rationale**: version reading itself decodes; a crafted newer-version file must not reach it.

## FILE-007-D5: Limits per document

| Document | Max bytes | Depth | String bytes | Number bytes | Elements per container | Duplicate keys | Versions |
|---|---|---|---|---|---|---|---|
| Scene archive manifest | 65,536 (archive limits) | 8 | 4,096 | 32 | 256 | refused | 1…1 |
| Preset archive manifest | 4 MiB | 8 | 16,384 | 32 | 4,096 | refused | 1…1 |
| User presets file | 4 MiB | 8 | 16,384 | 32 | 4,096 | refused | 0…2 (0 = no field, migration) |
| Collections file | 16 MiB | 8 | 16,384 | 32 | 16,384 | refused | 0…1 |

Largest valid shapes: scene manifest depth 3, ≤ 3 files; preset manifest depth 5 (preset → license
lines), ≤ 1,000 presets, license lines ≤ 200 characters (≤ 1,200 escaped bytes); user presets file
≤ 1,200 presets; collections ≤ 100 collections × ≤ 1,000 ids. Numbers are sizes and versions (≤ 20
digits). Margins are 2-60×.

## FILE-007-D6: Paths left with their own equivalent bounds

- SCN-001 `SceneJSONParser`: 1 MiB, depth 32, duplicate keys refused, UTF-8 — equal or stricter.
- SHD-011 `GeneratorGraphImporter`: 64 KiB before reading, UTF-8, depth 8 outside strings before
  decoding; with 64 KiB, element and string sizes are bounded by the byte cap. Duplicate keys are
  accepted there (graph documents are re-encoded canonically and validated by SHD-002); recorded, not
  changed in this row, to avoid a Compositor → LocalPortability dependency.
- App-written settings (MED-009 text spec, audio library, play queue), trial records, bundled
  resources and debug files: not imported (spec baseline).
