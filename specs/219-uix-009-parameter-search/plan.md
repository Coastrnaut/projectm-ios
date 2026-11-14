# Implementation Plan: UIX-009 Parameter Search

**Branch**: `feature/uix-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A pure, deterministic search over every MOD-001 parameter descriptor (`ParameterSearch` in the ParameterGraph
package, Foundation only, tested on every CI host including Linux) returns ranked parameter IDs and takes no
layer or visual input, so the current selection cannot change the result (UIX-009-R1). The app adds a
"Search Parameters" row in Settings (next to Modulation) that pushes a `.searchable` list of rows built by
`ParameterSearchRows` (name, group, current value, "on screen" mark); choosing a row opens the UIX-003 inspector
sheet over Settings by ID.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the Mac; CI Xcode 26 type-check budget)
**Primary Dependencies**: ParameterGraph (MOD-001 types), VisualParameters (catalog), SwiftUI
**Storage**: none (no new UserDefaults key, nothing saved)
**Testing**: XCTest — ParameterGraphTests (search), app unit tests (rows, layer independence with the real catalog), one XCUITest
**Target Platform**: iOS 26+ / iPadOS 26+
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: search of the whole catalog well under 1 ms (15 descriptors; linear scan)
**Constraints**: no wall-clock assertions; UI test < 30 s; SwiftUI bodies split into properties
**Scale/Scope**: 15 parameters today; linear in catalog size

## Constitution Check

- I Public APIs only: Foundation `String.folding`, SwiftUI `.searchable`. Pass.
- VI Modular boundaries: matching and ranking live in ParameterGraph (no UI, no app types); the app only builds rows and navigation. Pass.
- VII Real-time audio safety: no audio or render path touched; search runs on the main actor on keystrokes over 15 items. Pass.
- Privacy/local-first: nothing stored, nothing sent. Pass.
- X Evidence-based quality: unit tests per rule with representative cases; one short UI test; no device claim. Pass.

Post-design re-check: unchanged, pass. No ADR: no constitution rule or project default is overridden.

## Project Structure

### Documentation (this feature)

```text
specs/219-uix-009-parameter-search/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/parameter-search.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/ParameterGraph/Sources/ParameterGraph/ParameterSearch.swift        # new: fold, unit terms, match, rank
Packages/ParameterGraph/Tests/ParameterGraphTests/ParameterSearchTests.swift # new
Apps/projectM-iOS/Coordinators/ParameterSearchModel.swift                    # new: rows, on-screen groups
Apps/projectM-iOS/Views/ParameterSearchView.swift                            # new: link section + searchable list
Apps/projectM-iOS/Views/SettingsView.swift                                   # one line in mediaSections
Apps/projectM-iOS/Tests/ParameterSearchAppTests.swift                        # new: acceptance with the real catalog
Apps/projectM-iOS/UITests/ParameterSearchUITests.swift                       # new: search and open another layer's inspector
```

**Structure Decision**: search logic in the existing ParameterGraph package (already in a CI package group, so
no workflow change); UI in the app next to the UIX-003 inspector it opens.

## Complexity Tracking

None.
