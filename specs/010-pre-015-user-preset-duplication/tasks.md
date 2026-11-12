# Tasks: PRE-015 User preset duplication

**Input**: `specs/010-pre-015-user-preset-duplication/` (spec, plan, research, data-model,
contracts, quickstart)

**Conventions**: task IDs are `PRE-015-T01…`. Tests come first within each phase and their
failing ("red") run is recorded before the code is written. Tags: `{mac}` runs on the Mac host
(`swift test`), `{sim}` needs the iOS 27.2 simulator, `{device}` needs a physical device and
belongs to the roadmap's final device stage (not run here). A task is ticked only when its
evidence was produced, with " — Verified <date>: <how>". `[P]` = can run in parallel with the
neighbouring tasks (different files).

Paths: `UP` = `Packages/PresetLibrary/Sources/PresetLibrary/UserPresets`, `PKGT` =
`Packages/PresetLibrary/Tests/PresetLibraryTests`, `APP` = `Apps/projectM-iOS`.

## Phase 1: Setup

- [ ] PRE-015-T01 {mac} Create the immutable golden fixture `PKGT/Golden/user-presets-v2.json`
  (`schemaVersion` 2): one imported playable preset, one copy with `license.origin`
  `bundledDuplicate`, `duplicateOf` (presetID `cream-of-the-crop/Folder/Example.milk`, pack
  title "Cream of the Crop", `licenseStatement` ≤ 1,000 characters, `requiresLibraryUnlock`
  true) and `modifiedAt`. Evidence: `python3 -m json.tool` parses it.

## Phase 2: Foundational (record v2, migration, path guard; blocks every story)

- [ ] PRE-015-T02 {mac} Write `PKGT/UserPresetsMigrationTests.swift` (R21): the v1 golden file
  decodes through the migration with `migratedFrom == 1` and every record equal to the v1 decode
  with `duplicateOf == nil`, `modifiedAt == nil`; the migration step only changes
  `schemaVersion` (key-by-key comparison); the v2 golden decodes without migration; a v2 record
  where `origin == bundledDuplicate` but `duplicateOf` is absent (and the reverse) is unreadable;
  a store opened on the v1 file keeps `index.v1.backup.json` when the save fails and removes it
  after the first successful save; a version 3 file is `newerFormat` and its bytes stay
  unchanged. Update `PKGT/UserPresetStoreTests.swift` expectations that hard-code version 1.
  Record the red run.
- [ ] PRE-015-T03 {mac} Implement in `UP/UserPresetModel.swift`: `Origin.bundledDuplicate`,
  `PresetDuplicateOrigin` (presetID "1-300 characters", name/pack ≤ 120, `sha256` hex 64,
  `blobHash` hex 40, `licenseStatement` "≤ 1,000 characters", `requiresLibraryUnlock`),
  `UserPreset.duplicateOf` and `modifiedAt` (optional), and the well-formedness rule
  "`duplicateOf` present iff `license.origin == bundledDuplicate`". In `UP/UserPresetsFile.swift`:
  `currentVersion = 2`, migration `1 → 2`. Evidence: T02 passes, PRE-012 suites still pass.
- [ ] PRE-015-T04 {mac} Write the path-guard tests in `PKGT/UserPresetEditingTests.swift`
  (R19, S3): an internal observer records every create, write, move and delete of the store;
  across add, update into and out of quarantine, replace, remove, trial records and migration,
  every recorded path is inside the store directory; a store whose directory is a symbolic link
  still passes; an operation on a path outside (forced through the internal helper) fails with
  `saveFailed` and touches nothing. Record the red run.
- [ ] PRE-015-T05 {mac} Implement the guard in `UP/UserPresetStore.swift`: one internal function
  for every file operation (create directory, write, move, remove, copy), standardized and
  symlink-resolved containment check, `fileOperationObserver`. Evidence: T04 passes.

## Phase 3: User Story 1 - Duplicate a bundled preset (P1) 🎯 MVP

**Goal**: a bundled preset becomes a new user preset with an origin. **Independent test**:
`UserPresetDuplicationTests` and the app test below.

- [ ] PRE-015-T06 [US1] {mac} Write `PKGT/UserPresetDuplicationTests.swift` (R2-R6, R20): a
  bundled fixture in a read-only temporary "bundle" folder; duplicate → `added`, bytes in
  `files/` equal the source byte-for-byte, record has a new `user/` id, name "<name> copy",
  author, origin fields, `rightsVerified == false`; the bundled file's bytes, hash and
  modification date are unchanged; hash mismatch → `sourceMismatch`, nothing stored; blocked →
  `blocked`; unchanged copy present → `alreadyCopied(name)`; same text in Quarantine →
  `alreadyInQuarantine`; validator rejection (unbalanced shader braces) → `invalid(reason)` and
  no byte under the directory changes; trial failed → `quarantined`; no trial → `waiting`;
  library full / quarantine full; newer-format store → `libraryUnavailable`; record save failure
  → `saveFailed` and no file left. Naming: "copy", "copy 2" after the first copy is edited,
  case-insensitive collisions, 120-character limit. Record the red run.
