# Tasks: PRE-012 Preset import validation

**Input**: `specs/008-pre-012-preset-import-validation/` (spec, plan, research, data-model,
contracts, quickstart)

**Conventions**: task IDs are `PRE-012-T01…`. Tests come first within each phase and their
failing ("red") run is recorded before the code is written. Tags: `{mac}` runs on the Mac host
(`swift test`), `{sim}` needs the iOS 27.2 simulator, `{merge}` needs the full app build with the
preset submodules and is run by the main session after the merge, `{device}` needs a physical
device and belongs to the final device stage. A task is ticked only when its evidence was
produced, with " — Verified <date>: <how>".

Paths: `PKG` = `Packages/PresetLibrary/Sources/PresetLibrary`, `UP` = `PKG/UserPresets`, `PKGT` =
`Packages/PresetLibrary/Tests/PresetLibraryTests`, `ANG` = `Packages/ANGLERendering`, `APP` =
`Apps/projectM-iOS`.

## Phase 1: Setup

- [ ] PRE-012-T01 {mac} Create `PKGT/UserPresetFixtures.swift`: a builder for synthetic presets
  (`[preset00]` header, a few settings, per-frame and per-pixel equations, optional warp and
  composite shaders using `sampler_main` and `sampler_noise_lq`), written for this repository
  (no third-party preset text), plus helpers for a temporary store directory and a scripted fake
  `PresetTrialRunning`. Create the immutable golden fixture `PKGT/Golden/user-presets-v1.json`
  (`schemaVersion` 1; one playable proven preset with a warning and a license line, one pending,
  one quarantined with `engineRejected` and a detail, one quarantined with a reason code this
  version does not know; a name with an emoji and right-to-left text). Evidence: the package's
  tests build and `python3 -m json.tool` parses the fixture.

## Phase 2: Foundational (hashing, validator, model, store; blocks every story)

- [ ] PRE-012-T02 {mac} Write `PKGT/ContentHashTests.swift`: SHA-1 and SHA-256 of the empty
  input, "abc" and a 1,000,000 × "a" input equal the published test vectors; `gitBlobSHA1` of
  "hello\n" equals `ce013625030ba8dba906f756967f9e9ca394464a` (what `git hash-object` prints);
  inputs of 55, 56, 63, 64 and 65 bytes (padding boundaries) match values computed with
  `shasum`. Record the red run.
- [ ] PRE-012-T03 {mac} Implement `UP/ContentHash.swift` (pure Swift, iterative, no
  dependencies). Evidence: T02 passes.
