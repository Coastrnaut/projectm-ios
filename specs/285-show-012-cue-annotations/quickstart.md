# Quickstart: SHOW-012 Cue Annotations

1. Package: `swift test --package-path Packages/ShowControl --filter ShowCueNoteTests` — rules, round trip, lenient read.
2. Backup: `swift test --package-path Packages/LibraryBackup --filter LibraryBackupCueNoteTests` — archive round trip.
3. App (simulator "SHOW12 iPhone 17"): `-only-testing:projectM-iOSTests/CueNoteAcceptanceTests` — editing, lock,
   duplicate, and the live-output isolation (S2).
4. UI: `-only-testing:projectM-iOSUITests/CueNoteUITests` — More… → Add Note…, type, Save, the row shows the note.
5. Checks: `python3 scripts/check_compliance.py` (SHOW-012-R11), `python3 scripts/test_scripts.py`.
6. `{device}` (D1, external display attached): add a note to a cue, step to it, confirm nothing of the note on the
   external display or in a short recording; VoiceOver reads the note on the row.
