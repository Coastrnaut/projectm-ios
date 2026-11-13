# Feature Specification: FILE-007 Document Schema Validator

**Feature Branch**: `feature/file-007` (spec directory `068-file-007-document-schema-validator`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (FILE-007-T01-T11 verified on the Mac host and the Linux shape; no app code changed, so no simulator or device task)

**Input**: User description: "Implement FILE-007 (Document schema validator) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Validate imported JSON against
versioned semantic constraints." Acceptance, verbatim: "Malformed nesting and oversize payload are
rejected safely." P0, effort M, depends on FILE-001 (portable scene archive)."

Identifiers in this feature carry the roadmap ID: requirements `FILE-007-R1…`, success criteria
`FILE-007-S1…`, tasks `FILE-007-T01…`. Other features are cited by their own IDs: SCN-001-R8 (the scene
document's bounded reader), PRE-014 / FILE-001 / FILE-002 (the checksummed archive and its
`manifest.json`), SHD-011 (generator-graph import), PRE-007 (collections file), PRE-012 (user presets
file), MED-009 (text overlay settings), SCN-002 (autosave, built in parallel).

## Baseline: every JSON the app reads, and how it is bounded today (audit of 2026-11-13, commit `525f5c2`)

"Untrusted" means the bytes can come from outside the app (a file the user picked, an archive from
another device). "Local" means only this app writes them, in its own container or settings.

| JSON path | Source | Max bytes | Max depth | Duplicate keys | String / number / element limits | Version handling | Generic decoder on raw bytes without a pre-check? |
|---|---|---|---|---|---|---|---|
| SCN-001 scene document (`SceneFormat`, `scene.json` in archives) | Untrusted | 1 MiB before parsing | 32, checked while reading | Refused | Own reader; counts checked before typed decoding | Newer refused, older migrated | No: own bounded reader (no generic decoder) |
| Scene archive `manifest.json` (FILE-001/002, `PortableArchive` + `SceneArchiveReader`) | Untrusted | 64 KiB (ZIP entry limit) | None | Last one wins silently | None (records checked after decoding) | Newer refused (`newerVersion`) | **Yes**: three full decodes of the manifest |
| Preset archive `manifest.json` (PRE-014, `UserPresetArchiveReader`) | Untrusted | 4 MiB | None | Last one wins silently | Preset count checked after decoding | Newer refused | **Yes**: three full decodes of up to 4 MiB |
| Generator-graph file (SHD-011, `GeneratorGraphImporter`) | Untrusted | 64 KiB before reading | 8, counted outside strings before decoding | Last one wins | Node limits after decoding (SHD-002) | Graph version validated by SHD-002 | No: size, UTF-8 and nesting pre-checked |
| Collections file (PRE-007, `PresetCollectionsFile`) | Local (future restore: FILE-005) | 16 MiB | None | Last one wins | Duplicate ids checked after decoding | Newer refused, older migrated | **Yes** |
| User presets file (PRE-012, `UserPresetsFile`) | Local (future restore: FILE-005) | 4 MiB | None | Last one wins | Counts checked after decoding | Newer refused, older migrated (migration step uses a generic parser) | **Yes** |
| Text overlay settings (MED-009, `TextOverlaySpec.decodeStored`) | Local settings; scenes carry text through SCN-001 | None | None | Last one wins | Fields clamped after decoding | Other versions refused | Yes, but app-written settings only |
| Bundled preset index, license catalog, blocklist | Signed app bundle (built at build time) | n/a | n/a | n/a | n/a | n/a | Trusted |
| Trial record, audio library, play queue | Local (app-written) | 4 KiB (trial record) / settings | n/a | n/a | n/a | n/a | App-written only |
| Debug automation reports | Debug builds only | n/a | n/a | n/a | n/a | n/a | Not in the shipping app |
| SCN-002 autosave | Local, being built in parallel | Not visible on this branch | | | | | Follow-up (see Scope) |

Gaps for this row: the two archive manifests (untrusted) reach the platform decoder with no depth,
element, string or number bound and with silent duplicate keys; the two local library files the same
(they become untrusted once a backup can be restored); limits are spread over many files and not
declared per document.

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: One shared validator, or reuse the scene document's reader everywhere? → A: One shared structural validator in `LocalPortability` (the dependency-free package that every archive and preset reader already imports) that checks shape without building values; the scene document keeps its own reader (it already enforces the same limits and builds the value tree SCN-001 needs) and the generator-graph importer keeps its pre-checks (64 KiB and depth 8 before decoding: equivalent bounds; `Compositor` would otherwise gain a dependency). No behaviour is implemented twice in one path.
- Q: Which paths get the validator? → A: Every untrusted path that reached the platform decoder without a bound (both archive manifests, through the shared archive layer) and the two local library files that a future restore makes untrusted (collections, user presets). App-written settings, bundled resources and debug-only files are out of scope and listed in the baseline.
- Q: Should the shape check run before the version check? → A: Yes. Shape first, then version: a hostile file that claims a newer version still cannot reach the decoder. Limits are generous enough (about 4-60 times the largest valid document) that a newer valid version is still recognised as newer.
- Q: Duplicate keys? → A: Refused in every validated document (compared after decoding escapes, so `"a"` and `"a"` are the same key): the platform decoder keeps one of them silently, so two `files` lists could hide an entry. The app's own writers never produce duplicates.
- Q: A UTF-8 byte order mark? → A: Refused with its own error. The app never writes one, and JSON exchanged between systems must not carry one (RFC 8259 §8.1).
- Q: How is "versioned semantic constraints" declared? → A: A small `DocumentSchema` value per document type (format name, oldest readable and current version, structural limits), declared once next to each format; readers take version and limits from it, and every reader refuses a newer version with its existing "update the app" message. Semantic checks stay in each reader after decoding (record checks, counts, ids).
- Q: A new package for the validator? → A: No. `LocalPortability` already is the shared import/export package with no dependencies and a Linux test lane, so no CI or project change is needed (recorded in the plan).
- Q: How is "rejected safely" proven? → A: Each refusal is a typed error with a byte offset; the validator counts the bytes it examines and tests assert the count stays at or below the offset of the refusal (no rescans, no recursion), plus a fixed-seed fuzz that only ever returns a typed result.
- Q: What does the person see when a manifest is refused by the validator? → A: One sentence per reason family, never raw offsets: "The archive's manifest is not valid JSON." for grammar and encoding errors, "The archive's manifest is too large or too deeply nested to read." for limit errors, and "The archive's manifest lists the same field twice." for duplicate keys; the typed reason with its offset stays available to tests and diagnostics. Applied to FILE-007-R6.
- Q: What happens to a local library file (collections, user presets) that the validator refuses? → A: The existing "unreadable" path, unchanged: the store sets the file aside and starts empty, never deleting it, exactly as for any other unreadable file today (PRE-007-R15, PRE-012-R26). Applied to FILE-007-R7.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A hostile or damaged archive manifest is refused before decoding (Priority: P1)

A performer imports a scene or preset archive whose `manifest.json` was crafted to exhaust the app:
thousands of nested brackets, a giant string, a huge list, duplicate keys hiding a second file list.
The import is refused with a clear message, quickly and without unbounded memory, and nothing changes.

**Why this priority**: The row's acceptance: "Malformed nesting and oversize payload are rejected safely."

**Independent Test**: Build archives whose manifests carry each hostile shape (with valid ZIP checksums)
and read them through the scene and preset archive readers.

**Acceptance Scenarios**:

1. **Given** a scene archive whose manifest nests deeper than its limit, **When** it is read, **Then** it
   is refused with "manifest rejected: nesting too deep" and no decoding happens.
2. **Given** a preset archive whose manifest has a list with more elements than its limit, or a string
   longer than its limit, **When** it is read, **Then** it is refused with that exact reason.
3. **Given** a manifest with the same key twice in one object, **When** it is read, **Then** it is refused.
4. **Given** a valid archive, **When** it is read, **Then** it is accepted exactly as before.

### User Story 2 - One validator with exact, typed refusals (Priority: P1)

Any reader can ask the shared validator whether bytes are acceptable JSON within declared limits and
gets either success or one typed reason with the byte offset where reading stopped.

**Why this priority**: The single place that makes every importer safe and testable.

**Independent Test**: A hostile table: each input with its exact expected error and a bound on the work done.

**Acceptance Scenarios**:

1. **Given** 100,000 nested `[`, **When** validated with depth limit 8 and any top-level value allowed, **Then** it is refused as too
   deep at the 9th bracket, having examined at most 9 bytes.
2. **Given** a 10 MB string, **When** validated with a 4 MiB byte limit, **Then** it is refused as too
   large without examining any byte.
3. **Given** malformed input (invalid UTF-8, overlong number, BOM, trailing garbage, unterminated
   string), **When** validated, **Then** each gives its own error and offset.

### User Story 3 - Local library files are bounded too (Priority: P2)

The saved collections and user presets files are checked by the same validator before their version is
read, so a damaged or crafted file (for example one restored from a backup later) is set aside as
unreadable instead of being decoded without bounds.

**Why this priority**: Prepares FILE-005 restore; today only the app writes these files.

**Independent Test**: Decode each file type with deep, duplicate-key and BOM variants; all are refused
as unreadable; existing golden files still decode.

**Acceptance Scenarios**:

1. **Given** a collections file nested 1,000 deep, **When** it is loaded, **Then** it is unreadable.
2. **Given** the existing golden files of every version, **When** they are loaded, **Then** they decode as before.

### Edge Cases

- Brackets inside strings do not count towards depth; escaped quotes do not end a string.
- A key repeated in different objects is allowed; the same key twice in one object is not, even when
  one copy uses `\u` escapes.
- An empty document, only white space, or a scalar at the top level: refused (documents are objects).
- A number with a leading zero, a lone `-`, `1.`, `1e`: refused as invalid numbers.
- Control characters inside strings, invalid escapes, lone surrogate escapes: refused.
- Overlong UTF-8 encodings, encoded surrogates and code points above U+10FFFF: refused as invalid UTF-8.
- A valid document exactly at each limit: accepted; one over: refused.

## Requirements *(mandatory)*

### Functional Requirements

- **FILE-007-R1**: A shared validator MUST check bytes, in one forward pass without recursion, against
  declared limits: total bytes (checked before any byte is read), nesting depth, string length in bytes,
  number length in bytes, elements per array or members per object, and a top-level object.
- **FILE-007-R2**: The validator MUST enforce RFC 8259 grammar over strictly valid UTF-8 and refuse,
  each with its own typed reason and the byte offset: too large, empty, byte order mark, invalid UTF-8,
  nesting too deep, string too long, number too long, too many elements, duplicate key, invalid number,
  invalid escape, control character in a string, unterminated string, unexpected character, unexpected
  end, trailing data, top level not an object.
- **FILE-007-R3**: Duplicate keys within one object MUST be refused when the limits ask for it (all
  documents in this row do), comparing keys after escapes are decoded.
- **FILE-007-R4**: The work the validator does MUST be bounded by the input size: it examines each byte
  at most once and stops at the first refusal; tests observe a counter of bytes examined.
- **FILE-007-R5**: Each document type MUST declare, in one place next to its format, a schema: name,
  oldest readable version, current version and limits. Readers take their version policy and limits
  from it; a newer version is refused with the reader's existing "made by a newer version" error.
- **FILE-007-R6**: The shared archive layer MUST validate `manifest.json` against its schema's limits
  before any decoding, refusing with a new error that carries the validator's reason and shows one of three readable sentences (Clarifications); the scene archive
  and the preset archive readers declare their manifest schemas.
- **FILE-007-R7**: The collections and user presets files MUST be validated before their version is
  read (and before any migration step); a refusal is the existing "unreadable" outcome (the store sets the file aside; nothing is deleted).
- **FILE-007-R8**: The scene document reader (SCN-001-R8) and the generator-graph importer (SHD-011)
  keep their existing equivalent bounds; tests prove both refuse deep and oversize input before decoding.
- **FILE-007-R9**: Valid documents written by the app MUST be accepted unchanged (no behaviour change for
  valid input; existing tests and golden files pass).
- **FILE-007-R10**: Plain Swift with no new dependency; builds and tests on Linux.

### Key Entities

- **JSON limits**: maximum bytes, depth, string bytes, number bytes, elements per container, duplicate-key policy.
- **Shape error**: one typed reason plus the byte offset where reading stopped.
- **Document schema**: format name, oldest readable version, current version, limits.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FILE-007-S1**: Every case in the hostile table (at least 15 cases: 100,000-deep arrays, deep objects,
  a 10 MB string, a 1,000,000-element array, invalid UTF-8, overlong number, duplicate keys, BOM,
  trailing garbage, unterminated string, and the edge cases) is refused with its exact expected error
  and offset, and the bytes examined never exceed the refusal offset plus one.
- **FILE-007-S2**: Each untrusted path (scene archive, preset archive, generator graph, scene document)
  refuses a deep and an oversize input before decoding, with its typed error; both local library files
  refuse a deep input as unreadable.
- **FILE-007-S3**: A fixed-seed fuzz of at least 2,000 mutated documents never crashes and returns only
  success or a typed error, and every accepted input is also accepted by the platform decoder.
- **FILE-007-S4**: Each unit test runs in about 1-2 s (at most 10 s) and each touched package suite in
  under 1 minute, on the Mac host and in the Linux shape.

## Assumptions

- Limits are set from the largest valid documents the app can write, with wide margins; they are listed
  in the plan and declared in code.
- The threat is a crafted or damaged file the user picked; memory and time must stay proportional to the
  bytes allowed, which are already capped per document.

## Scope

| In this row | Later rows / follow-ups |
|---|---|
| Shared validator, per-document schemas, archive manifests, collections and user presets files, tests | SCN-002 autosave adopts a schema when it lands (built in parallel; not visible on this branch) |
| | FILE-005 restore reuses the schemas for its backup manifest |
| | FILE-003 dry run reports the validator's reason in its preview |