- [ ] PRE-015-T07 [US1] {mac} Implement `UP/UserPresetEditing.swift` (outcomes, refusals and
  their words; `UserPresetName.copyName`; `BundledPresetSource`) and
  `UserPresetLibrary.duplicate(_:contents:)` in `UP/UserPresetLibrary.swift`. Evidence: T06
  passes.
- [ ] PRE-015-T08 [US1] {sim} Write `APP/Tests/UserPresetDuplicationAppTests.swift` (S1, S2,
  R2, R20): with the app's real bundle and `PresetLibrary.load(from: .main)`, for each of the 28
  Included presets: bundled bytes' git blob hash equals the index hash before; duplicate through
  `UserPresetsCoordinator.duplicate` (scripted trial); equal again after; the bundled preset
  loads into a fake renderer with its bundle `fileURL` and no `data`; a favorite and a collection
  naming the bundled id still resolve to the bundled preset; a locked pack preset (synthetic
  pack) is refused with the purchase requested and nothing stored. Record the red run.
- [ ] PRE-015-T09 [US1] {sim} Implement the app side: `RendererPresetLoader.bundledData(for:)`
  in `APP/Coordinators/AppCoordinator.swift` (read-only, shared with `load`);
  `UserPresetsCoordinator.duplicate(_:)`, `duplicateMessage`; `PresetCoordinator`
  purchase request for a locked source and refusal for one excluded this session. Evidence: T08
  passes.
- [ ] PRE-015-T10 [US1] {sim} UI: "Duplicate to My Presets" in `PresetRow`'s context menu and as
  a VoiceOver action for bundled rows (`APP/Views/PresetBrowserView.swift`, environment action);
  a "Duplicate to My Presets" button by the current preset name in
  `APP/Views/ControlsOverlay.swift` (only when the current preset is bundled); result alerts in
  `PresetBrowserView` and `APP/Views/VisualizerView.swift`. Evidence: T15's UI tests.

## Phase 4: User Story 2 - Edit my copy (P1)

**Goal**: edit and save with checks; the original never changes. **Independent test**:
`UserPresetEditingTests`, `UserPresetEditingUITests`.

- [ ] PRE-015-T11 [US2] {mac} Extend `PKGT/UserPresetEditingTests.swift` (R9-R15, S5): edit a
  playable copy → `saved`, the record's hashes and size describe the new text, the old body is
  deleted, the new body exists, `provenOnScreen == false`, `modifiedAt` set, the bundled fixture
  unchanged; unchanged text and name → `unchanged`, nothing written; name only → saved without a
  trial; each refusal (`emptyName`, `emptyText`, `tooLarge`, `blocked`, `sameAsBuiltIn`,
  `sameAsUserPreset`, `invalid`, `checkFailed`, `checkTimedOut`, `checkUnavailable`,
  `notEditable` for pending and quarantined, `libraryUnavailable`) leaves every byte under the
  directory identical and `data(for:)` returning the old text; editing back to the copy's own
  source text is allowed; a record-save failure during replace removes the new body; an
  `edit.json` left at launch is removed, the preset stays playable with its old text, and
  `takeEditNotices()` returns its name once; removal during the trial → `changedMeanwhile`;
  `editorText` decodes UTF-8 and falls back to Latin-1 with `isUTF8 == false`. Record the red run.
- [ ] PRE-015-T12 [US2] {mac} Implement `UserPresetStore.replaceContents`, the `editCheck` record
  (`UP/UserPresetStore.swift`), `UserPresetLibrary.edit`, `editorText`, `takeEditNotices`
  (`UP/UserPresetLibrary.swift`). Evidence: T11 passes.
- [ ] PRE-015-T13 [US2] {sim} Write app tests in `APP/Tests/UserPresetDuplicationAppTests.swift`
  for editing: for each Included preset, duplicate then save an edit through
  `UserPresetsCoordinator.saveEdit`; the bundled hash and bytes equal the index before and after
  (S1); the copy's stored file changed (S2); when the copy is on screen it is reloaded with the
  new text. Record the red run.
- [ ] PRE-015-T14 [US2] {sim} Implement `UserPresetsCoordinator.editorText`, `saveEdit`,
  `editNotice`, reload of the current preset (`PresetCoordinator.reloadIfCurrent`), and the
  editor sheet `APP/Views/UserPresetEditorView.swift` (name field, monospaced `TextEditor`,
  Cancel/Save, checking progress, error section announced, Latin-1 note,
  `interactiveDismissDisabled` while dirty, Discard Changes / Keep Editing). Add "Edit" to user
  rows in `APP/Views/UserPresetsView.swift` and `PresetBrowserView.swift`. Evidence: T13 passes.
