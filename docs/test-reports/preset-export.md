# Test report: PRE-014 Bulk preset export

Spec: `specs/012-pre-014-bulk-preset-export/`. Branch `feature/pre-014`, Mac Studio, Xcode 27.2,
iOS 27.2 simulator "iPhone 18 Pro". 2026-11-12. Simulator results are not device evidence
(Constitution X); sharing to Files on D1-D3 is task T25 of the final device phase.

## Acceptance ("Round-trip archive preserves IDs and metadata without network")

`UserPresetArchiveTests.testRoundTripPreservesIDsMetadataAndTexts` builds a library through
`UserPresetLibrary` (an import with a license line and an author from the file name, an import
with an emoji name and a warning, an edited copy of an Included preset), exports it with
`UserPresetLibrary.export`, reads the file back with `UserPresetArchiveReader` and compares, for
every preset: id, name, author, author-from-file-name flag, original file name, origin,
`rightsVerified`, license lines, warnings, `duplicateOf` (including the pack's statement),
imported and modified dates, SHA-256, git blob hash, size and the text bytes. All equal. The
record PRE-013 would store (`ExportedUserPreset.userPreset()`) equals the stored record with the
state set to waiting, and passes the store's well-formedness rule.

Without network: `NoNetworkingTests` scans LocalPortability's sources and the export files of
`PresetLibrary` for networking API names (none); `python3 scripts/check_compliance.py` is OK.

## Format

- Stored ZIP (no compression), UTF-8 names, CRC-32, no extra fields or comment, entries
  `presets/<uuid>.milk` sorted by id, then `manifest.json`. Golden archive SHA-256
  `ad40f883ea014fc822430605bb5646e565a6a39eacd154bf70357daa0d133794` (2 presets, fixed dates):
  `testGoldenArchiveHash`; identical input gives identical bytes (`testSameInputGivesTheSameBytes`).
- Interoperability (T13), golden archive written with
  `EXPORT_FIXTURE_OUT=… swift test --filter testWriteFixtureForInteroperability`:
  - `unzip -t`: "No errors detected in compressed data", 3 entries;
  - Python `zipfile`: `testzip()` → `None`; every entry method 0, flag 0x0800, mode 0644,
    "made by" Unix, date 2027-01-15 08:00:00;
  - the manifest matches the schema's keys, required fields, patterns and constants (a Python
    key check; the `jsonschema` module is not installed on this Mac).

## Refusals (T20: every case in contract §3-4 has a test)

