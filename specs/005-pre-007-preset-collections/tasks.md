# Tasks: PRE-007 Preset collections

**Input**: `specs/005-pre-007-preset-collections/` (spec, plan, research, data-model, contracts,
quickstart)

**Conventions**: task IDs are `PRE-007-T01…`. Tests come first within each story. Tags: `{mac}`
runs on the Mac host (`swift test`), `{sim}` needs an iOS simulator, `{merge}` needs the full app
build with the preset submodules and is run by the main session after the merge, `{device}` needs
a physical device and belongs to the final device stage. A task is ticked only when its evidence
was produced, with " — Verified <date>: <how>".

Paths: `PKG` = `Packages/PresetLibrary/Sources/PresetLibrary`, `PKGT` =
`Packages/PresetLibrary/Tests/PresetLibraryTests`, `APP` = `Apps/projectM-iOS`.

## Phase 1: Setup

- [X] PRE-007-T01 {mac} Add test resources to `Packages/PresetLibrary/Package.swift`
  (`resources: [.copy("Golden")]` on the test target) and create the immutable golden fixture
  `PKGT/Golden/collections-v1.json`: `schemaVersion` 1; three collections in a non-alphabetical
  order, one empty, one with a name containing an emoji and a diacritic, one holding an id that
  exists in `Fixtures.records`, a locked pack id and an id that is in no index. Evidence:
  `swift build --build-tests --package-path Packages/PresetLibrary` succeeds and the file parses
  with `python3 -m json.tool`. — Verified 2026-11-12: `swift build --build-tests` succeeded and `python3 -m json.tool` parsed the fixture; `testTheGoldenVersion1FixtureDecodesIntact` reads it through `Bundle.module`.

## Phase 2: Foundational (model, file, store; blocks every story)

- [X] PRE-007-T02 {mac} Write `PKGT/PresetCollectionTests.swift` (R9, R10, R6, R14): name
  normalization (trim, line breaks → spaces, "1-60 user-perceived characters", an emoji counts
  once, exactly 60 accepted, 61 refused with `nameTooLong(limit: 60)`, white space only →
  `emptyName`); comparison key ignores case and diacritics; `moved(_:fromOffsets:toOffset:)` for
  single and multiple offsets, moves to the start, the end and no-op positions;
  `applying(visibleOrder:to:)` keeps hidden ids in their slots, accepts a full permutation,
  refuses a foreign id, a duplicate and (when nothing is hidden) is the identity for the same
  order; every `PresetCollectionError` has a non-empty `message`. Evidence: the tests do not
  compile before T03. — Verified 2026-11-12: written before the sources existed; `swift build --build-tests` failed with "cannot find type 'PresetCollectionStore'/'PresetCollectionsFile'/'PresetCollectionError' in scope" (one red run for T02, T04, T06 and T08 together).
- [X] PRE-007-T03 {mac} Implement `PKG/PresetCollection.swift`: `PresetCollection` (JSON key
  `presets`), `PresetCollectionLimits` (60 / 100 / 1,000 / 16 MB), `PresetCollectionError` with
  `message`, `PresetCollectionName`, `PresetCollectionOrder`, per plan "Model and rules".
  Evidence: T02 tests pass. — Verified 2026-11-12: `swift test --package-path Packages/PresetLibrary` on the Mac Studio host: 71 tests, 0 failures (PresetCollectionTests 12).
- [X] PRE-007-T04 {mac} Write `PKGT/PresetCollectionsFileTests.swift` (R15, S6): the golden v1
  fixture decodes with every name, order and entry intact; `encode()` of the decoded fixture is
  semantically equal to the fixture (compared as JSON objects) and has `schemaVersion` 1; version
  2 → `ReadError.newerVersion(2)`; not JSON, a JSON array, a missing key, an empty or duplicate
  collection id, version 0 with no step, and data over 16 MB → `ReadError.unreadable`; duplicate
  preset ids in one collection are reduced to the first; unknown keys are ignored; an injected
  version-0 step (a bare array of collections) migrates and reports `migratedFrom == 0`; a step
  that throws → `unreadable`. Evidence: the tests do not compile before T05. — Verified 2026-11-12: written before the sources existed; `swift build --build-tests` failed with "cannot find type 'PresetCollectionStore'/'PresetCollectionsFile'/'PresetCollectionError' in scope" (one red run for T02, T04, T06 and T08 together).
