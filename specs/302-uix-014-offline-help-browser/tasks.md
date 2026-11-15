# Tasks: UIX-014 Offline Help Browser

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/help-content.md](contracts/help-content.md)

## Phase 1: Setup (content and bundling)

- [X] UIX-014-T01 Write `Apps/projectM-iOS/Resources/Help/index.json` and the eleven articles (`getting-started.md`, `visuals.md`, `presets.md`, `scenes-shows.md`, `effects.md`, `layers-media.md`, `recording.md`, `external-display.md`, `midi-osc.md`, `accessibility-safety.md`, `privacy.md`) from the app's current labels and footers, each ≤ 400 words, no links or addresses, no named music services (R1, R5, R8, D1, D3, D7) — Verified 2026-11-15: `HelpLibraryTests.testEveryIndexedArticleIsBundledAndOpensWithItsTitleAndBody` and `testNoArticleHasALinkAnAddressUnsupportedSyntaxOrANamedService` pass (11 articles, 203-257 words each); labels checked against the app sources
- [X] UIX-014-T02 `project.yml`: exclude `Resources/Help` from the app's sources and add it as a folder resource; `xcodegen generate` (R1) — Verified 2026-11-15: `xcodegen generate`; the built Debug app holds `Help/index.json` and all 11 `.md` files

## Phase 2: Foundational (model and parser)

- [X] UIX-014-T03 `Apps/projectM-iOS/Coordinators/HelpLibrary.swift`: `HelpEntry`, `HelpBlock`, `HelpArticle`, `HelpMarkdown.parse`, `HelpLibrary.bundled/entries/search/article(for:)`, and `HelpContentRules` (link, address, syntax and name checks; word count) (R3, R4, R5, R9, D2, D5) — Verified 2026-11-15: `testParserReadsTheSubset`, `testRulesCatchLinksAddressesNamesAndLength`, `testMissingFileAndMissingIndexGiveNil` pass

## Phase 3: User Story 1 — read help without a connection (P1, MVP)

- [X] UIX-014-T04 [US1] `Apps/projectM-iOS/Views/HelpBrowserView.swift`: `HelpSection` (Settings row `helpLink`), `HelpBrowserView` (list), `HelpArticleView` (blocks as `Text` with text styles, headings with the header trait), unavailable and missing states (R2, R4, R7, R9) — Verified 2026-11-15: `HelpBrowserUITests` 2/2 pass; no -warn-long-function-bodies/-expression warnings in the new files
- [X] UIX-014-T05 [US1] Add `HelpSection().id("help")` to `SettingsView.tailSections` before Storage, outside the scene-lock-disabled sections (R2, D4; edge case: scene lock) — Verified 2026-11-15: `HelpBrowserUITests` reach `helpLink` with `-uitestSettingsSection help`; SettingsTests and LibraryBackupAppTests pass
- [X] UIX-014-T06 [US1] App unit tests `Apps/projectM-iOS/Tests/HelpLibraryTests.swift`: every index entry is in the built bundle and opens through `HelpLibrary.article(for:)` with a level-1 heading equal to its title and body blocks; content rules over every article (no `http://`, `https://`, `www.`, `mailto:`, links, images, tables, code, HTML; no named services; ≤ 400 words); parser cases (headings, paragraphs joined, bullets, numbers, inline emphasis); missing file → nil; source scan of the two help Swift files for networking and web symbols (S1, S2, S4, acceptance) — Verified 2026-11-15: `-only-testing:projectM-iOSTests/HelpLibraryTests` 7/7 pass (0.04 s) on the UIX14 iPhone 17 iOS 27.2 simulator, including `testHelpSourcesUseNoNetworkingOrWebAPI`

## Phase 4: User Story 2 — find the right article (P2)

- [X] UIX-014-T07 [US2] Search: `.searchable` on the list, "No help articles match" when empty; unit tests for case- and accent-insensitive title and keyword matches and the empty query (R3, S3) — Verified 2026-11-15: `testSearchMatchesTitlesAndKeywordsIgnoringCaseAndAccents` passes; the UI test sees "No help articles match"
- [X] UIX-014-T08 [US2] UI test `Apps/projectM-iOS/UITests/HelpBrowserUITests.swift`: Settings opens at `help`, open Help, search "midi" → only MIDI and OSC, open it and check its heading; search "flash" → open Accessibility and sensory safety and check its heading; under 30 s — Verified 2026-11-15: `HelpBrowserUITests.testSearchAndOpenTwoArticles` passes (18.7 s)

## Phase 5: User Story 3 — VoiceOver and large text (P2)

- [X] UIX-014-T09 [US3] The UI test also checks that headings carry the header trait (`helpHeading` elements of type header) and one launch at an accessibility text size shows the article title (R7) — Verified 2026-11-15: `HelpBrowserUITests.testArticleOpensAtAnAccessibilityTextSize` passes (18.5 s) at AccessibilityXL; headings carry `.isHeader` in `HelpBlockView` (code read; XCUITest cannot query the trait directly)

## Phase 6: Polish

- [X] UIX-014-T10 Repo checks (compliance, docs, motion, permission catalog, status events, script tests); `check_privacy_manifest.py` and `check_network_symbols.py` on the Debug app; type-check budget on the new files; LibraryBackupAppTests and SettingsTests still pass; no new UserDefaults key (R6, R10) — Verified 2026-11-15: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events exit 0; test_scripts 186 OK (1 skipped); check_privacy_manifest and check_network_symbols OK on the Debug simulator app (19 images); SettingsTests and LibraryBackupAppTests pass; no new UserDefaults key
- [X] UIX-014-T11 Mark the spec Implemented; final report — Verified 2026-11-15: spec Status set to Implemented; no ADR (no default overridden)
- [ ] UIX-014-T12 {device} On D1 with Airplane Mode on (Wi-Fi off): Settings › Help, open all eleven articles; each shows its title and text at once (S1, roadmap acceptance)

## Dependencies

T01 → T02 → T03 → T04 → T05 → T06, T07 → T08, T09 → T10 → T11; T12 needs a device and a person. No new
UserDefaults key, so no key list changes.

## Parallel opportunities

T01 (content) and T03 (code) are independent files.

## Implementation strategy

MVP is T01-T06 (articles bundled and opened offline); US2 and US3 add search and accessibility checks.

## Analysis (speckit-analyze, 2026-11-15)

Coverage: R1 T01-T02; R2 T04-T05; R3 T07; R4 T03-T04; R5 T01, T06; R6 T06, T10; R7 T04, T09; R8 T01, T06; R9 T03-T04,
T06; R10 T10. S1 T06, T12; S2 T06, T10; S3 T07-T08; S4 T06. No unmapped requirement, no constitution conflict.
Fixes applied: the scene-lock edge case is covered by placing Help in `tailSections` (outside the locked
`sceneEditSections`), stated in T05; T09's large-text launch uses the `UIPreferredContentSizeCategoryName` launch
argument (no setting written).
