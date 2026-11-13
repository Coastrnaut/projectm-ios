# Implementation Plan: ACC-002 Reduced Flash Preset Policy

**Branch**: `feature/acc-002` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/030-acc-002-reduced-flash-preset-policy/spec.md`

## Summary

A deterministic text screen (the flash risk classifier) reads each preset's per-frame equations
and names the rules that flag it (research ACC-002-D1, D2). It exists twice, as one definition with
two executions like FX-019 (ADR-0011 decision 5): `scripts/preset_flash_risk.py` runs inside the
build's index step and writes an optional `flash` list into each flagged record of
`PresetIndex.json`; `PresetFlashRisk` (Swift, in `Packages/PresetLibrary`) screens imported and
edited presets in the app. Both are checked against one fixture set with expected verdicts. The
app's `PresetCoordinator` applies the policy while Reduce flashing is on: Next, Previous, Random,
warm-up and the launch preset walk only unflagged presets; an explicit choice of a flagged preset
sets a pending warning that the browser shows as an alert (Load Anyway / Cancel) before anything
loads; rows show a "May flash" mark. FX-019's envelope is untouched. Research:
[research.md](research.md); entities: [data-model.md](data-model.md); contracts:
[contracts/flash-risk-classifier.md](contracts/flash-risk-classifier.md),
[contracts/flash-policy.md](contracts/flash-policy.md); checks: [quickstart.md](quickstart.md);
decision record: ADR-0014.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 language mode), Python 3 (build script),
Xcode 27.2

**Primary Dependencies**: Foundation (`NSRegularExpression`, available on Linux) in PresetLibrary;
Python standard library (`re`) in the script; SwiftUI in the app. No new third-party dependency.

**Storage**: the build-generated `PresetIndex.json` gains an optional `flash` field (not
committed; research R-30 of feature 002). Nothing new on the device.

**Testing**: XCTest (`swift test --package-path Packages/PresetLibrary`, Linux in CI); Python
`scripts/test_scripts.py`; app unit tests (`FlashPolicyTests`) and one UI test
(`FlashPolicyUITests`) on the iOS 27.2 simulator.

**Target Platform**: iOS/iPadOS 26.0+, macOS 15+ (host tests), Linux (CI).

**Project Type**: iOS app plus SwiftPM library package plus build script.

**Performance Goals**: screening 14,576 pack files in Python takes about 5 s on the Mac Studio
(measured in research; once per index rebuild, which the stamp skips when nothing changed). One
imported preset (at most 256 KB) screens in milliseconds. The index grows by about 100 short
fields; loading it is not measurably slower.

**Constraints**: no rendering at build time; no network; no main-actor mutation in test
setUp/tearDown; no C stdio globals; explicit closure types for Xcode 26; unit tests about 1 s, UI
test under 30 s (owner rule 7).

**Scale/Scope**: about 200 lines of Python, 250 of package Swift, 150 of package tests, 120 of
app Swift, 150 of app tests, two fixture presets.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | Foundation, SwiftUI, `UIAccessibility` | Pass |
| II-III Capture | Not touched | Pass (n/a) |
| IV Truthful labeling | The mark says "May flash", not "safe"/"unsafe"; unflagged presets are never called safe | Pass |
| V No universal claims | No compatibility text | Pass |
| VI Modular boundaries | Classifier in PresetLibrary (Foundation only); policy in the app's coordinator; renderer and engine untouched | Pass |
| VII Real-time safety | Nothing on audio or render callbacks | Pass |
| VIII ProjectM fidelity | Preset text is only read; projectM gets the same bytes; no engine change | Pass |
| IX Dependencies and licenses | None added. The two fixture presets are written for this repository (MIT, like the code), no third-party text | Pass |
| X Evidence | Unit tests for the classifier and the policy, one UI test; the corpus count is reported as information; device check is `{device}` and not claimed | Pass |
| Privacy | Nothing stored, recorded or sent; the warning's answer is not kept | Pass |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/030-acc-002-reduced-flash-preset-policy/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/flash-risk-classifier.md
├── contracts/flash-policy.md
├── checklists/requirements.md
└── tasks.md
docs/adr/0014-reduced-flash-preset-policy.md
specs/002-preset-library-unlock/contracts/preset-index.schema.json   # optional "flash"
```

### Source Code (repository root)

```text
scripts/preset_flash_risk.py                         # new: classifier (Python)
scripts/build_preset_index.py                        # writes "flash"; stamp covers the classifier
scripts/test_scripts.py                              # fixture parity, index field, schema
Packages/PresetLibrary/Sources/PresetLibrary/
├── PresetFlashRisk.swift                            # new: classifier (Swift twin)
├── PresetIndex.swift                                # IndexedPreset.flash, mayFlash
└── UserPresets/UserPresetLibrary.swift, UserPresetModel.swift   # screen playable user presets
Packages/PresetLibrary/Tests/PresetLibraryTests/
├── FlashFixtures/{high-flash.milk, calm.milk, …, expected.json}  # new, own text
├── PresetFlashRiskTests.swift                       # new
└── PresetLibraryTests.swift                         # index with and without "flash"
Packages/PresetLibrary/Package.swift                 # FlashFixtures as a test resource
Apps/projectM-iOS/Coordinators/PresetCoordinator.swift   # policy: walk, warning, launch
Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift  # flags for user presets
Apps/projectM-iOS/Coordinators/AppCoordinator.swift     # browser stays open while warned
Apps/projectM-iOS/Views/PresetBrowserView.swift          # "May flash" mark, warning alert
Apps/projectM-iOS/Tests/FlashPolicyTests.swift           # new
Apps/projectM-iOS/UITests/FlashPolicyUITests.swift       # new
```

**Structure Decision**: the classifier belongs with the index it annotates (PresetLibrary, which
already holds the import validator for untrusted preset text), not with FlashSafety, which models
rendered luminance and has no knowledge of preset text. The policy is app behavior over the
existing scope walk, so it stays in `PresetCoordinator` rather than a new package.

## Shared files and parallel work

MOD-001 and CMP-001 run in parallel and may touch `AppCoordinator`, `project.yml` or Settings.
This row's edits to shared files are small and additive: one optional field on `IndexedPreset`
(defaulted initializer parameter), one method on `UserPresetLibrary`, a filtered walk and a
pending-warning property in `PresetCoordinator`, one condition in `AppCoordinator.choose`, a mark
and an alert in the browser. No `project.yml` change is needed (PresetLibrary is already a
dependency; the new app test files are picked up by the existing source globs).

## Persistence and rollback

Nothing new is stored on the device. The index field is generated at build time; an index
without it reads as "nothing flagged" (ACC-002-R13), so rolling back the app or the script in
either order is safe. Rollback is reverting the feature's commits.

## Complexity Tracking

| Item | Why | Simpler alternative rejected because |
|---|---|---|
| Two implementations of the classifier | The bundled library is screened at build time (Python, no Swift toolchain step in the build phase); imported presets only exist on the device | One Swift implementation run at build time needs a Swift build step inside the app build; one Python implementation cannot run on the device. Drift is caught by the shared fixture set (ADR-0014) |