- [X] PRE-007-T05 {mac} Implement `PKG/PresetCollectionsFile.swift` per plan "File and migration".
  Evidence: T04 tests pass. — Verified 2026-11-12: `swift test --package-path Packages/PresetLibrary` on the Mac Studio host: 71 tests, 0 failures (PresetCollectionsFileTests 10).
- [X] PRE-007-T06 {mac} Write `PKGT/PresetCollectionStoreTests.swift` against a fresh temporary
  directory per test, with injected ids (R1-R8, R10, R14, R15; S1, S2, S5, S6, S7, S9):
  - create (appended last, empty), rename (id, contents, position unchanged; own name accepted;
    case/diacritic duplicate refused), delete (others byte-for-byte equal), unknown id refused;
  - add (appended; second add returns false and writes nothing), remove (set of ids; order of the
    rest kept), the same preset in two collections, deleting one leaves the other;
  - `reorderPresets` and `reorderCollections`, each followed by a new store over the same
    directory showing the same order (S1);
  - limits: the 101st collection and the 1,001st preset are refused, data unchanged;
  - a failing injected writer: the call throws `saveFailed`, `collections` is unchanged and the
    file's bytes are unchanged (S5); a real failure (the directory replaced by a file) behaves the
    same;
  - load: no directory, empty directory, golden v1 copied in, a newer-version file (availability
    `newerFormat(2)`, list empty, every mutation throws `newerFormat`, bytes unchanged, S6), an
    unreadable file (renamed to `collections.unreadable.json` with the same bytes, `loadNotice`
    set, store usable; a second unreadable file replaces the first set-aside copy);
  - migration with an injected step: the migrated document is saved as version 1, the backup file
    is gone afterwards; when the save fails, the original file is untouched and the store holds
    the migrated list;
  - ids absent from any index survive add, remove of another id, reorder and rename (S7);
  - the largest collection (1,000 ids): reorder and save in under 0.5 s (S9, host figure).
  Evidence: the tests do not compile before T07. — Verified 2026-11-12: written before the sources existed; `swift build --build-tests` failed with "cannot find type 'PresetCollectionStore'/'PresetCollectionsFile'/'PresetCollectionError' in scope" (one red run for T02, T04, T06 and T08 together).
- [X] PRE-007-T07 {mac} Implement `PKG/PresetCollectionStore.swift` per plan "Store" and the
  contract. Evidence: T06 tests pass; `swift test --package-path Packages/PresetLibrary` is green. — Verified 2026-11-12: `swift test --package-path Packages/PresetLibrary` on the Mac Studio host: 71 tests, 0 failures (PresetCollectionStoreTests 23).

## Phase 3: User Story 3 foundation - a collection as a scope (P2 in the spec, built before the UI stories because they call it)

- [X] PRE-007-T08 [US3] {mac} Write `PKGT/PresetCollectionScopeTests.swift` (R11-R14; S3, S4):
  storage round trip of `.collection(id)` (`collection:<id>`; an empty id is refused); members
  follow the stored order, not the alphabet; missing ids skipped; a locked preset is absent while
  locked and present when unlocked, in its position; a session-excluded preset is absent; an
  unknown collection id gives no members; `collectionListing` keeps locked presets and order;
  `title(of:collectionNames:)`; a full Next cycle visits each member once in order and Previous
  reverses it; 1,000 Random picks with the library locked never return a locked preset and never
  repeat the current one; existing scopes return what they returned before (default parameter).
  Evidence: the tests do not compile before T09. — Verified 2026-11-12: written before the sources existed; `swift build --build-tests` failed with "cannot find type 'PresetCollectionStore'/'PresetCollectionsFile'/'PresetCollectionError' in scope" (one red run for T02, T04, T06 and T08 together).
- [X] PRE-007-T09 [US3] {mac} Add `case collection(String)` to `PKG/PresetScope.swift` and the
  collection handling to `PKG/PresetLibrary.swift` (`members`, `collectionListing`, `title`,
  `resolves`) per plan "Scope". Evidence: T08 passes; the existing `PresetScopeTests`,
  `PresetLibraryTests` and `PresetSearchTests` pass unchanged. — Verified 2026-11-12: `swift test --package-path Packages/PresetLibrary` on the Mac Studio host: 71 tests, 0 failures (PresetCollectionScopeTests 12; the 14 earlier tests unchanged and passing).

## Phase 4: User Stories 1, 2, 3, 4 - coordinator (P1)

