# Implementation Plan: SHOW-012 Cue Annotations

**Branch**: `feature/show-012` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

A cue gains an optional private note. The model and file live in the `ShowControl` package (pure, Linux-tested); the
editor UI in the app. No new settings keys, no new export path: every show export already re-encodes the cue list.

1. `ShowCueNote` (new file `ShowCueNote.swift`): the rules (500 characters, line feeds kept, other control characters
   removed, trimmed) — `normalized(_:)` and a lenient `stored(_:)` that also cuts to the limit.
2. `ShowCue.operatorNote: String?`; `ShowCueList.setOperatorNote(_:to:)` (throws `.invalidNote` for over-long text;
   empty → nil); `insert(…, operatorNote:)` for Duplicate Scene; `init(id:name:cues:position:)` checks a note is
   already normalized.
3. `show.json`: optional cue key `note`, written only when set; read leniently (`StoredNote`), warnings
   `droppedNotes(n)` (not text) and `shortenedNotes(n)` (normalized text differs or was cut). Contract
   [contracts/show-cue-note.md](contracts/show-cue-note.md).
4. App: `ShowCoordinator.setOperatorNote` (refused while locked, saves, applies nothing), Duplicate Scene passes the
   note; `ShowEditorView` shows a note line, offers Add/Edit Note… (More… dialog, context menu, VoiceOver action; hidden
   while locked) and reads the note in the row's VoiceOver value; new `CueNoteView` sheet (TextEditor, counter, Save
   disabled over the limit).
5. Isolation guard: `scripts/check_compliance.py` refuses `operatorNote`/`ShowCueNote` in output, diagnostics and report
   sources (allow-list by folder: only `Packages/ShowControl`, the show editor views, `ShowCoordinator` and tests may
   name it). App acceptance test proves the absence at run time.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: Foundation (package), SwiftUI/Observation (app); existing `ShowCoordinator`, `SceneLock`
**Storage**: the existing `show.json` (optional cue field); no UserDefaults keys
**Testing**: XCTest — ShowControl package tests (host, Linux), app unit/acceptance tests and one UI test on
"SHOW12 iPhone 17" (iOS 27.2)
**Target Platform**: iOS/iPadOS 26+
**Performance Goals**: none beyond the existing editor; note normalization is O(n) on ≤ 500 characters
**Constraints**: test budgets (owner rule 7); type-check budgets (300 ms bodies); Linux build of ShowControl
**Scale/Scope**: ≤ 256 cues × 500 characters ≈ 128 K characters worst case, inside the 1 MiB show-file limit
(500 characters × up to 4 bytes × 256 = 512 KB plus JSON escaping; checked in research D4)

## Constitution Check

| Principle | Check |
|---|---|
| I Public APIs only | SwiftUI `TextEditor`, Foundation only. Pass |
| VI Modular boundaries | Rules in `ShowControl` (pure); UI in the app; no output module learns of notes. Pass |
| VII Real-time audio safety | Nothing on the audio path. Pass |
| X Evidence-based quality | Package round-trip tests, app isolation test, UI test; device check left `{device}`. Pass |
| Privacy constraints | Notes stay in the app container and the user's own backups; never in output, diagnostics, OSC or logs; compliance rule added. Pass |

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/ShowControl/Sources/ShowControl/ShowCueNote.swift        new: rules
Packages/ShowControl/Sources/ShowControl/ShowCueList.swift        cue field, setOperatorNote, insert
Packages/ShowControl/Sources/ShowControl/ShowDocument.swift       `note` key, warnings
Packages/ShowControl/Tests/ShowControlTests/ShowCueNoteTests.swift new
Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupCueNoteTests.swift new (backup round trip)
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift              setOperatorNote, duplicate
Apps/projectM-iOS/Views/ShowEditorView.swift                      row line, actions, sheet
Apps/projectM-iOS/Views/CueNoteView.swift                         new: editor sheet
Apps/projectM-iOS/Tests/CueNoteAcceptanceTests.swift              new: editing, lock, live-output isolation
Apps/projectM-iOS/UITests/CueNoteUITests.swift                    new: add a note, see the indicator
scripts/check_compliance.py (+ test_scripts.py)                   SHOW-012-R11 rule
```

**Structure Decision**: existing packages and app; one new model file, one new view, new tests.

## Complexity Tracking

None.
