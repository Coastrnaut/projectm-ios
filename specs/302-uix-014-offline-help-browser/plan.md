# Implementation Plan: UIX-014 Offline Help Browser

**Branch**: `feature/uix-014` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Bundle eleven short Markdown help articles and a JSON index in the app (`Apps/projectM-iOS/Resources/Help`, a folder
resource like `Licenses`), and add Settings › Help: a searchable list and an article screen that renders a small
Markdown subset natively (SwiftUI `Text` per block, inline emphasis through `AttributedString(markdown:)` with
inline-only syntax). No web view, no links, no networking. Offline opening is proved structurally (research
UIX-014-D6) plus one `{device}` check in Airplane Mode on D1.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2; CI Xcode 26), SwiftUI, iOS 26+
**Primary Dependencies**: Foundation, SwiftUI only (no new package)
**Storage**: read-only bundle files; nothing written (UIX-014-R10)
**Testing**: XCTest app unit tests (`projectM-iOSTests`), XCUITest (`projectM-iOSUITests`), repo scripts
**Target Platform**: iPhone and iPad (the existing app target)
**Project Type**: mobile app feature
**Performance Goals**: an article opens without a loading state; all eleven parse well inside one unit test's 10 s budget
**Constraints**: FR-068 (no networking API, no web view); type-check budget (300 ms per body, 200 ms per expression)
**Scale/Scope**: 11 articles, each ≤ 400 words; 2 Swift source files, 2 test files

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: SwiftUI and Foundation only. |
| IV/V. Truthful labels, no universal-capture claims | Pass: articles describe what each source does; a test rejects named music services (UIX-014-R8). |
| VI. Modular boundaries | Pass: help is app UI; it touches no capture, PCM, engine or renderer layer. |
| VII. Real-time audio safety | Pass: nothing runs on the audio path. |
| X. Evidence-based quality | Pass: unit tests for the parser, index and article rules; Airplane Mode on a device is a `{device}` task, never claimed from the simulator. |
| Security/Privacy (no telemetry or network) | Pass: no networking code; built-app scan (`check_network_symbols.py`) stays clean. |

Post-design re-check: unchanged, all pass. No ADR needed (no default overridden).

## Project Structure

### Documentation (this feature)

```text
specs/302-uix-014-offline-help-browser/
├── spec.md  plan.md  research.md  data-model.md  quickstart.md  tasks.md
├── contracts/help-content.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Apps/projectM-iOS/
├── Resources/Help/            # index.json + 11 *.md articles (folder resource, project.yml)
├── Coordinators/HelpLibrary.swift   # index model, search, Markdown-subset parser, content rules
├── Views/HelpBrowserView.swift      # Settings › Help list, search, article view
├── Views/SettingsView.swift         # one Help section in tailSections (small edit)
├── Tests/HelpLibraryTests.swift     # bundle, parser, search, rules, source scan
└── UITests/HelpBrowserUITests.swift # list, search, open two articles
project.yml                          # exclude Resources/Help from sources, add it as a folder resource
```

**Structure Decision**: app-local code beside `LicensesView` (the same bundled-text pattern); no package, so no CI
package group change.

## Complexity Tracking

None.