- [X] PRE-007-T10 [US1] {sim} Write `APP/Tests/PresetCollectionsCoordinatorTests.swift` with the
  synthetic library and fake loader pattern of `PresetTests.swift`, a temporary store directory
  and a failing-writer variant:
  - US1: create, rename, delete, add, add twice ("already in"), remove; deleting a collection
    keeps favorites, the library and the other collection (S2); refused names set
    `collectionsMessage` and change nothing;
  - US2: `moveCollections` and `movePresets` (offsets as the list control gives them) and
    `movePreset(…, by: ±1)`; a new coordinator over the same directory shows the same order (S1);
    a failed save sets the message and leaves the shown order as saved (S5);
  - US3: choosing in a collection sets the scope, persists `collection:<id>` in settings, the
    scope line is "<name> · <playable count>", Next/Previous follow the manual order and wrap,
    Random stays inside; reorder and remove take effect at once; deleting the scope's collection
    keeps `current` and falls back to Included (locked) or All (unlocked); a stored scope for a
    collection that does not exist falls back on `attach`; the scope announcement names the
    collection;
  - US4: locked entry listed and `isLocked`, choosing it sets `purchaseRequested` and loads
    nothing, never reached by Next/Previous/Random; after `setUnlocked(true)` it plays; purchase
    state fields are otherwise untouched;
  - an entry missing from the library is not listed, not counted, and still in the file after a
    reorder (S7); with a newer-format file `collectionsAvailability` is `newerFormat`,
    `collectionsUnavailableText` is the clarified sentence and every action reports the reason;
    after an unreadable file was set aside `collectionsNotice` holds the clarified sentence until
    dismissed (R15);
  - edge cases: a collection whose every entry is locked or missing, as the scope: Next, Previous
    and Random load nothing and do not request a purchase; after a refund (`setUnlocked(false)`)
    a collection scope falls back to Included like every other scope (FR-109) and the collection
    is unchanged.
  Evidence: the tests do not compile before T11. — Verified 2026-11-12: the test file was written before the coordinator code (red run not recorded: the app build takes minutes, so the first run was made with T11 in place); 18 tests.
- [X] PRE-007-T11 [US1] {sim} Extend `APP/Coordinators/PresetCoordinator.swift` (store in the
  initializer, collections API, `collectionsMessage`, titles, `resolveScope`, `displayCount`
  switch) and create the store in `APP/Coordinators/AppCoordinator.swift` (plus removing the
  folder under `-uitestResetNotice`); update the coordinator construction in
  `APP/Tests/PresetTests.swift`. Evidence: `PresetCollectionsCoordinatorTests` and `PresetTests`
  pass on the iOS 27.2 simulator (except the known environmental
  `testBundledIncludedScopeMatchesRelease1_0` in a worktree). — Verified 2026-11-12: `xcodebuild test … -only-testing:projectM-iOSTests/PresetCollectionsCoordinatorTests -only-testing:projectM-iOSTests/PresetTests` on the iOS 27.2 simulator (iPhone 18 Pro): PresetCollectionsCoordinatorTests 18 of 18; PresetTests 18 of 19, the one failure being the known environmental `testBundledIncludedScopeMatchesRelease1_0` (28 presets in a worktree, expects more than 12,000).

## Phase 5: User Stories 1-4 - screens (P1)

- [X] PRE-007-T12 [US1] {sim} Create `APP/Views/CollectionSheets.swift`: `CollectionNameSheet`
  (field `collectionName`, live message `collectionNameError`, `saveCollectionName` disabled
  until valid) and `AddToCollectionSheet` (rows `addTo:<name>` with a checkmark when present,
  `newCollection`). Evidence: the app builds; used by T13-T15. — Verified 2026-11-12: `xcodebuild build-for-testing` of `projectM-iOS` succeeded; both sheets are driven by the UI tests (`xcodebuild test … -only-testing:projectM-iOSUITests/PresetCollectionsUITests` on the iOS 27.2 simulator (iPhone 18 Pro): 3 of 3, in two consecutive final runs).
- [X] PRE-007-T13 [US1] {sim} Create `APP/Views/PresetCollectionsView.swift` (R1-R3, R7, R18):
  rows `collection:<name>` labelled "<name>, <n> presets"; `newCollection`; Edit mode with move
  and delete; swipe actions and context menu (Rename, Move Up, Move Down, Delete); VoiceOver
  custom actions for the moves; delete confirmation; `collectionsEmpty`;
  `collectionsUnavailable` (newer format) and `collectionsNotice` (unreadable data set aside,
  shown once with a dismiss button; R15). Evidence: the app builds; exercised by T16. — Verified 2026-11-12: exercised by the UI tests (create, duplicate-name refusal, Move Up of a collection, delete with confirmation, empty state): `xcodebuild test … -only-testing:projectM-iOSUITests/PresetCollectionsUITests` on the iOS 27.2 simulator (iPhone 18 Pro): 3 of 3, in two consecutive final runs. The newer-format and set-aside texts are covered at coordinator level (T10), not by a UI test.
