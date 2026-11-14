# Tasks: SCN-005 Scene Tags

**Input**: [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md),
[contracts/scene-tags.md](contracts/scene-tags.md), [research.md](research.md)

Tests are requested by the roadmap row (schema round trip, integration, simulator). Budgets (owner
rule 7): unit tests about 1-2 s, package suites under 1 minute, the UI test under 30 s.

## Phase 1: Setup

- [X] SCN-005-T01 Create the feature's own simulator "SCN5 iPhone 17" (iOS 27.2), `xcodegen generate`, keep the `Build` link, and count PosterBoard reports before any run. — Verified 2026-11-14: simulator SCN5 (7F7D552A) created on iOS 27.2, `xcodegen generate`, `Build` link present, preset submodules initialized, PosterBoard reports 25 before.

## Phase 2: Foundational (model and file format; blocks every story)

- [X] SCN-005-T02 Implement `SceneTagMap` and `SceneTagError` in `Packages/ShowControl/Sources/ShowControl/SceneTags.swift`: tags "trimmed, 1-40 characters, one line"; "≤ 16 per scene"; "≤ 256 distinct per show"; folded identity (SCN-004 fold); existing spelling adopted; each scene's tags sorted by (fold, text); `add`, `remove`, `copyTags`, `vocabulary`, `count(of:)`, `matches(sceneID:all:)`, `prune(keepingScenes:)`, `repaired` (research SCN-005-D2, D3; contract T3). — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` (SceneTagMapTests 5/5).
- [X] SCN-005-T03 Add `tags` to `ShowCueList` with `addTag`, `removeTag`, `copyTags` (refuse a scene no cue refers to) in `Packages/ShowControl/Sources/ShowControl/ShowCueList.swift`. — Verified 2026-11-14: ShowTagDocumentTests.testTaggingASceneThatNoCueShowsIsRefused and testTagsOfScenesNoCueShowsAreNotWritten.
- [X] SCN-005-T04 Encode and decode the optional `sceneTags` key (written only when non-empty after pruning; lenient decoding; `ShowDecodeWarning.droppedTags(n)`) in `Packages/ShowControl/Sources/ShowControl/ShowDocument.swift` (research SCN-005-D4; contract T1, T2). — Verified 2026-11-14: ShowTagDocumentTests 6/6 (round trip, legacy bytes, repair warning).
- [X] SCN-005-T05 [P] Package tests for the tag rules (trim, folding and dedup, adopted spelling, limits 40 / 16 / 256, remove, vocabulary, AND matching) in `Packages/ShowControl/Tests/ShowControlTests/SceneTagMapTests.swift`. — Verified 2026-11-14: SceneTagMapTests 5 tests pass in 0.01 s.
- [X] SCN-005-T06 [P] Package tests for the file format in `Packages/ShowControl/Tests/ShowControlTests/ShowTagDocumentTests.swift`: round trip, determinism, a legacy file without `sceneTags` re-encoding byte for byte, damaged data repaired with a warning (unknown scene, bad tag, duplicate, over limit, non-object), a `ShowStore` save → reload keeping tags, and FILE-004 `installImportedScenes` keeping existing tags. — Verified 2026-11-14: ShowTagDocumentTests 6 tests pass; ShowControl 67/67 in 1.1 s.

## Phase 3: User Story 1 — tag scenes and filter by tag (P1, MVP)

**Independent test**: tag scenes, filter switcher entries by tags and text, change a tag and see the results update, reload from disk and get the same tags and results.

- [ ] SCN-005-T07 [US1] Tag operations in `Apps/projectM-iOS/Coordinators/ShowCoordinator.swift`: `tags(ofScene:)`, `tagVocabulary`, `addTag`, `removeTag` (save, announce on `announceLibrary`, refusals as editor message and announcement); Duplicate Scene copies tags (SCN-005-R9).
- [ ] SCN-005-T08 [US1] Switcher filtering in `Apps/projectM-iOS/Coordinators/SceneSwitcher.swift` (`tags` on entries, VoiceOver ", tags …", tag-aware `results`, `selectedTags`, `toggleTag`) and `Apps/projectM-iOS/Coordinators/AppCoordinator+SceneSwitcher.swift` (`toggleSwitcherTag`: re-highlight, count announcement) (contract T4).
- [ ] SCN-005-T09 [US1] `Apps/projectM-iOS/Views/SceneTagsView.swift` (Tags sheet, contract T5) and the switcher UI in `Apps/projectM-iOS/Views/SceneSwitcherView.swift` (chip row, row tag button, VoiceOver action "Tags", subtitle); register the new view in `scripts/check_status_events.py`.
- [ ] SCN-005-T10 [US1] Scene Folders integration in `Apps/projectM-iOS/Views/SceneFoldersView.swift`: tags on scene rows, "Tags…" swipe action, context menu and VoiceOver action opening the sheet.
- [ ] SCN-005-T11 [US1] Acceptance test `Apps/projectM-iOS/Tests/SceneTagAcceptanceTests.swift`: tag scenes, filter by chips (AND) and text, change a tag and check the results update, reload a coordinator from the same store and check tags and results persist; duplicate copies tags; removing the last cue drops the scene's tags; a selected chip whose tag no scene carries any more is ignored; an unreadable scene keeps its tags and can be tagged (spec Edge Cases); search matches tags in `Apps/projectM-iOS/Tests/SceneSwitcherTests.swift`.
- [ ] SCN-005-T12 [US1] UI test `Apps/projectM-iOS/UITests/SceneTagsUITests.swift` (under 30 s): with `-uitestShowSeed`, open the switcher, tag cue 1 "Intro" through the row's tag button, select the "Intro" chip (reached with the shared `app.reveal`) and see only cue 1.

## Phase 4: User Story 2 — tag rules (P2)

- [ ] SCN-005-T13 [US2] Refusal messages and announcements for invalid, duplicate and over-limit tags covered in `SceneTagMapTests` and `SceneTagAcceptanceTests` (no change on refusal).

## Phase 5: User Story 3 — backup and older files (P2)

- [X] SCN-005-T14 [P] [US3] Backup round trip in `Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupSceneTagTests.swift`: backup, exact restore into a fresh sandbox, same tags and same `show.json` bytes. — Verified 2026-11-14: `swift test --package-path Packages/LibraryBackup --filter LibraryBackupScene` 2/2 (tags and SCN-004 folders) in 0.07 s.

## Phase 6: Polish

- [ ] SCN-005-T15 Repo checks (compliance, docs, motion, permissions, status events, script tests), privacy manifest and network symbol checks on the Debug app, type-check budget, no new UserDefaults keys (SCN-005-R14: grep the diff), PosterBoard count after; update spec status; delete the simulator and derived data.

## Dependencies

T01 → T02 → T03 → T04 → (T05, T06, T14 in parallel) → T07 → T08 → T09, T10 → T11 → T12 → T13 → T15.

## Implementation strategy

MVP = Phases 1-3 (tag, filter, persist). US2 and US3 are mostly tests over the same code.
