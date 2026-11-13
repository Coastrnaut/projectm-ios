# Implementation Plan: SHD-011 User-Authored Shader Policy

**Branch**: `feature/shd-011` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/050-shd-011-user-authored-shader-policy/spec.md`

## Summary

Three deliverables, no app code:

1. **Policy ADR** (`docs/adr/0024-user-content-code-execution-policy.md`; 0022 and 0023 are left
   to the parallel MED-002 and OUT-001 rows): the user-content inventory, the treatment of each
   type, the projectM preset-shader exception and its PRE-012 bounds, the forbidden mechanisms each
   mapped to a compliance rule, and "any feature that executes user-supplied code needs its own
   spec and owner review" (SHD-011-R1).
2. **Graph importer**: a new target `GeneratorGraphImport` in `Packages/Compositor` (it needs
   Foundation's `JSONDecoder`; the `GeneratorGraph` module stays Foundation-free, ADR-0019
   Decision 6). `GeneratorGraphImporter.importGraph(_ data: Data, fileName: String?)` checks, in
   order: file-name extension, emptiness, the 65,536-byte limit, executable magic bytes, archive
   magic (zip central-directory names for code), UTF-8, top-level object, bracket nesting ≤ 8; then
   decodes with `JSONDecoder` into `GeneratorGraphDocument`, compiles with
   `GeneratorGraphCompiler.compile` and returns `ImportedGeneratorGraph` (document, compiled plan,
   canonical bytes from `JSONEncoder` with sorted keys). Every refusal is a
   `GeneratorGraphImportError` with one message (SHD-011-R2 to R7). Plain Swift + Foundation; no
   Metal; builds on Linux.
3. **Static enforcement**: `scripts/check_compliance.py` gains five rules applied to code with
   comments and string literals removed: bundle and library loading, script engines and expression
   evaluation, process spawning, executable memory, and Metal library creation (source only in an
   allowlist of eight reviewed files; never from URL, data, file or dynamic library). Script tests
   cover each rule both ways; the repository passes (SHD-011-R8, R9).
4. **Tests**: hostile fixture table (`GraphImportFixtureTests`), limits and determinism, a source
   scan of the importer module (`GraphImportSourceSafetyTests`, SHD-011-R10).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0, Xcode 27.2 on the Mac; CI Xcode 26 → explicit closure
types), Python 3 standard library for the compliance check.
**Primary Dependencies**: Foundation (`JSONDecoder`, `JSONEncoder`, `Data`), SHD-002 `GeneratorGraph`.
**Storage**: None in this row (Clarifications).
**Testing**: XCTest in `GeneratorGraphImportTests`; `scripts/test_scripts.py` (unittest).
**Target Platform**: iOS 26+ app packages; tests on the macOS host and the Linux build shape
(`-Xswiftc -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`).
**Performance Goals**: An import of the largest allowed file is a linear scan plus one decode;
suite under 10 s (owner rule 7). No wall-clock assertions.
**Constraints**: No file, bundle, network or shader API in the importer; no C stdio globals.
**Scale/Scope**: One new target (4 source files), one test target, one script change, one ADR.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pass: Foundation only; the compliance check is strengthened, not weakened. Not amended. |
| V No universal-capture claims | Not touched. |
| VI Modular boundaries | Pass: the importer is a new target depending only on `GeneratorGraph`; no app, engine or capture import. |
| IX Untrusted input | Pass: size, type and content are validated before decoding; failure is a typed error. |
| X Evidence | Pass: unit tests for deterministic logic; ADR for a policy decision; no device claims. |
| Security (imported files) | Pass; a wording proposal to name graphs and every user content type is in research.md (not applied; the owner amends the constitution). |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/050-shd-011-user-authored-shader-policy/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/graph-import.md        # API, check order, messages, fixture table
├── contracts/compliance-rules.md    # the new static rules and the allowlist
└── checklists/requirements.md
```

### Source Code (repository root)

```text
docs/adr/0024-user-content-code-execution-policy.md   # new
docs/adr/README.md                                      # index row
Packages/Compositor/Package.swift                       # + GeneratorGraphImport, + GeneratorGraphImportTests
Packages/Compositor/Sources/GeneratorGraphImport/
├── GeneratorGraphImporter.swift        # importGraph, check order
├── GeneratorGraphImportError.swift     # typed refusals + messages
├── GraphImportLimits.swift             # limits, extension tables
└── ExecutableSignature.swift           # magic bytes, zip entry names
Packages/Compositor/Tests/GeneratorGraphImportTests/
├── GraphImportFixtureTests.swift       # hostile + valid fixture table
├── GraphImportLimitTests.swift         # size, nesting, encoding, determinism, largest graph
└── GraphImportSourceSafetyTests.swift  # module scan
scripts/check_compliance.py, scripts/test_scripts.py
```

**Structure Decision**: a separate target keeps `GeneratorGraph` free of Foundation and file
formats, so its own safety scan (`GraphSourceSafetyTests`, which forbids `import Foundation`) stays
valid.

## Complexity Tracking

None.