- [X] PRE-007-T14 [US2] {sim} Create `APP/Views/PresetCollectionView.swift` (R5, R6, R11, R13,
  R18): `PresetRow`s in the user's order, choosing calls `onChoose(preset, .collection(id))`,
  Edit mode with move and remove, context menu (Move Up, Move Down, Remove from Collection),
  custom actions, Rename in the toolbar, `collectionEmpty`, Done. Evidence: the app builds;
  exercised by T16. — Verified 2026-11-12: exercised by the UI tests (order as added, Move Up, Edit-mode drag handle, Remove from Collection, choose → scope, Rename sheet): `xcodebuild test … -only-testing:projectM-iOSUITests/PresetCollectionsUITests` on the iOS 27.2 simulator (iPhone 18 Pro): 3 of 3, in two consecutive final runs.
- [X] PRE-007-T15 [US1] {sim} Change `APP/Views/PresetBrowserView.swift`: the home row
  `node:collections`, the navigation routes, the alert for `collectionsMessage`, and the
  "Add to Collection…" context-menu item and swipe action on `PresetRow` (R4), so every list
  (folders, All A-Z, search, Favorites, collections) offers it. Evidence: the app builds; the
  existing browser identifiers are unchanged (`grep` of `PresetLibraryUITests.swift` ids). — Verified 2026-11-12: exercised by the UI tests (home row and its label, Add to Collection from the Included list through the row menu). Existing identifiers unchanged: `SettingsUITests` 7 and `VisualizerUITests` 3 pass; `PresetLibraryUITests` needs the full library (T22). The swipe action and the search/Favorites/All lists use the same `PresetRow` and were not driven by a UI test.
- [X] PRE-007-T16 [US2] {sim} Write `APP/UITests/PresetCollectionsUITests.swift` (launch with
  `-uitestUnlocked NO`; scroll lazily built rows into view):
  - create "Friday set", refuse a duplicate name with the message, add three Included presets
    from the Included list (the third through "New Collection…" is not used here; one of them is
    added to a second collection created from inside the add sheet, R4), open the collection and
    check the order added; adding a preset twice shows the checkmark and changes nothing;
  - Move Up on the last preset, relaunch without the reset argument, check the same order (S1);
  - choose a preset: the scope line is "Friday set · 3", Next and Previous follow the order and
    wrap, Random stays inside;
  - move the second collection up, relaunch, same order (S1);
  - remove one preset from a collection: it is gone there and still in Included (R5);
  - star a preset, delete "Friday set": the preset is still in Included and still starred, the
    scope line falls back to "Included · 28" (S2).
  Evidence: the UI tests pass on the iOS 27.2 simulator, twice. — Verified 2026-11-12: `xcodebuild test … -only-testing:projectM-iOSUITests/PresetCollectionsUITests` on the iOS 27.2 simulator (iPhone 18 Pro): 3 of 3, in two consecutive final runs. Earlier runs failed and were fixed: a hang when a row menu and a pending drag-to-reorder shared the touch-and-hold (move handler now only in Edit mode), a hang after closing two sheets in one step, two test mistakes (ambiguous Done and alert button queries), a drag that needed slow velocity; one run failed at the first control tap while the Mac's load average was about 70 and passed when rerun. Shortened 2026-11-13 under owner rule 7: waits poll every 0.1 s (`UITests/UITestWaits.swift`; `waitForExistence` and predicate expectations checked only about once a second, about 1 s per wait even when the element was there) and `-autostart inAppPlayback` replaces the notice and chooser taps; the two long flows (120 s and 109 s) are split into five tests with every rule kept: duplicate name and add-once (R9; 25 s), preset order with Move Up, relaunch and the Edit-mode drag, the first add creating the collection in the add sheet (S1, R4; two presets; 34 s), collection order with Move Up and relaunch (S1; 25 s), playing a collection with Next/Previous wrap and Random (S4; three Random taps instead of five; 27 s), remove one preset then delete the collection with the favorite and Included kept and the scope falling back (R5, S2; 32 s). Verified 2026-11-13 on an iOS 27.2 iPhone 17 simulator (6ABB17A2-…): `-only-testing:projectM-iOSUITests/PresetCollectionsUITests` 6 of 6 passed with the final code (one run), and 6 of 6 with the revision before it, which differed only in a 1.0 s instead of 0.7 s touch-and-hold and the swipe loop.

