# Research: PRE-015 User preset duplication

All decisions 2026-11-12, under the standing delegation (spec Clarifications).

## D1. Where the copy's bytes come from

- **Decision**: the app's `RendererPresetLoader` reads them exactly as it does to play the
  preset: Included presets from their bundle file, pack presets from `PresetArchive.bin`
  (decompressed chunk). The library actor receives the bytes and the index hash and refuses a
  mismatch (`ContentHash.gitBlobSHA1Hex`, the same hash `build_preset_index.py` records).
- **Rationale**: one read path for playing and copying; the hash check proves byte identity
  against the shipped index.
- **Alternatives**: reading the packs' source files (not in the app); copying the archive chunk
  (wrong granularity).

## D2. Lock boundary and refunds

- **Decision**: refuse duplicating a locked preset in the interface (purchase sheet) and in the
  library actor (`requiresLibraryUnlock && !libraryUnlocked`). The record stores
  `requiresLibraryUnlock` from the pack's `locked` flag at copy time. While the entitlement is
  absent, such copies are held: not playable, not editable, not in any scope, but listed.
- **Rationale**: the copy must not route around the purchase (ADR-0007); user work is never
  deleted. Storing the flag avoids depending on load order between the record and the pack
  metadata.
- **Alternatives**: deleting copies on refund (destroys user work); deriving the lock at run time
  only (a window at launch where a copy could be listed as playable before pack data arrives).

## D3. Rights and attribution

- **Decision**: `license.origin = bundledDuplicate`, `rightsVerified = false`,
  `linesFound` from the validator as for imports, and `duplicateOf.licenseStatement` = the
  pack's `license` text from `PresetPacks.json` verbatim (bounded to 1,000 characters).
  Information shows: "Duplicated from “X” in <pack>. The pack's statement: <text>. projectM-iOS
  has not verified any other rights to this preset."
- **Rationale**: ADR-0007 records the basis as an assumption, not a verified license; nothing is
  invented.

## D4. Record format: version 2

- **Decision**: `UserPresetsFile.currentVersion = 2`. Migration 1 → 2 is a pure `Data → Data`
  step that sets `schemaVersion` to 2 and changes nothing else. New fields are optional
  (`duplicateOf`, `modifiedAt`), new enum value `bundledDuplicate`.
- **Rationale**: PRE-012's v1 decoder fails on the unknown origin value and would set the whole
  record aside; it would also not hold copies of locked packs. Version 2 makes it report "saved by
  a newer version" and write nothing. The PRE-012 build never shipped (1.1 is PRE-012-free), so
  the bump costs no user a downgrade path.
- **Alternatives**: additive fields without a bump (rejected above); a separate duplicates file
  (two files to keep consistent).

## D5. Content addressing and PRE-017

- **Decision**: keep `files/<sha256>.milk`; an edit adds the new body, then repoints the record,
  then deletes the old body. PRE-017 can later keep old bodies and add a version list to the
  record without changing how bodies are stored.

## D6. Failing edits and crash safety

- **Decision**: never store an unchecked edit. The trial runs on the in-memory candidate. A
  durable `edit.json` (preset id + candidate hash) exists during the trial; found at launch it is
  removed and the user is told once; the preset is not quarantined because its stored text never
  changed.
- **Alternatives**: saving as "invalid" (the preset becomes unplayable until fixed; loses the
  last good version); quarantining on crash (punishes the good version for a bad candidate).

## D7. Repeats and names

- **Decision**: identical text already stored → refused naming the entry (PRE-012's one record per
  content hash stays). Name "<original> copy", then "copy 2", "copy 3"… against all user preset
  names, case-insensitive; the original part is shortened so the name fits 120 characters.

## D8. Editor

- **Decision**: SwiftUI `TextEditor` (UITextView underneath: VoiceOver reads and edits it,
  Dynamic Type through `.font(.system(.body, design: .monospaced))`), `TextField` for the name,
  Cancel/Save in the toolbar, `interactiveDismissDisabled` while dirty plus a confirmation
  dialog. Text decoding: UTF-8, else ISO Latin-1 with a visible note; saving writes UTF-8.
  Unchanged text (string-equal to what was opened) saves nothing.
- **Rationale**: system controls carry accessibility for free; 512 KiB is within what a
  UITextView handles; device timing is S7 `{device}`.
