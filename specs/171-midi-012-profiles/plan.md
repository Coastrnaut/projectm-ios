# Implementation Plan: MIDI-012 MIDI Mapping Profiles

**Branch**: `feature/midi-012` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/171-midi-012-profiles/spec.md`

## Summary

Named, verbatim snapshots of the stored MIDI mapping list, kept in one local file, exported and imported as `.pmmidi`
JSON documents, and applied back as one Undo step. Same split as MIDI-001 to MIDI-011: pure, Linux-testable code in
`Packages/PerformanceControl/Sources/PerformanceControl/MIDI/`, a thin app layer.

Pure model (`MIDI/MIDIProfile.swift`, new):

- `MIDIProfile` (id, name, lines, optional `link: Int32`), `MIDIProfileLimits` (32 profiles, 512 lines, 256 bytes per
  line, 60-character names, 128 KB import, 4 MB store file).
- `MIDIMappingLineKind.classify(_:)`: control change, note trigger, CC button, real time, scene, unread (research
  MIDI-012-D3).
- `MIDIProfileDocument`: `encode(name:lines:)` → sorted-key JSON; `decode(_:)` → name and lines or a
  `MIDIProfileImportError` (format, version, size, line count, line length, control characters) (D2, D4).
- `MIDIProfileReport`: counts by kind, unread lines, the duplicate's name; spoken summary.
- `MIDIProfileList`: the store's value model (save current with "Profile <n>", rename, delete, add import with a free
  name, link, `inUse(current:)`, `suggestion(listed:current:)`), and its file codec (`MIDIProfileStoreFile`, version 1).
- `MIDIProfileFileStore`: reads and atomically writes `<directory>/profiles.json`; an unreadable or newer file is
  reported and never overwritten (D5).

App:

- `MIDIMappingCoordinator`: `otherLines` (lines no list reads, kept after the known lines, MIDI-012-R7);
  `storedLines`; `replaceLines(_:announcement:)` (verbatim write, reload of the three lists, released held keys, learn
  cancelled, one Undo step); Undo becomes a snapshot of the stored lines, restored verbatim (D6).
- `MIDIProfilesCoordinator` (new, `Coordinators/MIDIProfilesCoordinator.swift`): rows, Save Current, Apply, Rename,
  Delete, Link, Export (temporary `.pmmidi` + file mover, removed afterwards), Import (security-scoped read, bounded),
  messages and `.midi` announcements through the mapping coordinator's announcer.
- `MIDIProfilesSection` (new, `Views/MIDIProfilesSection.swift`) in `MIDIMappingsView` after the status section;
  rename alert, delete confirmation, link menu, file mover and importer on the section.
- `AppCoordinator`: one line creating the profiles coordinator; the UI-test reset removes the profiles folder.
- FILE-011: `LibraryErasePolicy.midiProfilesFolderName = "MIDIProfiles"` in `folders(.settings)`; FILE-005 does not
  list it (D7).

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/profiles.md](contracts/profiles.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PerformanceControl (MIDI-003-008 line formats), LibraryBackup (FILE-011 policy), SwiftUI
`fileMover`/`fileImporter`. No new package, framework or network API.

**Storage**: `Application Support/MIDIProfiles/profiles.json` (new file, versioned); `settings.midi.mappings`
(existing key). No new UserDefaults key.

**Testing**: package `MIDIProfileTests` (every-kind round trip through store file and document, byte-identical and
ordered; malformed and oversized refusals; names; list operations; suggestion; Linux shape); app
`MIDIProfilesCoordinatorTests` (save → export → import → apply → stored lines byte-identical; apply is one Undo step;
unknown lines kept after an edit; unreadable store not overwritten; erase policy); UI `MIDIProfilesUITests` (Save,
then Apply another, under 30 s). Package `LibraryBackup` existing erase tests.

**Target Platform**: iOS 26.5+ / iPadOS (app); package also macOS host and Linux.

**Performance Goals**: none beyond UI responsiveness: files are at most a few hundred KB and read on the main actor
only on user action and on first open of the section.

**Constraints**: owner rule 7 test budgets; Xcode 26 type-check budget (small view bodies, typed closures).

**Scale/Scope**: ≤ 32 profiles × ≤ 512 lines.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: Foundation, SwiftUI file mover/importer. |
| VI Modular boundaries | Pass: model and codec in the package; UI and file access in the app. |
| VII Real-time audio safety | Pass: nothing on the MIDI receive or audio path changes. |
| X Evidence-based quality | Pass: acceptance proven by package and app tests; device check is a `{device}` task. |
| Security (untrusted imports) | Pass: size checked before reading, strict validation, no execution, refusal messages. |
| Privacy | Pass: no device names stored; the link (system unique number) is local only, never exported or backed up (ADR-0038 Decision 8 honoured). |

Post-design re-check: unchanged, no violations.

## Project Structure

```text
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIProfile.swift          (new)
Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIProfileStore.swift     (new)
Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIProfileTests.swift       (new)
Packages/LibraryBackup/Sources/LibraryBackup/LibraryErasePolicy.swift                  (Settings folder)
Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator.swift                            (other lines, replace, undo)
Apps/projectM-iOS/Coordinators/MIDIProfilesCoordinator.swift                           (new)
Apps/projectM-iOS/Views/MIDIProfilesSection.swift                                      (new)
Apps/projectM-iOS/Views/MIDIMappingsView.swift                                         (section)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                                    (two lines)
Apps/projectM-iOS/Tests/MIDIProfilesCoordinatorTests.swift                             (new)
Apps/projectM-iOS/UITests/MIDIProfilesUITests.swift                                    (new)
```

## Complexity Tracking

None.