## Phase 6: Polish and cross-cutting

- [X] PRE-007-T17 [P] {mac} Update `docs/privacy-policy.md` (R17): the stored-data list gains the
  collections bullet, the "settings storage" sentence covers the file, and the coverage table
  gains a PRE-007-R17 row. Evidence: `python3 scripts/validate_docs.py` passes. — Verified 2026-11-12: `python3 scripts/validate_docs.py` OK (77 files).
- [X] PRE-007-T18 {sim} Run `PresetLibrary` tests on the iOS 27.2 simulator
  (`xcodebuild test -scheme PresetLibrary`). Evidence: all pass. — Verified 2026-11-12: `xcodebuild test -scheme PresetLibrary -destination 'id=<iPhone 18 Pro, iOS 27.2>'`: 72 tests, 0 failures. Host: `swift test --package-path Packages/PresetLibrary` 72 tests, 0 failures, twice. Linux was not run.
- [X] PRE-007-T19 {sim} Regression (S10): `PresetTests`, `LibraryStoreTests`, `SettingsTests`,
  `AccessibilityTests` and `SettingsUITests` pass in the worktree build; record the known
  environmental failure. Evidence: xcodebuild log lines. — Verified 2026-11-12: `-only-testing:projectM-iOSTests`: 75 tests, 1 failure, in two consecutive runs; the failure is the known environmental `PresetTests.testBundledIncludedScopeMatchesRelease1_0` (worktree has 28 presets). An earlier run stopped in `LibraryStoreTests.testFailureUnlocksNothing` (exceeded the 3-minute allowance; StoreKit test session, code this feature does not touch) and passed in both reruns. `SettingsUITests` 7 of 7 and `VisualizerUITests` 3 of 3.
- [X] PRE-007-T20 {mac} `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`
  and `python3 scripts/test_scripts.py` pass; no file under `Vendor/`, `Apps/projectM-iOS/Store/`
  or `Apps/projectM-iOS/Resources/` changed (`git diff --stat` against the branch point). — Verified 2026-11-12: `check_compliance.py` OK, `validate_docs.py` OK, `test_scripts.py` 88 tests OK (1 skipped); `git diff --stat 6d669fc -- Vendor Apps/projectM-iOS/Store Apps/projectM-iOS/Resources project.yml .github` is empty.
- [X] PRE-007-T21 {sim} Dynamic Type and labels (R18): run the collections UI flow once with the
  largest accessibility text size (`-UIPreferredContentSizeCategoryName
  UICTContentSizeCategoryAccessibilityXXXL`) and check the rows and buttons exist and are
  hittable; every new control has a label (unit assertion of the row label strings). — Verified 2026-11-12: `testTheCollectionScreensWorkAtTheLargestTextSize` (AccessibilityXXXL) passes in both final runs: rows and buttons exist and are hittable; `testRowLabels` asserts the label strings. A VoiceOver pass by a person is part of T23. Shortened 2026-11-13 under owner rule 7: same waits and launch; 43.6 s → 18.2 s, same assertions.
- [ ] PRE-007-T22 {merge} (open: needs the preset submodules, which a worktree does not have; for the main session after the merge) Full-library checks on the integration checkout: the existing
  `PresetLibraryUITests` and `PurchaseUITests` pass (S10); with `-uitestUnlocked NO` add a
  Cream of the Crop preset to a collection, see it locked there, tap it → purchase sheet (US4 on
  the real index).
- [ ] PRE-007-T23 {device} (open: final device stage) S11 on D1-D3: collections survive installing over the previous build;
  reorder with VoiceOver using the Move Up / Move Down actions; S8 timing by hand. Final device
  stage only.

## Dependencies

- T01 → T04, T06. T02 → T03 → T04 → T05 → T06 → T07.
- T07 → T08 → T09 → T10 → T11 → T12 → T13, T14, T15 → T16.
- T17 is independent. T18-T21 after T16. T22 after the merge. T23 last.
- Story order: US1 and US2 need Phase 2; US3 needs T09; US4 is covered by T08-T11 and T22 (the
  worktree has no locked presets in the real index, so the screen check is `{merge}`).

## Parallel opportunities

Single agent, single worktree: tasks run in order. `[P]` marks T17, which touches only the
privacy policy.

## Implementation strategy

MVP = Phases 1-2 plus T10-T15 for US1 (create, fill, delete). US2 (order) and US3 (play) are
delivered by the same store and views, so all four stories land together; each commit keeps the
package tests green.
