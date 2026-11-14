# Feature Specification: QA-004 Scene Migration Matrix

**Feature Branch**: `feature/qa-004` (spec directory `084-qa-004-scene-migration-matrix`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement QA-004 (Scene migration matrix) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Run all historical schema
fixtures against current decoder." Acceptance, verbatim: "Every supported schema migrates or fails
with documented error." P0, size M, depends on SCN-013 (integrated)."

Identifiers carry the roadmap ID: requirements `QA-004-R1…`, success criteria `QA-004-S1…`, matrix
rows `QA-004-M01…`, tasks `QA-004-T01…`. Other features are cited by their own IDs: SCN-001 (scene
document, ADR-0028), SCN-002 (scene autosave), SCN-012 (repair report), SCN-013 (scene migration),
SHOW-001 (show scenes, ADR-0033), FILE-001/002 (scene archives), QA-002 (golden render scenes).

## Baseline: what exists today (audit of 2026-11-13, commit `bc8f371`)

| Question | Finding |
|---|---|
| Which scene format versions exist? | Only version 1 (SCN-013 research D1). `SceneDocument.currentVersion = 1`; `SceneMigrator.standard` has no steps, so the oldest supported version is also 1. No historical version is invented here. |
| Which historical fixtures exist? | SCN-013's `Fixtures/legacy/manifest.json`: 11 real version-1 shapes (7 QA-002 golden scenes copied verbatim, all kinds, unknown audio feature, empty, hand-written), each with an expected current-schema document. `SceneLegacyFixtureTests` decodes them through `SceneDocument.decode` only. |
| Which stored documents hold a scene, and how are they read? | SCN-002 autosave (`SceneAutosaveStore.load`, app target; migrator seam); SHOW-001 show scenes (`ShowStore.scene(_:)` and `ShowStore.load()`, ShowControl package; migrator seam); FILE-001/002 archive entry `scene.json` (`SceneArchiveReader.read`, SceneArchive package; **no migrator seam**: always the app's chain); QA-002 golden scenes (`GoldenSceneRenderer.document(from:)`, RenderGoldens, Metal hosts only; app's chain only); SCN-012 repair report (`SceneRepairReport.open`, migrator seam). Every one calls `SceneDocument.decode`. |
| Which refusals exist? | `SceneDecodeError` has 11 cases (`empty`, `tooLarge`, `notJSON`, `nestingTooDeep`, `duplicateKey`, `notAScene`, `newerVersion`, `invalidVersion`, `tooMany`, `malformed`, `migrationFailed`), each with a user-facing `message` and an SCN-012 report entry `refusal.<case>` (group, "Cannot open", "if opened" text). `SceneMigrationError` has 5 cases mapped onto them. No single table documents them, and no test checks that a new case is documented. |
| What does the decoder do with each version value today? | 1 decodes unchanged. 0, negative, fractional (`1.5`, `1.0`, `1e0`), larger than 64-bit, string, null or missing are `invalidVersion`; 2 and any larger 64-bit integer are `newerVersion`; a wrong `format` is `notAScene`. `migrationFailed` is reachable only with a chain that has steps (none in production). |
| What is not covered? | No test crosses version values with the containers: each container's tests (SCN-013) check one synthetic v0 file and a current file, and the archive and golden paths have no version-boundary test at all. |

So the deliverable is the matrix and its enforcement: a machine-readable list of version cases ×
containers with one expected outcome each, a test per container that runs the real reader, a
documented error table, and a meta-test that fails when the code grows a version or a refusal that
the matrix or table does not list.

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative, local-first option.

- Q: Version 1 is the only supported version. What do the "migrates" cells test? → A: The production rows have one supported version (1, outcome "current, nothing migrated"). The "migrates" outcome and the "migration failed" refusal are proven by rows that name a synthetic, test-only chain (a made-up version 0 renamed to version 1, as SCN-013 did), clearly labelled in the matrix and never registered in the app. Rejected: inventing a historical version 0 (claims history that does not exist).
- Q: Which version values are "just outside" the supported range? → A: oldest−1 (0), a negative (−1), current+1 (2), the largest 64-bit integer, a number beyond 64 bits, fractions (`1.5`, `1.0`, `1e0`), a string `"1"`, `null`, a missing version, and a wrong `format` value. Each is one row. Rejected: random fuzzing here (ImportFuzz already fuzzes the reader; the matrix must be exact and readable).
- Q: How are cells that cannot run handled (the golden harness and the archive reader have no seam for a test chain)? → A: The archive reader gains an optional chain parameter that defaults to the app's chain (a test seam, like ShowStore and the autosave store); the golden harness stays fixed, and its synthetic-chain cells are "not applicable" with a written reason in the matrix. The meta-test refuses a skipped cell without a reason. Rejected: changing the golden harness (its scenes are committed current-version files; it renders, it does not import).
- Q: Where is the error table? → A: In the feature's contract `contracts/scene-decode-errors.md`, mirrored as data in `matrix.json` (`errors`), linked from ADR-0028's amendment; tests check that code, data and document agree. Rejected: a separate `docs/` page (one more copy to keep in step).
- Q: How does the meta-test learn the cases of `SceneDecodeError`, which has associated values? → A: Two ways together: a source scan of the enum's `case` lines (as other source tests here do) and a test-side exhaustive `switch` that builds one sample per case (the compiler refuses a new case until it gets a sample). Every scanned case must have a table entry, a sample and a documented report entry. Rejected: adding `CaseIterable` support to the production enum (changes the public API for a test).
- Q: Does the autosave container need the app's unit tests (simulator)? → A: Yes: `SceneAutosaveStore` lives in the app target, so its cells run in projectM-iOSTests on a dedicated simulator; every other container runs in package tests (Linux and macOS).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Every supported version opens everywhere a scene is stored (Priority: P1)

A performer's scenes live in the autosave, in a show, in exported archives and (for the team) in the
golden render scenes. Whatever container holds a supported version, the current app reads it into
the current schema, migrating it when it is older.

**Why this priority**: It is the roadmap row's acceptance: a supported schema must migrate.

**Independent Test**: For each supported-version row and each container, store the row's document in
that container and read it through the container's real reader; compare with the expected outcome.

**Acceptance Scenarios**:

1. **Given** each historical fixture of version 1, **When** it is read through each container,
   **Then** it decodes unchanged (no migration) to its expected current-schema document.
2. **Given** a test-only chain and a version-0 file of that chain's shape, **When** it is read through
   each container that accepts a chain, **Then** it migrates to version 1 with exactly the expected
   audit log.

---

### User Story 2 - Every other version fails with a documented error (Priority: P1)

A file with a version this app cannot read (newer, below the oldest, not a whole number, missing) is
refused with one specific reason, and the user sees the documented text and "Cannot open".

**Why this priority**: The other half of the acceptance: an unsupported schema fails with a
documented error, never a crash or a silent default.

**Independent Test**: For each out-of-range row and container, read the file and check the refusal's
case, its message and the repair report entry against the error table.

**Acceptance Scenarios**:

1. **Given** a row with version 2, **When** it is read through any container, **Then** it is refused
   as `newerVersion` with the documented message; the autosave sets the file aside as `.newer`.
2. **Given** rows with versions 0, −1, `1.5`, `1.0`, `1e0`, beyond 64 bits, a string, `null` or a
   missing version, **When** read, **Then** each is refused as `invalidVersion` with the documented
   message naming what was found.
3. **Given** any refusal, **When** the SCN-012 report is built, **Then** it has exactly one entry
   `refusal.<case>`, "Cannot open", in the documented group with the documented "if opened" text.

---

### User Story 3 - The matrix cannot fall behind the code (Priority: P2)

A developer adds a format version, a migration step or a refusal case. The test suite fails until
the matrix has rows and the error table has an entry for it.

**Why this priority**: Without enforcement the matrix is a snapshot that silently goes stale.

**Independent Test**: The meta-test's checks run against the current code and pass; each check is
shown to fail on a deliberately incomplete matrix or table (in-memory).

**Acceptance Scenarios**:

1. **Given** the app's chain and current version, **When** the meta-test runs, **Then** every version
   from the oldest supported to the current has a row, as do oldest−1, current+1, a non-integer and a
   missing version, and every production step has a "migrates" row.
2. **Given** the refusal cases in code, **When** the meta-test runs, **Then** each has an entry in the
   data table and the contract document, and every row's refusal names a table entry.
3. **Given** a row whose container cell is skipped, **When** the meta-test runs, **Then** the skip has
   a written reason; each container names its test file, which exists and runs that container.

### Edge Cases

- `1.0` and `1e0` equal 1 numerically but are refused: the format requires a whole number written as
  an integer (unchanged SCN-001 behaviour, now documented).
- `9223372036854775807` is a newer version; `9223372036854775808` does not fit 64 bits and is an
  invalid version.
- A synthetic chain with a gap refuses a version-1 file with `migrationFailed` (no step from 1).
- A synthetic step that fails refuses with `migrationFailed` naming the step and path.
- The show store reports a refused scene both from `scene(_:)` (unreadable) and from `load()` (the
  cue's scene listed as unreadable); the show itself still loads.
- The archive reader wraps a refusal as `sceneRefused`; the golden harness wraps it as
  `sceneInvalid` with the refusal's text.
- Refusals unrelated to versions (empty, too large, not JSON, nesting, duplicate key, too many,
  malformed) are listed in the table with the existing tests that cover them; they are not matrix
  rows.

## Requirements *(mandatory)*

### Functional Requirements

- **QA-004-R1**: A machine-readable matrix MUST list each version case (row), the chain it is read
  with (the app's or a named test-only chain), the base fixtures it applies to, and one expected
  outcome: `current` (decodes unchanged), `migrated` (source, target and exact audit log) or `refused`
  (decode error case and exact message).
- **QA-004-R2**: The matrix MUST name every container that stores a scene (decode entry point, SCN-012
  report, SHOW-001 show store, FILE-001/002 archive, SCN-002 autosave, QA-002 golden harness) with its
  reader, its test file and how it surfaces each outcome.
- **QA-004-R3**: Every row × container cell MUST be run by that container's test through the
  container's real reader, or be marked not applicable with a written reason.
- **QA-004-R4**: The production rows MUST cover every version from the oldest supported to the
  current (every historical fixture of each), oldest−1, current+1, the 64-bit limits, non-integer
  numbers, a string, null, a missing version and a wrong format.
- **QA-004-R5**: Test-only rows MUST prove a migration to current with its audit log, a failing step
  and a gap; each names its synthetic chain, labelled test-only, never registered in the app.
- **QA-004-R6**: A documented error table MUST list every `SceneDecodeError` case: its report code,
  when it happens, the user-facing message, the SCN-012 group, severity and "if opened" text, how
  each container surfaces it, and which rows or existing tests cover it. It MUST also map each
  migration error to its decode error.
- **QA-004-R7**: A meta-test MUST fail when a `SceneDecodeError` or `SceneMigrationError` case, a
  supported version, a production step or a container lacks its row, table entry or test.
- **QA-004-R8**: Tests MUST check, for every refusal cell, that the refusal's case appears in the
  table and its report entry matches the table's group, severity and text.
- **QA-004-R9**: ADR-0028 MUST link the table and carry a "how to add a version" checklist that
  includes the matrix.
- **QA-004-R10**: Production behaviour MUST NOT change, except an optional chain parameter on the
  archive reader that defaults to the app's chain.

### Key Entities

- **Matrix row**: ID, version value as written (or missing), chain, shape transform, base fixtures,
  expected outcome, not-applicable containers with reasons.
- **Container**: ID, reader entry point, test file, how outcomes surface.
- **Error table entry**: decode error case, report code, group, severity, "if opened" text, message
  form, covering rows or tests.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **QA-004-S1**: 100% of matrix cells end in their expected outcome or carry a written
  not-applicable reason; 0 cells end in an undocumented error.
- **QA-004-S2**: 100% of refusal cases in code have a table entry and a documented report text; the
  meta-test fails within one run when one is missing.
- **QA-004-S3**: Every historical fixture (11 today) is read through every container that holds
  scenes of its kind.
- **QA-004-S4**: Each new test file runs in under 10 s and each touched package suite in under
  1 minute (owner rule 7).

## Assumptions

- Version 1 stays current during this row; the next format change follows the ADR-0028 checklist.
- The golden harness's scene decoding is reachable only where Metal exists (macOS host); on Linux
  its cells run through `SceneDocument.decode`, the harness's only decoding step, and say so.
- No user-visible path changes, so there is no UI test.
