# Feature Specification: PRE-014 Bulk preset export

**Feature Branch**: `feature/pre-014` (spec directory `012-pre-014-bulk-preset-export`)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Implement PRE-014 (Bulk preset export) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Export user-owned presets with a manifest and checksums." Acceptance, verbatim: "Round-trip archive preserves IDs and metadata without network." Dependencies: PRE-012 (integrated); ADR-0008's PRE-014 export decision is binding. Honor the repository constitution."

**Roadmap row**: PRE-014, priority P1, effort M, depends on PRE-012
(`docs/FEATURE_ROADMAP_AUTONOMOUS.md`, PRE table). Later rows that will read or share this
archive are out of scope here: PRE-013 (bulk import, which will reuse the archive reader),
FILE-001 (portable scene archive), FILE-002 (checksums), FILE-003 (dry run), FILE-005 (backup),
FILE-007 (schema validator).

**ID convention**: requirements are `PRE-014-R1…`, success criteria `PRE-014-S1…`, tasks
`PRE-014-T01…`. `PRE-012-…` cites `specs/008-pre-012-preset-import-validation/spec.md`;
`PRE-015-…` cites `specs/010-pre-015-user-preset-duplication/spec.md`. FR-068 (no networking)
and FR-106 (the purchase boundary) cite features 001 and 002.

**Binding decision**: ADR-0008, "Decision for PRE-014 (export)": a copy of a bundled preset is
exported only when its source is an Included preset; copies whose source is in a pack that the
purchase unlocks are left out of every export, edited or not, and the export summary says how
many were left out and why. Exported copies keep their origin (`duplicateOf`), `rightsVerified =
false` and the pack's statement.

## What already exists (audit of HEAD `56fe170`, 2026-11-12)

| Area | What HEAD does | Evidence | Gap |
|---|---|---|---|
| User presets | Imported files (PRE-012) and copies of built-in presets (PRE-015) are stored by content hash with a versioned record (version 2): stable id `user/<uuid>`, name, author guess, file name, hashes, size, dates, state (waiting, playable, quarantined), warnings, license lines, origin, `duplicateOf`, `rightsVerified`. | `UserPresetStore.swift`, `UserPresetsFile.swift`, `UserPresetModel.swift` | No way to take them off the device. |
| Copies awaiting the unlock | A copy of a locked-pack preset is listed apart and never handed out while the library is locked (PRE-015-R8). | `UserPresetLibrary.awaitsUnlock` | Export must leave all locked-pack copies out, even when unlocked (ADR-0008). |
| Files in and out | One `.milk` file in through the system Files picker (PRE-012). Diagnostics export (feature 001) is user-initiated and local. | `UserPresetsView.fileImporter`, `DiagnosticsExporter.swift` | No archive writer or reader; Foundation on iOS has no public ZIP writer. |
| Checksums | SHA-256 and git blob SHA-1 in plain Swift (Linux-testable). | `ContentHash.swift` | No CRC-32 (needed by ZIP). |
| Networking | Forbidden in the app outside the OSC folder (FR-068 as amended, `check_compliance.py`). | ADR-0008 | Export must not need it. |

## Clarifications

### Session 2026-11-12

Answered under the standing delegation (owner rule 4, best judgement; recommended option first,
no owner question needed). Each answer is the conservative, local-first choice.

- Q: Which presets can be exported? → A: Playable user presets only: imported presets and copies
  of Included presets that passed the checks. Waiting (unchecked) presets, quarantined files,
  presets held after a failed save, and every copy of a locked-pack preset (locked or unlocked
  now, edited or not; ADR-0008) are left out, and the summary counts each group with its reason.
- Q: Archive container? → A: A standard ZIP file with every entry stored (no compression), written
  and read by the app's own small, bounded code with CRC-32 and SHA-256. Foundation offers no
  public ZIP writer on iOS, the presets are small text files, third-party dependencies are not
  allowed, and a stored ZIP opens in Files, Finder and every unzip tool. Apple Archive (`.aar`)
  was rejected: it is not readable on Linux (where the packages are tested) or in common tools.
- Q: What does the manifest carry? → A: The format name and version, the app version, the export
  time, a file list (relative path, SHA-256, byte length) and, per preset: stable id, name,
  author and whether it was guessed from the file name, the original file name, origin,
  `duplicateOf`, `rightsVerified`, license lines, warnings, hashes, size, and the imported and
  modified dates. Never the state of checks on this device, entitlements, purchase data, device
  names or absolute paths.
