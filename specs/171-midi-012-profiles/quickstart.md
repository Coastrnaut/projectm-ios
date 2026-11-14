# Quickstart: MIDI-012 MIDI Mapping Profiles

1. Package: `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDIProfileTests`
   — the every-kind round trip is byte-identical and ordered; every malformed fixture is refused.
2. App: `xcodebuild test-without-building … -only-testing:projectM-iOSTests/MIDIProfilesCoordinatorTests` on the
   feature simulator — save → export → import → apply leaves `settings.midi.mappings` byte-identical; one Undo restores
   the previous list; the Settings erase removes the file and a backup omits it.
3. UI: `-only-testing:projectM-iOSUITests/MIDIProfilesUITests` — Save, then Apply another profile (under 30 s).
4. Device (`{device}`): on D1 with a controller, save a profile, export it to Files, import it on D2, apply, and move
   each mapped control once.
