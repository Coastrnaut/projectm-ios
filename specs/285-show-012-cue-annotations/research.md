# Research: SHOW-012 Cue Annotations

- **SHOW-012-D1 Storage**: Decision: optional cue key `note` in `show.json` v1, written only when set. Rationale: the
  SHOW-002/004/005 pattern; FILE-005 backs up the show by decode → encode, so the field travels with no backup change.
  Alternatives: separate `notes.json` keyed by cue ID (second file to back up and keep in sync; rejected).
- **SHOW-012-D2 Which exports**: Decision: stored show, FILE-005 archive and folder backup, exact restore. FILE-004
  scene import, SCN-014 scene packs and FILE-005 merge restore carry scenes only (audit: `ShowSceneImport` appends
  plain cues; `LibraryRestoreInstaller.stageShow(.merge)` installs scenes) — unchanged, as for transitions and dwells.
- **SHOW-012-D3 Normalization**: Decision: CR LF, CR, U+2028, U+2029 → LF; remove Unicode general category Cc except
  LF (tab, NUL, ESC, DEL, C1 controls); trim whitespace and newlines; count `Character`s (grapheme clusters, as
  PRE-011-D3). Format characters (Cf, e.g. ZWJ in emoji) are kept so emoji stay whole.
- **SHOW-012-D4 Size**: 256 cues × 500 characters: worst case 4-byte scalars and JSON `\uXXXX` escapes are not used
  for normal text (`JSONEncoder` escapes only controls, quotes, backslash; LF becomes `\n`). Worst realistic case
  ≈ 512 KB + labels < 1 MiB limit. A combining-mark flood can exceed it; the save then fails with the existing
  "could not be saved" message (no new rule, documented edge).
- **SHOW-012-D5 Lenient read**: Decision: non-string → dropped (`droppedNotes`), string whose normalized form differs
  (cut, controls, untrimmed) → kept normalized (`shortenedNotes`), normalized-empty → no note (counted as shortened).
- **SHOW-012-D6 Privacy guard**: Decision: a static rule plus a run-time test. The property name `operatorNote` and type
  `ShowCueNote` are distinctive; `check_compliance.py` allows them only under `Packages/ShowControl`,
  `Packages/*/Tests`, `Apps/projectM-iOS/Tests`, `Apps/projectM-iOS/UITests`, `Views/ShowEditorView.swift`,
  `Views/CueNoteView.swift` and `Coordinators/ShowCoordinator.swift`. Any other source naming it (an output,
  HUD, OSC, diagnostics or report file) fails CI.
- **SHOW-012-D7 Live-output test pattern**: Decision: follow UIX-013/OUT-005 and SHOW-007 acceptance tests: a real
  `ShowCoordinator` over a temporary store wired as `AppCoordinator.connectShow` does, a real `OSCSendCoordinator`
  with a capturing transport, `SceneHUDContent.make`, `ShowTransportCoordinator.positionText`, and an
  `ExternalDisplayViewController` window with the slot's visual; the distinctive string is searched in every
  produced string, the applied scene's bytes and the OSC datagrams. Pixel comparisons are not needed: the note never
  enters the scene document, which is the only input of recordings, Save Frame and offline export.
- **SHOW-012-D8 VoiceOver**: the row's value ends with ", note <full text>" (operator's own screen reader). No
  announcement on save ("Note saved" would be noise; the row updates).