- Q: Where do preset texts go inside the archive? → A: `presets/<uuid>.milk`, built from the
  stable id alone; nothing from a user-chosen name becomes a path.
- Q: How does the file leave the device? → A: Only through the system share sheet that the user
  opens with Export (Save to Files, AirDrop, Mail are the user's choice). The archive is written
  to a private temporary folder first and deleted when the share sheet closes, whether it
  finished or was cancelled, and at the next launch if the app ended meanwhile.
- Q: Does this feature import archives? → A: No import UI (that is PRE-013). The reader and the
  manifest validation are built and tested here as library code, because the acceptance is a
  round trip.
- Q: What does the reader refuse? → A: The whole archive, with a reason, when anything is wrong:
  a newer or unknown format, a malformed manifest, a checksum or length mismatch, an unsafe path
  (absolute, `..`, backslash, drive letter, control characters, duplicates that differ only in
  case), more entries or bigger entries than the limits, a truncated or overlapping archive,
  compressed or encrypted entries, a file the manifest does not list, a preset whose content hash
  does not match, a copy of a locked-pack preset, or `rightsVerified = true`. Partial reads are
  PRE-013's decision.
- Q: Limits? → A: At most 1,000 presets (the My Presets limit), each at most 512 KiB (the import
  limit), a manifest of at most 4 MiB (the record limit), so an archive is bounded by about
  516 MiB; the reader checks every limit before it reads the bytes it limits.
- Q: Is the output reproducible? → A: Yes. The same presets, app version and export time give
  byte-identical archives (entries sorted by id, sorted JSON keys, the export time as every
  entry's time), so tests can compare golden hashes.
- Q: Selection? → A: The Export sheet lists every exportable preset, all selected; the user can
  deselect some, select all or none. Export is disabled with nothing selected.
- Q: File name? → A: `projectM-iOS Presets <yyyy-MM-dd>.zip` (local date), no device or user name.
- Q: (clarify pass) When is the summary shown? → A: As soon as the archive is written, before the
  share sheet opens: it is announced to VoiceOver and shown as text at the top of the Export sheet;
  the sheet stays open under the share sheet so the summary is still readable after sharing.
- Q: (clarify pass) Can Export run during an import, a duplicate or another export? → A: No.
  Export is disabled while an import, a duplicate or an export runs, and Import is disabled while
  an export is written; the library actor serializes the reads anyway.
- Q: (clarify pass) Which app version goes into the manifest? → A: The short version and the
  build, as `"1.1 (2)"`; it is informational only and never used to accept or refuse an archive.
- Q: (clarify pass) Is anything logged? → A: No preset names, ids or paths are logged; only the
  outcome kind (exported, failed) may appear in the existing unified log category.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Export my presets as one archive (Priority: P1)

In My Presets the user taps Export, sees the presets that can be exported (all selected), keeps
or changes the selection and taps Export. The app writes one archive and opens the system share
sheet, from which the user saves it to Files or sends it wherever they choose. A summary says how
many presets were exported and what was left out and why.

**Why this priority**: It is the roadmap's observable behavior: "Export user-owned presets with a
manifest and checksums."

**Independent Test**: Import two presets, export them, and inspect the produced file: a ZIP with
`manifest.json` and two preset texts whose checksums match the manifest.

**Acceptance Scenarios**:

1. **Given** two playable imported presets, **When** the user exports all, **Then** the archive
   holds both texts byte for byte and a manifest listing both with their ids, names, hashes and
   sizes, and the share sheet appears.
2. **Given** the user deselects one preset, **When** they export, **Then** only the selected
   preset is in the archive.
3. **Given** the share sheet is closed (finished or cancelled), **Then** the temporary archive
   no longer exists on the device.
4. **Given** no exportable presets, **Then** Export is disabled and the sheet explains why.

---

### User Story 2 - The archive reads back unchanged, with no network (Priority: P1)

An exported archive can be read back by the app's archive reader: every preset's id, name,
author, origin, `duplicateOf`, rights flag, license lines, dates and text are identical to what
was exported, and nothing in the path needs a network.

**Why this priority**: It is the roadmap's acceptance: "Round-trip archive preserves IDs and
metadata without network."

**Independent Test**: Export a fixture library with an imported preset, an edited copy of an
Included preset and a preset with license lines; read the archive back; compare every field and
byte.

**Acceptance Scenarios**:

1. **Given** an exported archive, **When** it is read back, **Then** each preset's id and
   metadata equal the stored record and each text equals the stored bytes.
2. **Given** the export and read code, **Then** it uses no networking API (compliance check).

---

### User Story 3 - Paid content and unsafe content never leave in an export (Priority: P1)

Copies of presets from packs the purchase unlocks are never exported, even when the library is
unlocked or the copy was edited; quarantined files and unchecked presets are not exported either.
The summary says how many were left out and why.

**Why this priority**: The purchase sells access to the packs (ADR-0007, ADR-0008); an export
must never hand that content on. Quarantined files failed a safety check.

**Independent Test**: A library with an imported preset, an Included copy, a locked-pack copy
(unlocked), a quarantined file and a waiting preset: the archive holds exactly the first two.

**Acceptance Scenarios**:

1. **Given** the library is unlocked and holds an edited copy of a pack preset, **When** the user
   exports all, **Then** the copy is not in the archive and the summary says "1 copy of a preset
   from the full library" was left out because it is part of the purchase.
2. **Given** a quarantined file and a waiting preset, **Then** neither is in the archive and the
   summary names both groups.

---

### User Story 4 - A damaged or hostile archive is refused safely (Priority: P2)

The reader refuses an archive that was altered, cut off or crafted to escape its folder, with a
plain reason, and never crashes.

**Why this priority**: PRE-013 will read archives from anywhere; the reader built here must be
safe first.

**Independent Test**: Flip one byte, truncate, name `../x` or `/x`, exceed the entry count or an
entry size: each is refused with its reason.

**Acceptance Scenarios**:

1. **Given** an archive with one flipped byte in a preset text, **Then** it is refused for a
   checksum mismatch.
2. **Given** a manifest naming `../x` or an absolute path, **Then** it is refused as unsafe.
3. **Given** more entries than allowed or an entry larger than allowed, **Then** it is refused
   before the oversize bytes are read.
4. **Given** a truncated archive, **Then** it is refused.

### Edge Cases

- Two presets with the same name: paths use ids, so both are kept; names are metadata only.
- A name, author or license line with emoji, quotes or non-Latin text: exported verbatim as UTF-8
  JSON and read back identical.
- A stored text that no longer matches its record (disk damage): the export stops with "The
  presets could not be exported. Nothing was shared." and no partial file is shared.
- Not enough space to write the archive: the same message; the partial file is deleted.
- The saved record is from a newer app version: Export is unavailable, like Import.
- The app ends while the share sheet is open: the temporary folder is emptied at the next launch.
- A preset is removed while the Export sheet is open: it is skipped and counted as no longer
  available.
- An archive from a later format version: refused as "made by a newer version of the app".

## Requirements *(mandatory)*

### Functional Requirements

**Choosing and exporting**

- **PRE-014-R1**: My Presets MUST offer Export, which opens a sheet listing every exportable
  preset with all selected, Select All and Select None, the count selected, a footer naming what
  cannot be exported and why, and an Export button disabled when nothing is selected.
- **PRE-014-R2**: Exportable means playable, not held, and either imported by the user or a copy
  whose source is an Included preset (pack `included`, no unlock needed). Every copy whose source
  needs the library unlock is excluded whatever the entitlement and edits (ADR-0008); quarantined,
  waiting and held presets are excluded.
- **PRE-014-R3**: Export MUST write one archive containing the selected exportable presets and
  then present the system share sheet with that file only. Nothing leaves the device unless the
  user completes a share action.
- **PRE-014-R4**: The archive MUST be written in a private temporary folder of the app and
  deleted when the share sheet closes (completed or cancelled); leftovers from an earlier launch
  are deleted at the next export or launch.
- **PRE-014-R5**: When the archive is written, before the share sheet opens, the app MUST show (at
  the top of the Export sheet) and announce a summary: the number exported
  and, per excluded group, the count and the reason (copies of full-library presets: part of the
  purchase, stay on this device; quarantined: failed a check; waiting: not checked yet;
  unavailable: could not be read).
- **PRE-014-R6**: If any selected preset's stored text does not match its record, or the archive
  cannot be written, the export MUST stop, delete its partial file and share nothing.

**Archive format**

- **PRE-014-R7**: The archive MUST be a ZIP file whose entries are all stored uncompressed, with
  UTF-8 names, CRC-32 per entry, no encryption, no extra fields and no comment.
- **PRE-014-R8**: The archive MUST contain `manifest.json` and one entry per preset at
  `presets/<uuid>.milk`, where `<uuid>` is the preset's stable id without its `user/` prefix.
  No other entries.
- **PRE-014-R9**: The manifest MUST carry: format `org.projectmios.user-presets`, format version
  1, app version, export time, a `files` list (relative path, SHA-256, byte length per preset
  text), and a `presets` list with, per preset: id, name, author, author-from-file-name flag,
  original file name, path, SHA-256, git blob hash, byte length, origin, `rightsVerified`,
  license lines, warnings, `duplicateOf` (copies only, with the pack's statement verbatim),
  imported date and modified date when stored.
- **PRE-014-R10**: The manifest MUST NOT contain absolute paths, device or user names other than
  text the user or the preset supplied, the check state on this device, entitlement or purchase
  data. A contract and a JSON schema MUST document it.
- **PRE-014-R11**: Identical input (presets, app version, export time) MUST give byte-identical
  archives.

**Reading back (for the round trip and PRE-013)**

- **PRE-014-R12**: A reader MUST return every preset's metadata and text from an archive of this
  format, or refuse the whole archive with a reason.
- **PRE-014-R13**: The reader MUST refuse: a non-ZIP or truncated file; compressed, encrypted or
  multi-disk entries; local and central headers that disagree; overlapping or out-of-bounds
  entries; a CRC-32, SHA-256 or length mismatch; an unsafe path (empty, absolute, `.` or `..`
  components, backslash, colon, control characters, longer than 255 bytes, more than 8 levels);
  two names equal ignoring case; an entry the manifest does not list, or a listed file that is
  missing or that no preset uses; more than 1,001 entries; an entry over its limit (512 KiB per preset, 4 MiB manifest);
  an archive over the total limit; an unknown format; a newer format version (its own reason); a
  malformed manifest or preset record; duplicate ids or texts; a git blob hash that does not match
  the text; a `duplicateOf` whose source needs the unlock or is not Included; `rightsVerified =
  true`.
- **PRE-014-R14**: The reader MUST check sizes and counts before reading the bytes they limit and
  never crash on any input.
- **PRE-014-R15**: Export and read MUST use no networking API and run fully offline.

**General**

- **PRE-014-R16**: The archive container and checksum code MUST be reusable by later archive
  features (FILE-001, PRE-013) without depending on presets.
- **PRE-014-R17**: Every control and the summary MUST have accessibility labels and work at all
  Dynamic Type sizes.
- **PRE-014-R18**: While the saved record is from a newer app version, Export MUST be
  unavailable. Export MUST be disabled while an import, duplicate or export runs, and Import while
  an export is written.
- **PRE-014-R20**: Preset names, ids and paths MUST NOT be logged by the export.
- **PRE-014-R19**: The privacy policy MUST say that an export leaves the device only through the
  user's own share action.

### Key Entities

- **Preset archive**: one ZIP file: `manifest.json` plus preset texts.
- **Manifest**: format, version, app version, export time, file list, preset list.
- **Exported preset**: the portable part of a user preset record (no device check state).
- **Export summary**: exported count plus excluded counts by reason.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-014-S1**: Round trip: for a fixture library of imported presets and Included copies, 100%
  of ids, names, authors, origins, `duplicateOf` values, rights flags, license lines, warnings,
  dates and texts read back identical, offline.
- **PRE-014-S2**: 0 copies of locked-pack presets, quarantined files or waiting presets appear in
  any archive, whatever the entitlement.
- **PRE-014-S3**: 100% of the tamper cases (flipped byte, `../x`, absolute path, too many entries,
  oversize entry, truncation, unlisted entry, newer version) are refused with their reason and no
  crash.
- **PRE-014-S4**: Exporting the same input twice gives the same SHA-256 for the archive.
- **PRE-014-S5**: After the share sheet closes, 0 temporary archive files remain.
- **PRE-014-S6**: Exporting 1,000 small presets finishes in under 10 seconds in the package tests
  (Mac host and simulator; indicative, device timing belongs to the final device phase).

## Assumptions

- The archive is opened by the app (PRE-013) or by standard tools; no other app is expected to
  understand the manifest.
- Sharing uses the system share sheet; which destinations exist is up to the user's device.
- Device verification (share to Files on D1-D3) waits for the final device phase (ADR-0008).
- Collections (PRE-007) are not exported: they mix built-in and user presets and belong to the
  later portable formats (FILE rows).
