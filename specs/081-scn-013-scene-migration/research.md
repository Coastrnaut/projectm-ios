# Research: SCN-013 Scene Migration

## SCN-013-D1: What history exists

- Decision: version 1 is the only scene format version ever written; no "v0" fixture.
- Evidence: `git log --all -- Packages/SceneFormat` (12 commits, first `7b620b7`); `currentVersion = 1`
  in every revision; `git diff 7b620b7 01c0388 -- SceneEncoding.swift` changes only type names. App
  Store builds 1.0 and 1.1 predate SceneFormat. QA-002's 7 committed scenes are canonical version 1.
- Alternatives rejected: inventing a v0 shape (would accept files nobody wrote).

## SCN-013-D2: Migrate the raw JSON value, not the typed model

- Decision: steps transform the document object (`[String: SceneJSON]`), before typed decoding.
- Rationale: an old shape may not decode with today's typed decoder at all (removed or renamed
  required fields); the raw value keeps unknown fields and number text exactly; the steps stay pure
  and Foundation-free.
- Alternatives: per-version typed models (a model per version forever); Codable (not used by the
  format: research SCN-001-D1).

## SCN-013-D3: The migrator owns the version field

- Decision: after each step the migrator writes `version = from + 1` and logs a `version` change; a
  step never sets it. Chains are validated as contiguous at run time: a document whose version has no
  step and is below the target is refused (`migrationFailed`, reason "no step from version N").
  Version < 1 with no step stays `invalidVersion` (unchanged behaviour); a version above the target
  stays `newerVersion`.

## SCN-013-D4: Where migration runs and when files are written

- Decision: inside `SceneDocument.decode` (in memory, every reader); opening never writes; the stores
  back up the original once just before their normal save replaces it.
- Alternatives: rewrite on open (changes files without an edit); a bulk upgrade pass (writes many
  files unasked).

## SCN-013-D5: Backup naming and durability

- Decision: `<file name>.v<N>.backup` in the same folder; `open(O_WRONLY|O_CREAT|O_EXCL, 0600)`, full
  write, `F_FULLFSYNC` (fsync fallback), close. `EEXIST` counts as kept (never overwritten). Any other
  failure refuses the save that would replace the original.
- ShowStore uses Foundation `Data.write(options: .withoutOverwriting)` plus the same naming, matching
  its existing Foundation-based writes.

## SCN-013-D6: Proving "no data loss"

- Decision: flatten input and output into leaf paths (`$.layers[0].composite.opacity`); every input
  leaf must exist in the output with an equal value (numbers compared by value, so `1` equals `1.0`),
  unless the audit log lists its path as renamed (then it must exist at the new path), removed or
  transformed. Defaults the decoder adds are allowed (new leaves).
- The fixtures' expected documents are compared byte for byte with the canonical encoding.

## SCN-013-D7: Fixture layout for QA-004

- Decision: `Fixtures/legacy/manifest.json` rows `{ "file", "version", "source", "expected",
  "covers" }`; inputs at `Fixtures/legacy/v<N>/<name>.scene.json`, expected documents at
  `Fixtures/legacy/expected/<name>.scene.json`. Tests read them through `#filePath` (works on the host
  and Linux, no resource bundle). QA-004 adds a version by adding a folder, rows and the step.
- A future format change adds a step, keeps every existing fixture (their expected documents are
  regenerated only through the new step, which the review diff shows) and adds the new version's
  fixtures.

## SCN-013-D8: Report note

- Decision: new `SceneRepairReport.Group.formatUpdated` (title "Updated format", last in order), one
  note entry: item "Scene file", problem "Updated from an older format (version N to M).", if opened
  "It opens in the current format; the original file is kept when it is next saved.", code
  `migration.updated`, path `$`. A note never makes `needsReview` true.
