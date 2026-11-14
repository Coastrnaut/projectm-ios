# Contract C1: notes.json

```json
{ "notes": { "included/Alpha.milk": "Slow build, good for intros" }, "schemaVersion": 1 }
```

- Location: `Application Support/PresetCollections/notes.json`; written atomically; sorted keys, unescaped slashes.
- FILE-007 schema `org.projectmios.preset-notes`: versions 0 (migration only) to 1, at most 8 MiB, depth 3, strings up to 16 KiB, 20,000 elements per object, no duplicate keys, strict UTF-8.
- Version newer than 1: the store is unavailable (nothing shown, nothing written, file untouched).
- Unreadable: renamed to `notes.unreadable.json` (one copy kept); notes start empty.
- Lenient body: entries that are not strings, are empty after trimming, exceed 2,000 characters, or have an empty or over-512-byte ID are dropped and counted.

# Contract C2: privacy

- No diagnostics output reads notes: PERF-012 report, CaptureLab diagnostics export, `DiagnosticsLog`, automation reports. `scripts/check_compliance.py` refuses `PresetNote`, `noteStore` or `notes.json` in those sources.
- Notes are not written to UserDefaults, logs, preset exports, scene or show packs, OSC or MIDI.
- Notes are in the FILE-005 library backup (`collections/notes.json`), a local file the user saves.

# Contract C3: UI

- Row menu "Note…" (`presetNoteAction`), VoiceOver action "Note".
- Sheet `presetNote`: text editor `presetNoteText` (label "Note"), count `presetNoteCount` ("n of 2,000"), Save `presetNoteSave`, Cancel `presetNoteCancel`, Delete Note `presetNoteDelete` (when saved), message `presetNoteMessage`.
- Row indicator `presetNoteIndicator:<name>` (symbol `note.text`, hidden from VoiceOver); row label suffix ", has note".
- Announcements on the library lane: "Note saved for <name>." / "Note removed from <name>."
