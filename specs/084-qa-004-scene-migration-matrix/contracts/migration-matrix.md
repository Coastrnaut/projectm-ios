# Contract: the scene migration matrix (QA-004-R1 to R5, R7)

File: `Packages/SceneFormat/Tests/SceneFormatTests/Fixtures/legacy/matrix.json`, beside SCN-013's
`manifest.json` (the historical fixtures). Format id `projectm-ios.scene-migration-matrix`.

## Schema

```text
{ "format": "projectm-ios.scene-migration-matrix",
  "currentVersion": 1, "oldestSupportedVersion": 1,
  "containers": [ { "id", "reader", "test", "surfaces" } ],
  "chains":     [ { "id", "testOnly", "target", "steps": [identifier] } ],
  "rows":       [ { "id", "title", "versionJSON": "<JSON text>" | null, "format"?: string,
                    "chain", "shape": "as-is" | "v0-title", "base": "all" | "<manifest file>",
                    "outcome": { "kind": "current" }
                             | { "kind": "migrated", "from", "to", "log": [line] }
                             | { "kind": "refused", "error": "<case>", "message" },
                    "notApplicable": { "<container>": "<reason>" } } ],
  "errors":          [ { "case", "code", "group", "severity", "ifOpened", "when", "coveredBy" } ],
  "migrationErrors": [ { "case", "decodeError" } ] }
```

- `versionJSON: null` removes the `version` key; otherwise its text is parsed as JSON and stored.
- `shape: "v0-title"` moves `name` to `title` (the synthetic version-0 shape of the `test-v0` chain).
- `base: "all"` runs every manifest fixture (the golden container: every committed golden scene);
  a current outcome then compares canonical bytes with each fixture's `expected` document.
- Log lines are `SceneMigrationLogEntry.description`.

## Cell rules

1. A cell is (row, container) for every container not in the row's `notApplicable`.
2. Each runner executes every cell of its container through the reader in the contract
   [scene-decode-errors.md](scene-decode-errors.md) ("How each container surfaces"), compares the
   outcome exactly, and asserts the number of cells it ran equals the matrix's count.
3. A refused cell's `error` must name an `errors` entry; its message must equal `message`.
4. Test-only chains (`testOnly: true`) are defined in each runner with exactly the listed step
   identifiers and are never registered in the app.

## Rows (2026-11-13)

| Row | Version value | Chain | Outcome | N/A |
|---|---|---|---|---|
| QA-004-M01 | `1` (every historical fixture) | standard | current | — |
| QA-004-M02 | `0` (oldest − 1) | standard | refused `invalidVersion` "found 0" | — |
| QA-004-M03 | `-1` | standard | refused `invalidVersion` "found -1" | — |
| QA-004-M04 | `2` (current + 1) | standard | refused `newerVersion` 2 | — |
| QA-004-M05 | `9223372036854775807` | standard | refused `newerVersion` | — |
| QA-004-M06 | `9223372036854775808` | standard | refused `invalidVersion` | — |
| QA-004-M07 | `1.5` | standard | refused `invalidVersion` | — |
| QA-004-M08 | `1.0` | standard | refused `invalidVersion` | — |
| QA-004-M09 | `1e0` | standard | refused `invalidVersion` | — |
| QA-004-M10 | `"1"` | standard | refused `invalidVersion` "found a string" | — |
| QA-004-M11 | `null` | standard | refused `invalidVersion` "found null" | — |
| QA-004-M12 | missing | standard | refused `invalidVersion` "found nothing" | — |
| QA-004-M13 | `1`, format `projectm-ios.preset` | standard | refused `notAScene` | — |
| QA-004-M14 | `0`, v0 shape | test-v0 (test-only) | migrated 0 → 1, 2 log lines | golden |
| QA-004-M15 | `0`, no title | test-v0 (test-only) | refused `migrationFailed` (step failed) | golden |
| QA-004-M16 | `1` | test-gap (test-only) | refused `migrationFailed` (no step) | golden |
| QA-004-M17 | `1` | test-v0 (test-only) | current (a chain never touches a current file) | golden |

Golden N/A reason: the golden harness reads with the app's chain only; its scenes are committed
current-version files.

## Meta-test (QA-004-R7)

`SceneMigrationMatrixMetaTests` fails when:

- a `SceneDecodeError` case (source scan of `SceneIssue.swift`) has no `errors` entry, no contract
  row (`refusal.<case>` in scene-decode-errors.md) or no test sample; or an entry names no case;
- a `SceneMigrationError` case has no `migrationErrors` entry;
- an entry's group, severity or "if opened" text differs from `SceneRepairReport(refusal: sample)`;
- a version in oldest…current has no standard row with a current or migrated outcome; oldest − 1 or
  current + 1 has no row; no standard row has a non-integer number or a missing version;
- a step of `SceneMigrator.standard` has no migrated row starting at its version; a manifest version
  has no row;
- a row's refusal names no `errors` entry, a not-applicable reason is empty, or a container's test
  file is missing or does not name the container;
- `currentVersion` / `oldestSupportedVersion` differ from the code.
