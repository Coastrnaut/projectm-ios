# Tasks: UIX-009 Parameter Search

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [contracts/parameter-search.md](contracts/parameter-search.md)

## Phase 1: Foundational (search core)

- [X] UIX-009-T01 Add `ParameterSearch` (fold, word split, tiers, ranking, `search`/`ids`) and `ParameterUnit.searchTerms` in `Packages/ParameterGraph/Sources/ParameterGraph/ParameterSearch.swift` (R2-R4, D2-D4) — Verified 2026-11-14: `swift test --package-path Packages/ParameterGraph --filter ParameterSearchTests` (7 tests pass, 0.003 s)
- [X] UIX-009-T02 [P] Tests in `Packages/ParameterGraph/Tests/ParameterGraphTests/ParameterSearchTests.swift`: empty query, AND of words, ranking order, group ID match, unit prefixes ("%", "ms", "Hz", "s"), diacritics and case, no enum-case match — Verified 2026-11-14: `swift test --package-path Packages/ParameterGraph --filter ParameterSearchTests` (7 tests pass, 0.003 s)

## Phase 2: User Story 1 — find and open (P1, MVP)

- [ ] UIX-009-T03 Add `ParameterSearchRows` (rows with name, group, value or "Read only", on-screen groups per visual) in `Apps/projectM-iOS/Coordinators/ParameterSearchModel.swift` (R5, D6, D7)
- [ ] UIX-009-T04 Add `ParameterSearchLinkSection` and `ParameterSearchView` (`.searchable`, rows as buttons with the S4 identifiers and VoiceOver values) in `Apps/projectM-iOS/Views/ParameterSearchView.swift`; one line in `SettingsView.mediaSections` before Modulation, `.id("parameterSearch")`; choosing calls `inspectParameter` (R5, R6, R8)
- [ ] UIX-009-T05 Acceptance unit tests in `Apps/projectM-iOS/Tests/ParameterSearchAppTests.swift` with the real catalog: identical IDs for "radius", "%", "bars", "orientation" with no layer, the circular and the linear visual; unit queries "%", "ms", "Hz" equal the catalog's unit sets; row values and on-screen marks (S1, S2)
- [ ] UIX-009-T06 UI test `Apps/projectM-iOS/UITests/ParameterSearchUITests.swift`: circular visual, Settings › Search Parameters, type "orientation", choose `visual.linearSpectrum.orientation`, the inspector shows it; under 30 s

## Phase 3: User Story 2 — empty and no-result states (P2)

- [ ] UIX-009-T07 Empty query lists every parameter under group headers; no-match shows `parameterSearchEmpty` (R7); covered by T05 (rows grouping) and T06 (asserts the no-result text for a nonsense query first)

## Phase 4: Polish

- [ ] UIX-009-T08 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbol checks on the Debug app, type-check budget on new files
- [ ] UIX-009-T09 Mark spec Implemented; final report

## Dependencies

T01 → T02, T03 → T04 → T05, T06 → T07 → T08 → T09. No new UserDefaults key (spec Assumptions), so no key lists change. No `{device}` task.

## speckit-analyze (2026-11-14)

Coverage: R1→T01/T05, R2→T01/T02, R3→T02/T05, R4→T02, R5→T03/T04/T05, R6→T04/T06, R7→T07, R8→T04/T06; S1→T05, S2→T05, S3→T06, S4→T01 (by construction).
Findings applied: (1) S4 has no timing test (owner rule: no wall-clock assertions); it is met by construction — one linear pass over the catalog per keystroke — and stated so in plan.md Performance Goals. (2) Terminology: "on screen" is used throughout for the current-visual mark (not "current layer"), since the mark never filters. No critical issues.
