# Research: FILE-004 Import Conflict Resolver

## FILE-004-D1: Choice model

- **Decision**: Three choices (Skip, Keep both = Rename, Replace); a plan-wide default plus overrides keyed by incoming identifier. The plan stores both as given and records each entry's effective choice.
- **Rationale**: "Apply to all" and per-row choice are one model; storing inputs keeps re-validation a plain `==` (FILE-003-R8).
- **Alternatives**: Per-row choices only (tedious for many conflicts); policy only (the row asks for a choice per duplicate).

## FILE-004-D2: Deterministic identifiers

- **Decision**: Presets keep FILE-003-D3 (`user/` + 32 hex of SHA-256("FILE-003|id|text sha256|n")). Scenes: SHA-256("FILE-004|scene|id|canonical scene sha256|n"), first 16 bytes as a UUID with version nibble 8 and variant `10`, uppercase; cues: SHA-256("FILE-004|cue|final scene id|n") the same way. Smallest n ≥ 1 not taken by the library or earlier planned items.
- **Rationale**: Content-based seeds make a re-export (new date, new archive bytes) idempotent, while different content gives different IDs; keeping D3 keeps FILE-003's fixtures and contract.
- **Alternatives**: Archive SHA-256 in the seed (a re-export would mint a second copy); random UUIDs (not deterministic).

## FILE-004-D3: Preset Replace, atomicity

- **Decision**: Replace keeps the target's identifier and its position in the index; the new text is staged and moved into `files/` under its own content hash (old and new never share a file); `staging/replaced.json` lists the old texts; the index write is the commit; the old texts are deleted after it, then `staging/`. Before the commit no old byte is touched, so rollback only removes what was added. `removeLeftoverStaging()` at load deletes listed texts that no record names, then `staging/`.
- **Rationale**: The index is the only place that says which text a preset has, so it is the natural single commit point; content addressing means the replacement never overwrites a file.
- **Alternatives**: Moving old texts into a backup folder before the commit (a crash then needs the backup restored; more steps to fault); overwriting the file in place (not atomic).

## FILE-004-D4: Scene install, atomicity

- **Decision**: In the show folder: stage each final scene in `ImportStaging/` (written whole, read back and hashed); write `scene-import.journal.json` (phase `prepared`, added and replaced IDs, which folders existed); move each replaced scene file into `ImportStaging/replaced/`; move the staged files into `Scenes/`; atomically replace the journal with phase `committed` plus the new show bytes (the commit); write `show.json`; remove `ImportStaging/` and the journal. Any failure before the commit restores the moved files and removes everything added; `recoverInterruptedSceneImport()` does the same for a `prepared` journal and rolls a `committed` one forward.
- **Rationale**: Several scene files and the show cannot be renamed together; a journal gives one atomic decision point and makes a crash recoverable.
- **Alternatives**: Show file as commit point (a Replace-only install leaves the show unchanged, so it cannot mark the commit).

## FILE-004-D5: References

- **Decision**: Replace keeps the identifier, so collections (presets) and cues (scenes) stay valid; the scene preview reports how many cues use the replaced scene. Rename adds an item under a new identifier, rewrites the scene document's `id` (SCN-003 `duplicated`) and the new cue's scene ID; nothing else refers to an incoming item. Scene-internal IDs (layers, assets, bindings) are document-scoped and kept.
- **Rationale**: No reference can dangle, so no warning beyond the cue count is needed.

## FILE-004-D6: Replace fallbacks and refusals

- **Decision**: Replace applies only to a target stored before the import and not already replaced in the same plan; otherwise the entry is installed as Keep both and `fellBack` is set. A held preset target refuses the install ("Nothing was installed. …") with nothing written.
- **Rationale**: Replacing another incoming item would mean merging inside one archive; a held preset has a leftover record that would quarantine the new text at the next launch.

## FILE-004-D7: Trial during Replace

- **Decision**: `runTrial` keeps the tried text's SHA-256 and discards the result if the preset's text changed during the trial.
- **Rationale**: Without it, a trial of the old text could mark the replacement playable.

## FILE-004-D8: UI

- **Decision**: Per-row buttons in a separate `PresetArchiveChoiceRow` view (three buttons stacked vertically, checkmark plus `.isSelected`), identifiers `archiveChoice:<incoming name>:<choice>`; the "Apply to all" picker gets the Replace option and clears overrides. No animation.
- **Rationale**: Buttons are reachable and readable at accessibility sizes and easy to drive in XCUITest; a separate view keeps bodies small for CI's Xcode 26.