- [ ] PRE-015-T15 [US2] {sim} Write `APP/UITests/UserPresetEditingUITests.swift`: duplicate an
  Included preset from the browser row → "<name> copy" listed; duplicate the current preset from
  the controls; open Edit, break the header and Save → error shown, editor stays; Cancel →
  discard prompt → Discard; Edit, change the text validly and Save → editor closes; the editor at
  the largest accessibility text size: fields and buttons exist and are hittable (S6). Evidence:
  the tests pass on the simulator.

## Phase 5: User Story 3 - Purchase boundary (P1)

**Independent test**: hold tests in the package and the app.

- [ ] PRE-015-T16 [US3] {mac} Write hold tests in `PKGT/UserPresetDuplicationTests.swift` (R7,
  R8, S4): locked source with `libraryUnlocked == false` → `locked`, nothing stored; unlocked →
  added with `requiresLibraryUnlock`; revoke → not in `playable`, in `needsUnlock`, `data(for:)`
  and `editorText(for:)` nil, `edit` → `needsUnlock`, no trial runs for a held pending copy;
  unlock → playable again; Included copies unaffected; nothing deleted. Record the red run.
- [ ] PRE-015-T17 [US3] {mac} Implement `setLibraryUnlocked`, `needsUnlock` and the hold in
  `UP/UserPresetLibrary.swift`. Evidence: T16 passes.
- [ ] PRE-015-T18 [US3] {sim} App: `UserPresetGuarding.libraryUnlockChanged`, called by
  `PresetCoordinator.setUnlocked` before the scope changes; "Needs the full library" section in
  `UserPresetsView` (tap → purchase sheet; Information; Remove). Test in
  `APP/Tests/UserPresetDuplicationAppTests.swift`: unlock, duplicate a pack preset, revoke →
  not in the library or My Presets scope, choose → purchase requested; a favorite naming the
  copy survives a relaunch while held (`PresetCoordinator.attach` keeps favorites of known user
  preset ids); restore → playable. Record the red run, then make it pass.

## Phase 6: User Story 4 - Origin information (P2)

- [ ] PRE-015-T19 [US4] {sim} `UserPresetInfoView`: for a copy, show "Duplicated from" (name and
  pack), the pack's statement verbatim, the not-verified sentence, and "Edited" when
  `modifiedAt` is set (`presetOrigin` identifier). Test: words in
  `APP/Tests/UserPresetDuplicationAppTests.swift` and an info check in T15's UI test.

## Phase 7: Polish & cross-cutting

- [ ] PRE-015-T20 Extend the PRE-012 row of `docs/privacy-policy.md` and its "What is stored on
  your device" text for R23. Evidence: `python3 scripts/validate_docs.py` OK.
- [ ] PRE-015-T21 {mac} Run `swift test --package-path Packages/PresetLibrary` twice and once
  with `PRE012_CORPUS` if the validator changed (it is not planned to). Evidence: counts.
- [ ] PRE-015-T22 {sim} Run `Rendering-Package` and `ANGLERendering` simulator tests (unchanged
  packages, regression) twice. Evidence: counts.
- [ ] PRE-015-T23 {sim} Run all app unit tests and `UserPresetsUITests`,
  `PresetCollectionsUITests`, `VisualizerUITests`, `UserPresetEditingUITests` twice. Evidence:
  counts; known environmental failure `PresetTests.testBundledIncludedScopeMatchesRelease1_0`.
- [ ] PRE-015-T24 Run `python3 scripts/check_compliance.py`, `python3 scripts/test_scripts.py`,
  `python3 scripts/validate_docs.py`. Evidence: all OK.
- [ ] PRE-015-T25 Write `docs/test-reports/preset-duplication.md` with commands, counts and what
  is not verified.
- [ ] PRE-015-T26 {device} S7 on D1: the editor opens a 524,288-byte preset in under 2 s; VoiceOver
  pass over the editor. Final device stage; not run here.

## Dependencies

T01 → T02 → T03 → T04 → T05 → (US1: T06 → T07 → T08 → T09 → T10) → (US2: T11 → T12 → T13 →
T14 → T15) → (US3: T16 → T17 → T18) → US4 T19 → Polish. US3's package work (T16-T17) depends
only on T07 and can precede US2. T26 waits for the final device stage.

## Parallel opportunities

T01 with T02 (different files). Within US1, T10 (views) can be written while T08/T09 run.
T20 and T25 (docs) can be written any time after the code is final.

## Implementation strategy

MVP: Phases 1-3 (duplicate, with the original untouched). Then editing (the acceptance), the
purchase hold, the information view, and the polish runs.
