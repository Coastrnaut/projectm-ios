# Implementation Plan: SCN-011 Scene Template Gallery

**Branch**: `feature/scn-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Five read-only starter scenes ship in the app bundle (`SceneTemplates/`: a `manifest.json` plus one
`.scene.json` per scene). `ShowStorage` gains a pure, Foundation-only template catalog (manifest decode,
per-template load with SCN-001 decoding, licence records) and `ShowStore.storeTemplateCopy`, which writes a
copy of a template scene under a new ID through SCN-001 `duplicated(newID:name:)`, never over an existing
file. `ShowCoordinator.addTemplate` checks capacity, writes every copy, appends the cues (with the
template's SCN-007 transition), tags them "template" (SCN-005), saves once, reports `sceneFilesChanged`
(SCN-006) and announces on the library lane. Settings → Show gains "Add from Template…", a sheet listing
the templates.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: ShowControl/ShowStorage, SceneFormat, ParameterGraph (registry validation in app tests); app ShowCoordinator, ShowEditorView
**Storage**: bundled read-only files; copies in the show store (`Application Support/Show/Scenes`)
**Testing**: XCTest: ShowControl package (host; Linux-compatible), app unit tests, one UI test on simulator "SCN11 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+
**Constraints**: scene format unchanged; no new UserDefaults keys; no networking; owner rule 7 budgets; Xcode 26 type-check budget

## Constitution Check

- I (public APIs only), no networking, local-first: pass (bundle files, local show store).
- IX (licence review): pass. No third-party content: only native visuals, app parameters and text written for the project, all MIT (repository `LICENSE`); every asset recorded in the manifest and enforced by a test. No preset is bundled or referenced by a template.
- Accessibility (FR-070): a standard List in a sheet, one element per row, announcer library lane.
- Photosensitive safety: copies apply through the existing cue path (glow and spectrum values clamped by MOD-001; Reduce flashing unaffected).
- No compatibility or device claims.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Apps/projectM-iOS/Resources/SceneTemplates/manifest.json              # new: templates, scenes, asset licences
Apps/projectM-iOS/Resources/SceneTemplates/*.scene.json               # new: six scene files (five templates)
Packages/ShowControl/Sources/ShowStorage/SceneTemplates.swift         # new: manifest, catalog, storeTemplateCopy
Packages/ShowControl/Tests/ShowControlTests/SceneTemplateTests.swift  # new: bundled files decode, licences, independence
Apps/projectM-iOS/Coordinators/ShowCoordinator+Templates.swift        # new: addTemplate
Apps/projectM-iOS/Views/SceneTemplateGalleryView.swift                # new: the sheet
Apps/projectM-iOS/Views/ShowEditorView.swift                          # "Add from Template…" row
Apps/projectM-iOS/Tests/SceneTemplateAcceptanceTests.swift            # new: acceptance 1-3, registry validation
Apps/projectM-iOS/UITests/SceneTemplateUITests.swift                  # new: add a template, its cue appears
project.yml                                                           # SceneTemplates as a folder resource
```

## Complexity Tracking

None.
