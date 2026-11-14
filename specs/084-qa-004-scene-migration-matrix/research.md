# Research: QA-004 Scene Migration Matrix

## QA-004-D1 Supported versions and what is just outside them

- **Decision**: Supported = `SceneMigrator.standard.oldestVersion ... SceneDocument.currentVersion`,
  today exactly {1}. Boundary rows: 0, −1, 2, 9223372036854775807 (Int64.max), 9223372036854775808,
  `1.5`, `1.0`, `1e0`, `"1"`, `null`, missing, and a wrong `format`.
- **Rationale**: These are the branches of `SceneMigrator.migrate` and `SceneDecoder.document`
  (read 2026-11-13): no number → `invalidVersion(typeName)`; not an integer literal or beyond Int64
  → `invalidVersion(text)`; > target → `newerVersion`; < 1 without a step → `invalidVersion(text)`;
  format ≠ `projectm-ios.scene` → `notAScene`.
- **Alternatives**: a version-0 historical shape (rejected: none was ever written, SCN-013-D1).

## QA-004-D2 Proving "migrates" and "migration failed"

- **Decision**: Three named test-only chains, defined identically in each runner:
  `test-v0` (step `test-v0-to-v1`: `$.title` → `$.name`, fails with "missing title" when absent;
  target 1) and `test-gap` (the same step, target 2: a version-1 file has no step from 1).
- **Rationale**: Covers migrated with log, `stepFailed` and `missingStep`; same shape as SCN-013's
  synthetic v0 step, so it reads as test-only.

## QA-004-D3 Containers and seams

| Container | Reader | Chain seam | Runs in |
|---|---|---|---|
| decode | `SceneDocument.decode(_:migrator:)` | yes | SceneFormat |
| repairReport | `SceneRepairReport.open(bytes:registry:migrator:)` | yes | SceneFormat |
| showStore | `ShowStore(directory:migrator:)` `.scene(_:)`, `.load()` | yes | ShowControl |
| archive | `SceneArchiveReader.read(_:registry:limits:migrator:)` | **added** (default `.standard`) | SceneArchive |
| autosave | `SceneAutosaveStore(directory:migrator:).load` | yes | projectM-iOSTests |
| golden | `GoldenSceneRenderer.document(from:)` | no (test chains n/a) | RenderGoldens |

- **Decision**: Add the archive seam (one defaulted parameter, mirrors ShowStore); keep the golden
  harness fixed and mark its test-chain cells not applicable.

## QA-004-D4 Enumerating an enum with associated values

- **Decision**: Scan `SceneIssue.swift` for `case` lines between `public enum SceneDecodeError` and
  its closing brace (and `SceneMigration.swift` for `SceneMigrationError`), and keep a test-side
  `switch` that returns a sample per case name (`default` returns nil, so a scanned name without a
  sample fails). `SceneRepairReport.refusalName` is already an exhaustive switch in production.
- **Alternatives**: `CaseIterable` on a test-only wrapper (still needs a hand list); Mirror (needs
  an instance per case).

## QA-004-D5 Where the error table lives

- **Decision**: `contracts/scene-decode-errors.md` plus `matrix.json` `errors`; the meta-test checks
  that the contract lists every `refusal.<case>` and every report "if opened" text, and that the
  data entry's group and text equal what `SceneRepairReport(refusal:)` builds.

## QA-004-D6 Linux and the golden harness

- **Decision**: On Linux `SceneRenderHarness` is compiled out; the golden runner then reads the
  committed golden scenes through `SceneDocument.decode` (the harness's only decoding step) and
  checks the same outcome. On macOS it calls the harness.

## QA-004-D7 A message quirk only test chains can show

- **Finding**: `SceneDecodeError.migrationFailed`'s message names `SceneDocument.currentVersion` as
  the target, not the chain's target. With `test-gap` (target 2) the message reads "format version 1
  cannot be updated to version 1". The production chain always targets `currentVersion`, so users
  can never see this. **Decision**: record the exact message in the matrix as it is; no production
  change (QA-004-R10).
