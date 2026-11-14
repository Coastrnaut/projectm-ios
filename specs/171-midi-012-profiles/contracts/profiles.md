# Contract: MIDI-012 Profiles

## P1 Package (`PerformanceControl`)

- `MIDIProfileDocument.encode(name:lines:) -> Data` and `decode(_ data: Data) throws(MIDIProfileImportError) -> (name: String, lines: [String])`.
  Errors: `.empty`, `.tooLarge`, `.notAProfile`, `.newerVersion(Int)`, `.missingName`, `.tooManyLines(Int)`,
  `.lineTooLong(index)`, `.controlCharacters(index)`; each has a `message` for the user.
- `MIDIProfileList`: `profiles`, `add(name:lines:link:) throws`, `saveCurrent(_:) throws -> MIDIProfile` ("Profile <n>"),
  `rename(id:to:)`, `delete(id:)`, `setLink(_:for:)`, `uniqueName(_:)`, `profile(id:)`,
  `inUse(_:current:) -> Bool` (UTF-8 equal), `suggestion(listed:current:) -> MIDIProfile?`; store codec
  `encoded() -> Data`, `init(decoding:) throws`.
- `MIDIProfileFileStore(directory:)`: `load() -> MIDIProfileList` with `readError`, `write(_:) throws`.
- `MIDIProfileReport(lines:existing:)` with `summary`.

## P2 App

- `MIDIMappingCoordinator.storedLines`, `replaceLines(_:announcement:)` (one Undo step, verbatim), `otherLines`.
- `MIDIProfilesCoordinator`: `rows`, `saveCurrent()`, `apply(id:)`, `rename(id:to:)`, `delete(id:)`, `link(id:to:)`,
  `prepareExport(id:)` → `exportFile` (temporary `.pmmidi`), `exportFinished()`, `importFile(at:)`, `message`,
  `suggestion`.
- Announcements (`.midi` lane): "Saved MIDI profile <name>.", "Applied MIDI profile <name>.", "Imported MIDI profile
  <name>. <report>", refusals ("Could not import: <reason>").

## P3 UI (accessibility identifiers)

- `midiProfileSaveCurrent`, `midiProfileImport`, row `midiProfile.<name>` (label "<name>, <n> mappings[, in use]"),
  `midiProfileApply.<name>`, `midiProfileMore.<name>` (Rename…, Export…, Link, Delete…), `midiProfilesMessage`,
  `midiProfileSuggestion`.
