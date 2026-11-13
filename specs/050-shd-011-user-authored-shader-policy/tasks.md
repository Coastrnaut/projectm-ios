# Tasks: SHD-011 User-Authored Shader Policy

**Input**: Design documents from `specs/050-shd-011-user-authored-shader-policy/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

Tests are part of this row (its verification is "parser/unit + static checks"). Task IDs carry the
roadmap ID (`SHD-011-T01…`). No `{device}` task: no import UI in this row (Clarifications).

## Phase 1: Setup

- [ ] SHD-011-T01 Add target `GeneratorGraphImport` (dependency `GeneratorGraph`) and test target `GeneratorGraphImportTests` (dependencies `GeneratorGraphImport`, `GeneratorGraph`) to the library product in `Packages/Compositor/Package.swift`, with a header comment line

## Phase 2: Foundational

- [ ] SHD-011-T02 [P] `GraphImportLimits`: `maximumBytes = 65_536` (inclusive), `maximumNesting = 8`, `acceptedExtensions = ["json"]`, `executableExtensions` exactly as data-model.md, in `Packages/Compositor/Sources/GeneratorGraphImport/GraphImportLimits.swift`
- [ ] SHD-011-T03 [P] `GeneratorGraphImportError` and `ExecutableKind` with the exact messages of data-model.md, in `Packages/Compositor/Sources/GeneratorGraphImport/GeneratorGraphImportError.swift`

## Phase 3: User Story 1 - An imported graph file is only ever data (P1) MVP

**Goal**: bytes → accepted graph or one typed refusal. **Independent test**: the fixture table of contracts/graph-import.md.

- [ ] SHD-011-T04 [US1] `ExecutableSignature`: classify first bytes (Mach-O four magics, universal four magics, ELF, `MZ`, `#!`, `!<arch>\n`, `MTLB`, `\0asm`) and archives (zip three signatures, gzip, xar); `firstCodeEntry(inZip:)` walks `PK\x01\x02` records within the bytes (name length at +28, name at +46, bounds-checked) and returns the first name whose path component ends in a code extension, in `Packages/Compositor/Sources/GeneratorGraphImport/ExecutableSignature.swift`
- [ ] SHD-011-T05 [US1] `GeneratorGraphImporter.importGraph(_:fileName:)` with the data-model check order (extension → empty → size → executable → archive → UTF-8 → object → nesting → decode → compile), `malformed` reasons as fixed strings per `DecodingError` case, and `ImportedGeneratorGraph` (`document`, `compiled`, `canonicalData` from `JSONEncoder` `.sortedKeys`), in `Packages/Compositor/Sources/GeneratorGraphImport/GeneratorGraphImporter.swift`
- [ ] SHD-011-T06 [P] [US1] Fixture table test: every row of contracts/graph-import.md with its exact outcome and message, in `Packages/Compositor/Tests/GeneratorGraphImportTests/GraphImportFixtureTests.swift`
- [ ] SHD-011-T07 [P] [US1] Limit tests: 65,536 accepted / 65,537 refused; oversized Mach-O refused as too large; nesting 8 accepted inside strings-safe scan, 9 refused; brackets inside strings ignored; BOM accepted; determinism (same bytes twice → equal results and canonical bytes); each SHD-002 example round-trips, in `Packages/Compositor/Tests/GeneratorGraphImportTests/GraphImportLimitTests.swift`
- [ ] SHD-011-T08 [US1] Largest valid graph (64 nodes, 32-character IDs, 64-character name, every value set) encodes below `maximumBytes`; record the measured size in research SHD-011-D2, in `GraphImportLimitTests.swift`
- [ ] SHD-011-T09 [US1] Source scan of the importer module: no `dlopen`, `dlsym`, `Bundle`, `FileManager`, `contentsOf`, `URL(`, `URLSession`, `makeLibrary`, `Metal`, `Process`, `NSExpression`, `JSContext`, `import Network`; the only Foundation use is `Data`, `JSONDecoder`, `JSONEncoder`, `DecodingError`, in `Packages/Compositor/Tests/GeneratorGraphImportTests/GraphImportSourceSafetyTests.swift`

## Phase 4: User Story 2 - The rule is enforced on the app's own code (P1)

**Goal**: static rules of contracts/compliance-rules.md. **Independent test**: script tests both ways; repository passes.

- [ ] SHD-011-T10 [US2] Add `strip_strings`, the five SHD-011 rules and `METAL_SOURCE_ALLOWED` (eight files of research SHD-011-D4) to `scripts/check_compliance.py`; update its docstring
- [ ] SHD-011-T11 [US2] Script tests `ComplianceCodeExecutionTests`: one violating and one allowed example per rule (including `.system(` and `func system(` allowed, literal `NSPredicate(format:` allowed, forbidden words inside string literals allowed, `makeLibrary(source:` allowed only in an allowlisted path), the allowlist files exist, and the repository passes, in `scripts/test_scripts.py`; extend `scripts/fixtures/Violations.swift.txt` with one SHD-011 line per rule

## Phase 5: User Story 3 - The policy is written down (P2)

- [ ] SHD-011-T12 [US3] ADR-0024 user-content code-execution policy (inventory, treatment, preset-shader exception and PRE-012 bounds, forbidden mechanisms → rules, review requirement, constitution proposal) in `docs/adr/0024-user-content-code-execution-policy.md`; index row in `docs/adr/README.md`; ADR-0019 Decision 6 gets a "Done by SHD-011" note

## Phase 6: Polish

- [ ] SHD-011-T13 Run quickstart.md: compliance, script tests, docs, importer tests on the host and in the Linux shape, `GeneratorGraphTests` unchanged; record counts and durations here and set the spec status

## Dependencies

T01 → T02, T03 → T04 → T05 → T06-T09. T10 → T11 (independent of US1). T12 after T10 (names the rules). T13 last.

## Parallel examples

- T02 and T03 (different files); T06, T07, T09 (different test files); US2 (T10-T11) alongside US1.

## Implementation strategy

MVP = US1 (importer + fixtures). Then US2 (static rules), US3 (ADR), polish.