- [ ] PRE-012-T04 {mac} Write `PKGT/MilkdropPresetValidatorTests.swift` (R7-R13, S1, S7): the
  valid fixture is accepted with no warnings; CRLF, CR-only, a UTF-8 byte-order mark and Latin-1
  bytes are accepted (Latin-1 adds the `notUTF8` warning); each of these is rejected with exactly
  this code: a NUL byte or control byte 0x01 → `binaryContent`; a line of 8,193 bytes and a line
  of 1,000,000 bytes → `lineTooLong` (8,192 accepted); 20,001 lines → `tooManyLines`; no header,
  a header after the first setting, `[preset01]` → `missingHeader`; header only → `noSettings`; a
  block of 131,073 bytes → `blockTooLarge`; a statement of 8,193 bytes in equations and in a
  shader → `statementTooLong` (8,192 accepted; comments are not counted); brackets nested 65 deep
  → `nestingTooDeep` (64 accepted), also for 100,000 nested parentheses; an equation block with
  one missing `)` → `unbalancedEquation`; a warp shader cut off before its closing brace, and a
  composite shader without `shader_body` → `incompleteShader`. Warnings: an unknown
  `sampler_mytexture` → `missingTexture("mytexture")`, while `sampler_main`, `sampler_fw_noise_lq`,
  `sampler_rand03`, `sampler_blur2` and a name in `knownTextures` (compared without prefix and
  case) give none; `per_frame_1` + `per_frame_3` → `numberingGap("per_frame_")` and the validator
  judges only line 1; a repeated key → `repeatedKeys`; a line without `=` → `ignoredLines`.
  License lines: "// License: CC-BY 4.0", "copyright 2004 Someone" and a line with © are found
  verbatim, at most 5, each at most 200 characters; `x=(c)*2` is not found. The corpus test
  walks `Vendor/presets` of the main checkout when present (path from the environment variable
  `PRE012_CORPUS` or the repository's own `Vendor/presets`), asserts no file is rejected for a
  limit (`lineTooLong`, `tooManyLines`, `blockTooLarge`, `statementTooLong`, `nestingTooDeep`,
  `binaryContent`, `missingHeader`, `noSettings`) and reports the count of other rejections;
  otherwise `XCTSkip`. Record the red run.
- [ ] PRE-012-T05 {mac} Implement `UP/PresetImportLimits.swift` (maxFileBytes 524,288;
  maxLineBytes 8,192; maxLines 20,000; maxBlockBytes 131,072; maxStatementBytes 8,192;
  maxNestingDepth 64; maxLicenseLines 5; maxLicenseLineCharacters 200; maxWarnings 50;
  maxUserPresets 1,000; maxQuarantined 200; trialTimeout 10 s; trialFrames 30; provingPeriod
  3 s), the reason, warning and license types of data-model.md in `UP/UserPresetModel.swift`, and
  `UP/MilkdropPresetValidator.swift` (contract order of checks; bytes only; iterative).
  Evidence: T04 passes; the corpus test result is recorded here.
- [ ] PRE-012-T06 {mac} Write `PKGT/UserPresetStoreTests.swift` (R4, R25-R27, S6): the golden
  version-1 fixture decodes intact and re-encodes to equal content; a record with an unknown
  reason code survives a load and a save; `schemaVersion` 2 → unavailable, file bytes unchanged,
  every change refused; garbage → set aside as `index.unreadable.json`, store empty and usable;
  duplicate ids or hashes, bad hex, `state == quarantined` without a reason → unreadable; a
  failing writer makes add, state change and removal throw `saveFailed` and leaves the index
  bytes, memory and both folders as before (the moved file is moved back); stored file names are
  `<sha256>.milk` whatever the original name ("../../evil.milk", "a/b.milk", a name with NUL,
  emoji, right-to-left text, 400 characters); display names are cleaned and cut ("1-120
  characters", `originalFileName` "at most 255 characters"); `incoming/` is emptied at load; a
  trial record is written before and removed after, an unreadable record is ignored and removed.
  Record the red run.
- [ ] PRE-012-T07 {mac} Implement `UP/UserPresetsFile.swift` (version 1, migrations map,
  validation at decode, limits "1,000 non-quarantined, 200 quarantined, 4 MiB") and
  `UP/UserPresetStore.swift` (layout of plan.md; transactions with rollback; trial record).
  Evidence: T06 passes.

## Phase 3: User Story 1 - Import a preset of my own and play it (P1)

**Independent test**: import a valid preset, see it in My Presets, play it, step, delete the
original, relaunch, play again.

- [ ] PRE-012-T08 [US1] {mac} Write `PKGT/UserPresetScopeTests.swift` (R22, R23): `PresetScope.user`
  round-trips through `storageValue` "user"; `withUserPresets` adds the presets to id lookup,
  search (group source `user`) and `members(of: .user)` alphabetically; `.all`, the home tree and
  every pack's members are unchanged; user presets are never locked, with `unlocked` false;
  favorites and a collection listing resolve a user id; replacing the user list removes old ones;
  the PRE-007 golden collections fixture still decodes (existing test stays green). Record the
  red run.
- [ ] PRE-012-T09 [US1] {mac} Implement `.user` in `PKG/PresetScope.swift` and
  `userSource`, `withUserPresets(_:)`, `.user` members and title "My Presets" in
  `PKG/PresetLibrary.swift`. Evidence: T08 and all existing PresetLibrary tests pass.
- [ ] PRE-012-T10 [US1] {mac} Write the import half of `PKGT/UserPresetLibraryTests.swift` (R2-R6,
  R14, R16, R26): a valid file with a passing fake trial → `.added`, state `playable`, the
  stored bytes equal the original, `data(for:)` returns them, the record has both hashes, size,
  date, author guess from "Author - Title.milk" and `rightsVerified == false`; the original can
  be deleted afterwards; the fake trial received exactly the stored bytes; refused with nothing
  stored: a folder, a `.txt` file, an empty file, a 524,289-byte file, a missing file, a
  duplicate of an imported preset (names it), a built-in blob hash from the context (names the
  preset and pack), a takedown hash; 1,001st preset refused. Record the red run.
- [ ] PRE-012-T11 [US1] {mac} Implement the import path of `UP/UserPresetLibrary.swift` (actor;
  `load`, `setContext`, `importFile`, `data(for:)`, `remove`, `snapshot`) and the
  `PresetTrialRunning` protocol with `PresetTrialResult`. Evidence: T10 passes.
- [ ] PRE-012-T12 [US1] {sim} Write `ANG/Tests/ANGLERenderingTests/PresetTrialRunnerTests.swift`,
  first test only: a valid synthetic preset passes the trial on the real engine within the time
  limit. Record the red run (the type does not exist).
- [ ] PRE-012-T13 [US1] {sim} Add `PresetTrialOutcome`, `PresetTrialing` and
  `VisualizerRenderer.presetTrial` (default nil) to
  `Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift`; implement
  `ANG/Sources/ANGLERendering/PresetTrialRunner.swift` (plan Design layer 3) and expose it from
  `ANGLERenderer` as `presetTrial`, registered in `presentationResources`. Evidence: T12 passes
  and the existing ANGLERendering and Rendering tests pass.
- [ ] PRE-012-T14 [US1] {sim} Write `APP/Tests/UserPresetsCoordinatorTests.swift`, import half:
  with a fake trial, importing a valid file lists it, sets the result text "Added …", and makes
  `PresetCoordinator.members` of `.user` contain it; choosing it loads the stored bytes through
  the loader; Next/Previous/Random stay inside `.user`; the purchase state is untouched
  (`unlocked` stays false and locked presets stay locked); a starred user preset is in the
  favorites listing after a new coordinator attaches (relaunch); removing a user preset (R24)
  deletes it from `.user` while the current preset stays current, and a built-in preset's files
  are untouched. Record the red run.
- [ ] PRE-012-T15 [US1] {sim} Implement `APP/Coordinators/UserPresetsCoordinator.swift`, the user
  preset hooks in `APP/Coordinators/PresetCoordinator.swift` (`setUserPresets`, loader branch
  for source `user`), the wiring in `APP/Coordinators/AppCoordinator.swift` (create the
  coordinator, load it before the library attaches, give it the renderer's trial, reset in
  `-uitestResetNotice`, `-uitestImportPreset`), and bundle `PresetBlocklist.json`
  (`project.yml`). Evidence: T14 passes.
- [ ] PRE-012-T16 [US1] {sim} Implement `APP/Views/UserPresetsView.swift` (My Presets list with
  `PresetRow`, pending section, empty state, "Import Preset…" with `fileImporter`, progress,
  result alert, remove with confirmation) and the `node:myPresets` row in
  `APP/Views/PresetBrowserView.swift`. Write `APP/UITests/UserPresetsUITests.swift`
  `testImportPlayStepAndRelaunch` (S5): import a valid preset through `-uitestImportPreset`,
  open My Presets, tap it, the current preset name is the imported one and the scope line is
  "My Presets · 1"; delete the source file, relaunch without the argument, it is still listed
  and plays. The imported row must exist within 5 s of the visualizer appearing (S5). Evidence:
  the UI test passes on the simulator.

## Phase 4: User Story 2 - A bad file is quarantined with a reason (P1)

**Independent test**: import each invalid fixture; each ends in Quarantine with its reason, none
is playable, the picture keeps drawing.

- [ ] PRE-012-T17 [US2] {mac} Extend `PKGT/UserPresetLibraryTests.swift` (R13, R15, R16, R20, R24,
  R27): a statically invalid `.milk` file → `.quarantined` with the validator's reason, its copy
  is in `quarantine/` and not in `files/`, `data(for:)` is nil, the fake trial was never called;
  fake trial `failed("x")` → `engineRejected` with the message; `timedOut` → `timedOut`;
  `unavailable` → `.waiting`, state `pending`, `data(for:)` nil, and `runPendingTrials()` with a
  passing trial makes it playable; importing quarantined content again is refused with its
  reason, and works after `remove`; removing deletes record and file; the 201st quarantined file
  is refused; every reason and refusal has a non-empty user text that contains the limit where
  there is one. Record the red run.
- [ ] PRE-012-T18 [US2] {mac} Implement quarantine, pending trials and the user texts in
  `UP/UserPresetLibrary.swift` and `UP/UserPresetModel.swift`. Evidence: T17 passes.
- [ ] PRE-012-T19 [US2] {mac} Write `PKGT/PresetMutationSweepTests.swift` (S2): seed-fixed
  SplitMix64; 600 variants of the valid fixture (byte flips, truncation at a random offset, a
  random line repeated up to 30,000 times, random bracket insertion, NUL insertion, a run of up
  to 1,000,000 identical bytes, random bytes); for each: validation returns in under 1 second;
  importing it into a temporary library with a passing fake trial ends in added, quarantined or
  refused; after a refusal the directory listing and every file's bytes equal the snapshot taken
  before; after a quarantine the set of playable ids and the bytes under `files/` are unchanged;
  at the end `data(for:)` is nil for every quarantined id. Evidence: passes twice with the same
  counts per outcome (deterministic).
- [ ] PRE-012-T20 [US2] {sim} Extend `PresetTrialRunnerTests.swift` (S3) with the real engine: a
  preset whose per-frame equations do not compile fails with a message containing "compile"; a
  preset that passes static validation at the limits (64 nested parentheses; an 8,192-byte
  operator chain in an equation and in a shader) ends passed or failed and the process survives;
  a preset with four nested maximal loops in per-frame code ends `timedOut` at a 3 s limit and
  the next call returns `unavailable`; a suspended runner returns `unavailable`; while failing
  trials run, a visible `ANGLERenderer` in a window with a valid preset keeps increasing
  `presentedFrameCount` and never receives the failing preset. Evidence: the tests pass on the
  simulator. The outcome of the at-the-limits presets is recorded here; if any crashes the
  process, the limit is lowered in spec, plan and code before this task is ticked.
- [ ] PRE-012-T21 [US2] {sim} Implement `PresetQuarantineView` (rows with name and reason,
  delete by swipe and by a button, empty state) in `APP/Views/UserPresetsView.swift`, and the
  quarantine part of `UserPresetsCoordinator`. Extend `UserPresetsCoordinatorTests.swift`: an
  import that ends quarantined sets the result text with the reason and adds nothing to any
  scope. Write `UserPresetsUITests.testInvalidFilesAreQuarantinedAndThePictureKeepsRunning`:
  with a built-in preset playing, import a binary `.milk` file and a preset with broken
  equations (two launches); the "Import Preset" alert shows the reason; Quarantine lists the file
  with its reason; the current preset name is unchanged; deleting the row removes it. Evidence:
  unit and UI tests pass on the simulator.

## Phase 5: User Story 3 - The app survives a preset that kills it (P1)

**Independent test**: leave a trial record behind, start again, find the preset quarantined and
not retried.

- [ ] PRE-012-T22 [US3] {mac} Extend `PKGT/UserPresetLibraryTests.swift` (R17-R19, S4): a fake
  trial that never returns, with the library abandoned and a second library opened on the same
  directory → the preset is `quarantined(interruptedDuringCheck)`, the record file is gone, and
  `runPendingTrials()` calls no trial for it; `beginProving` then a second library →
  `interruptedOnScreen`; `beginProving` + `endProving(proven: true)` sets `provenOnScreen` and a
  second library changes nothing; `endProving(proven: false)` removes the record without proof;
  `quarantineOnScreenFailure` quarantines, moves the file and clears a proving record; the
  record is on disk before the fake trial is entered (checked from inside the fake). Record the
  red run.
- [ ] PRE-012-T23 [US3] {mac} Implement the trial record, launch recovery and proving in
  `UP/UserPresetLibrary.swift`. Evidence: T22 passes.
- [ ] PRE-012-T24 [US3] {sim} Extend `UserPresetsCoordinatorTests.swift`: a user preset whose
  load throws on the fake loader → the previous preset stays current, the failure text is shown,
  the preset is quarantined and leaves `.user`; selecting an unproven user preset begins proving
  before the load, and after the proving period with frames presented it is proven; switching
  away earlier ends proving without proof; a quarantined last-selected preset is not the initial
  preset. Then implement the hooks in `PresetCoordinator.swift` and `UserPresetsCoordinator.swift`.
  Evidence: the tests pass (red run recorded first).

## Phase 6: User Story 4 - See what the app knows about an imported preset (P2)

- [ ] PRE-012-T25 [US4] {sim} Implement `UserPresetInfoView` in `APP/Views/UserPresetsView.swift`
  (file name, size, import date, author "from the file name", license lines "found in the file"
  or "No license information was found in the file.", "Imported by you. projectM-iOS has not
  verified any rights to this preset.", warnings in words) reachable from each My Presets row
  (context menu, swipe action and a VoiceOver action). Extend
  `UserPresetsUITests.testImportPlayStepAndRelaunch`: the fixture names an unknown texture and
  carries a license comment; the information view shows both. Evidence: the UI test passes.

## Phase 7: Polish and gates

- [ ] PRE-012-T26 {mac} Privacy (R30): add the stored-data sentence and the coverage row to
  `docs/privacy-policy.md` directly after the PRE-007 row. Evidence: `validate_docs.py` passes
  and the row cites `PRE-012-R30`.
- [ ] PRE-012-T27 {sim} Accessibility (R29): every new row has a combined label (name, author or
  reason); the import button, delete and information actions have labels; reasons wrap at the
  largest text size (no `lineLimit`). Add label helpers with unit tests in
  `UserPresetsCoordinatorTests.swift`. Evidence: tests pass; a screenshot at the largest text
  size is looked at.
- [ ] PRE-012-T28 {mac} Gates: `python3 scripts/validate_docs.py`, `check_compliance.py`,
  `test_scripts.py` pass. Evidence: their output.
- [ ] PRE-012-T29 {sim} Regression: `swift test` for PresetLibrary; `xcodebuild test` for
  `Rendering-Package` and `ANGLERendering`; in the app all unit tests, `PresetCollectionsUITests`,
  `VisualizerUITests`, `SettingsUITests` and `UserPresetsUITests`; each suite twice. Evidence:
  test counts recorded here.
- [ ] PRE-012-T32 {mac} Report (R21, Constitution X): write
  `docs/test-reports/preset-import.md` with the engine audit, the corpus measurements behind each
  limit, the results of T04 (corpus), T19 (sweep counts) and T20 (real-engine outcomes), and a
  "Limitations" section stating what is not contained in-process. Evidence: the file exists and
  `validate_docs.py` passes.
- [ ] PRE-012-T30 {merge} After the merge, with the pack submodules: the corpus test of T04 over
  all 14,604 files, the full app build, `PresetTests`, `python3 scripts/check_privacy_manifest.py` on the built app, and a check that
  the bundled `PresetBlocklist.json` is in the built app.
- [ ] PRE-012-T31 {device} Final device phase on D1-D3: import through the real Files picker; a
  renamed JPEG is quarantined; trial timing on device; VoiceOver pass over My Presets and
  Quarantine.

## Dependencies

T01 → T02-T07 → US1 (T08-T16) → US2 (T17-T21) → US3 (T22-T24) → US4 (T25) → T26-T29, T32. T12-T13
need only T05. T30 and T31 are outside this worktree.

## Parallel opportunities

One agent works here, so nothing is run in parallel. Independent by file: T02/T04/T06 (tests),
T08 (scope) and T12 (trial runner).

## MVP

US1 + US2 + US3 together are the acceptance check; US4 makes the recorded metadata visible.