| Refusal | Test |
|---|---|
| not a ZIP, random bytes | `StoredZipTests.testRefusesNonZipData`, `UserPresetArchiveTests.testGarbageIsRefusedWithoutCrashing` |
| truncation at every length | `StoredZipTests.testEveryTruncationIsRefusedWithoutCrashing`, `UserPresetArchiveTests.testTruncatedArchiveIsRefused` |
| flipped byte (CRC-32) | `StoredZipTests.testFlippedDataByteFailsTheChecksum`, `UserPresetArchiveTests.testFlippedTextByteFailsTheChecksum` |
| compression, encryption, data descriptors | `StoredZipTests.testRefusesCompressionEncryptionAndOtherOptions` |
| archive comment, ZIP64 | `testRefusesAnArchiveComment`, `testRefusesZIP64Markers` |
| local and central headers disagree | `testRefusesHeadersThatDisagree` |
| overlapping, out-of-bounds entries | `testRefusesOverlappingEntries`, `testRefusesOutOfBoundsOffsets` |
| too many entries, oversize entry (before reading it), per-name limit, total size | `testRefusesTooManyEntries`, `testRefusesAnOversizeEntryBeforeReadingIt`, `testPerPathLimitOverride`, `testRefusesAnArchiveOverTheTotalLimit`, `PortableArchiveTests.testRefusesTooManyFiles`, `testRefusesAnOversizeManifest` |
| `../x`, `/x`, `\`, `C:` names; case-only duplicates; non-UTF-8 names | `StoredZipTests.testRefusesUnsafeNamesInTheArchive`, `testRefusesNamesThatDifferOnlyInCase`, `testRefusesNamesThatAreNotUTF8`, `ArchivePathTests`, `UserPresetArchiveTests.testUnsafePathsAreRefused` |
| missing or malformed manifest, wrong format, newer version | `PortableArchiveTests.testRefusesAnArchiveWithoutAManifest`, `testRefusesMalformedManifests`, `testRefusesAnotherFormat`, `testRefusesANewerVersionWithItsOwnError`, `UserPresetArchiveTests.testNewerAndForeignFormatsAreRefused` |
| unlisted, missing, duplicate-listed files; length and SHA-256 mismatch | `PortableArchiveTests.testRefusesUnlistedAndMissingFiles`, `testRefusesMismatchesAndDuplicateListings` |
| wrong path for an id, text not matching its hashes, duplicate ids, invalid records, unreferenced files, more than 1,000 presets | `UserPresetArchiveTests.testAPresetPathMustBeItsOwnIDsPath`, `testTextThatDoesNotMatchItsHashesIsRefused`, `testDuplicateIDsAndTextsAreRefused`, `testOriginAndDuplicateOfMustAgree`, `testFilesNoPresetUsesAreRefused`, `testTooManyPresetsAreRefused` |
| copy of a full-library preset; `rightsVerified = true` (ADR-0008) | `testCopiesOfFullLibraryPresetsAreRefused`, `testRightsClaimsAreRefused` |

## What an export leaves out (ADR-0008)

`UserPresetExportTests` (9): a library with an import, an Included copy, a pack copy edited while
unlocked, a second pack copy, a quarantined file and a waiting preset. Locked or unlocked, the
plan lists exactly the import and the Included copy and counts 2 full-library copies, 1
quarantined, 1 waiting; an export asked for every id (and one that does not exist) writes exactly
those two and its summary names every group. A stored text that no longer matches its record, a
write failure after 0, 1 or 3 writes, and a missing folder each fail with no file left; the store
is byte-identical after an export. 1,000 small presets: import plus export 7.1-7.2 s on the Mac
host (S6, indicative).

## App (simulator)

- `UserPresetExportAppTests` (8): plan and exclusion words; the archive of the selection is
  readable and carries the app version; the summary is announced; closing the share sheet deletes
  the file and its folder (S5); a second export replaces the first; leftovers are deleted at
  launch; a failed export shares nothing; a newer record makes Export unavailable.
- `UserPresetExportUITests` (2): import a preset, My Presets → Export…, the row starts selected,
  Select None disables Export, Select All enables it, Export shows the summary and the system
  share sheet (screenshot kept: "projectM-iOS Presets 2026-11-12, ZIP Archive · 1 KB", Save to
  Files); the archive copied by the DEBUG hook starts with `PK\3\4` and contains the manifest,
  the name, the license line and the preset text. At the accessibility XXXL size the row and the
  Export button are reachable.

Diagnosis during the runs: at XXXL the "My Presets" row on the library home can sit half under the
bottom edge after a swipe; a tap at its centre then lands on the home indicator and nothing opens.
This failed `UserPresetExportUITests.testExportSheetAtTheLargestTextSize` and PRE-015's
`UserPresetEditingUITests.testTheEditorAtTheLargestAccessibilityTextSize` once each in run 1 (the
app was not at fault; the hierarchy shows the row at y 796-951 on an 874-point screen). Both tests
now retry until My Presets is open, as PRE-012's `UserPresetsUITests` already did.

## Commands and results

| Command | Result |
|---|---|
| `swift test --package-path Packages/LocalPortability` (twice) | 51 tests, 0 failures, both runs |
| `swift test --package-path Packages/PresetLibrary` (twice) | 194 tests, 2 skipped (PRE-012 corpus: packs not checked out; the interoperability writer without its variable), 0 failures, both runs |
| app unit tests (`-only-testing:projectM-iOSTests`), runs 1-3 | 116 tests each, 1 failure each: the known environmental `PresetTests.testBundledIncludedScopeMatchesRelease1_0` (needs the full library) |
| `UserPresetsUITests`, `UserPresetEditingUITests`, `UserPresetExportUITests` (8 tests) | run 1: 6 passed, the two XXXL tests failed (diagnosis above); runs 2 and 3 after the retry fix: 8 of 8 passed |
| `xcodebuild test` of LocalPortability and PresetLibrary on the iOS 27.2 simulator (as CI does) | 51 and 194 tests (2 skipped), 0 failures; the golden hash holds on iOS too |
| `python3 scripts/check_compliance.py` | OK |
| `python3 scripts/validate_docs.py` | OK |
| `python3 scripts/test_scripts.py` | 97 tests, OK (1 skipped) |

The red runs are recorded in `specs/012-pre-014-bulk-preset-export/tasks.md`.

## Not verified here

- Linux: the packages are written for it (Foundation only, no CryptoKit) but were not built on
  Linux on this Mac; CI's `host-tests-linux` job runs them.
- Sharing on a device, Save to Files, AirDrop, and the iPad popover: final device phase (T25).
- The red run of the UI test (T19) was not recorded before the view was written.
