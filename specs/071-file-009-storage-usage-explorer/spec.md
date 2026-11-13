# Feature Specification: FILE-009 Storage Usage Explorer

**Feature Branch**: `feature/file-009` (spec directory `071-file-009-storage-usage-explorer`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement FILE-009 (Storage usage explorer) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Show storage consumed by media,
caches, recordings and user scenes." Acceptance, verbatim: "Totals agree with fixture directory sizes
within file-system overhead." P1, effort M, depends on SCN-001."

Identifiers in this feature carry the roadmap ID: requirements `FILE-009-R1…`, success criteria
`FILE-009-S1…`, tasks `FILE-009-T01…`. Other features are cited by their own IDs: MED-001 (photo),
MED-002 (video), SCN-002 (scene autosave), PRE-007 (collections), PRE-012 (user presets), AUD-001
(imported audio), REC-003 (recordings), REC-012 (share copies), FILE-001 (scene archive export),
PRE-014 (preset export), REC-015 (disk-space check), FILE-010 (cache cleanup), FILE-011 (local data
erase), FILE-005 (backup).

## Baseline: what the app keeps on disk (audit of 2026-11-13, commit `c6e5875`)

| Store | Folder | Kind | Who removes it today |
|---|---|---|---|
| MED-001 photo | `Library/Application Support/Photos` | User media | Remove Photo |
| MED-002 video | `Library/Application Support/Videos` | User media | Remove Video |
| SCN-002 autosave | `Library/Application Support/Scenes` | User scene | Overwritten on save |
| PRE-012 user presets | `Library/Application Support/UserPresets` | User presets | Delete preset |
| PRE-007 collections | `Library/Application Support/PresetCollections` | User presets | Delete collection |
| AUD-001 imported audio | `Library/Application Support/AudioLibrary` | User media | Delete track |
| REC-003 recordings | `tmp/Recordings` | Temporary | Moved to Photos; leftovers removed at launch |
| REC-012 share copies | `tmp/Sharing` | Temporary | Removed at launch |
| FILE-001 scene archive export | `tmp/SceneArchiveExport` | Temporary | After sharing |
| PRE-014 preset export | `tmp/PresetExport` | Temporary | After sharing |
| System caches (shader cache) | `Library/Caches` | Cache, system-managed | The system, under storage pressure |
| Settings and everything else | rest of the app container | Other | n/a |

The app writes nothing to `Library/Caches` itself; the texture pool (PERF-004), shader pipelines and
the preset archive's decompressed chunks live in memory. SHOW-001 shows are being built in parallel and
are not on this branch (follow-up in Scope). Bundled presets live in the signed app bundle, outside the
data container, and are not counted.

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which number does the screen show for a file, its length or the space it occupies? → A: The space
  it occupies (allocated blocks), because that is what frees up when it is removed and what the
  system's iPhone Storage shows; content bytes are measured too and are what the tests compare exactly.
  "Within file-system overhead" is defined as: per regular file, space used ≤ content bytes + one 4 KiB
  block (sparse or compressed files may use less). Applied to FILE-009-R3 and FILE-009-S1.
- Q: Should the screen show the device's free space next to the app's usage? → A: No. Showing free space
  would need a new privacy-manifest reason (Disk space 85F4.1, "display to the person") for little
  value; the system's iPhone Storage already shows it. The app keeps only its existing reason E174.1
  (REC-015). Applied to FILE-009-R8.
- Q: Should the screen offer delete or clear buttons now? → A: No. FILE-010 owns cache and intermediate
  cleanup and FILE-011 owns erasing user data; the temporary folders (Recordings, Sharing) are already
  emptied at launch by their owners, and the Photos, Videos, presets and audio screens already offer
  removal. The Storage screen is read-only. Applied to FILE-009-R7.
- Q: What does "caches" mean on disk? → A: The app's `Library/Caches` folder. The app writes nothing
  there itself; the system keeps compiled shader caches there and may purge them. In-memory caches
  (texture pool, shader pipelines, preset archive chunks) take no disk space and are not shown.
  Applied to the baseline and FILE-009-R2.
- Q: What happens when a folder is too deep or too large, or cannot be read? → A: The walk stops at depth
  32 and at 100,000 entries per category, skips unreadable folders, shows the sizes counted so far, and
  adds the note "Some files could not be counted; sizes may be higher." Applied to FILE-009-R4 and
  FILE-009-R6.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See what the app's data takes up (Priority: P1)

A performer whose device is nearly full opens Settings › Storage and sees, per category, how much space
the app's own data takes (Photos, Videos, Scenes, Presets, Imported audio, Recordings, Shares and
exports, Caches, Other app data) and a total, so they know what to remove.

**Why this priority**: The row's observable behavior.

**Independent Test**: Seed known files into each category's folder, open the screen, read each value.

**Acceptance Scenarios**:

1. **Given** fixture files in every category, **When** Storage opens, **Then** each category shows its
   size and the total equals the sum of the categories.
2. **Given** a category with no files, **When** Storage opens, **Then** it shows "Zero KB".
3. **Given** the screen is open, **When** a file is added to Recordings and Refresh is tapped, **Then**
   Recordings and the total grow and no other category changes.

### User Story 2 - Totals agree with the files on disk (Priority: P1)

The numbers are exact for the bytes stored and honest about file-system overhead.

**Why this priority**: The row's acceptance: "Totals agree with fixture directory sizes within
file-system overhead."

**Independent Test**: A fixture tree with known sizes (many small files, nested folders, a sparse file,
an empty folder, a symbolic link to a folder outside) is measured and compared with the sizes written.

**Acceptance Scenarios**:

1. **Given** the fixture tree, **When** it is measured, **Then** the content bytes equal the bytes
   written exactly, and the space used differs from them by no more than the documented overhead bound.
2. **Given** a symbolic link to a large folder outside the tree, **When** it is measured, **Then** the
   folder behind the link is not counted and never read.
3. **Given** a tree deeper or larger than the walk limits, **When** it is measured, **Then** the walk
   stops at the limit and the result says it is incomplete.

### User Story 3 - Measuring never gets in the way (Priority: P2)

Measuring runs in the background; leaving the screen or refreshing again stops the previous count.

**Independent Test**: Cancel a measurement over a large injected tree; it stops without a result.

**Acceptance Scenarios**:

1. **Given** a measurement is running, **When** the person leaves the screen or taps Refresh, **Then**
   the earlier measurement stops and only the newest result is shown.

### Edge Cases

- A category folder that does not exist yet: zero, not an error.
- A category folder that is itself a symbolic link, or resolves outside the app container: not walked;
  counted as zero.
- A folder that cannot be read: skipped; the result is marked incomplete.
- Hard links to one file in two folders: counted twice (the app never creates hard links).
- Files that change while measuring: each file is counted with the size seen when it was listed.
- Very large counts: sizes are 64-bit; the formatter shows up to terabytes.

## Requirements *(mandatory)*

### Functional Requirements

- **FILE-009-R1**: Settings MUST offer a Storage screen listing nine categories in a fixed order —
  Photos, Videos, Scenes, Presets, Imported audio, Recordings, Shares and exports, Caches, Other app
  data — each with a formatted size, followed by a total equal to their sum.
- **FILE-009-R2**: Each category MUST be measured from the folders the baseline table names, taken from
  the same definitions the stores use; "Other app data" is everything else in the app's data container,
  excluding the category folders.
- **FILE-009-R3**: Measurement MUST count regular files only, with two numbers per file: content bytes
  (the file's length) and space used (the blocks the file system allocated). The screen shows space used.
- **FILE-009-R4**: Measurement MUST never follow symbolic links, never walk a folder outside the app
  container, and stop at depth 32 and at 100,000 entries per category walk, reporting the result as
  incomplete when a limit is reached or a folder cannot be read.
- **FILE-009-R5**: Measurement MUST run off the main thread, MUST stop when cancelled, and a newer
  request MUST cancel an older one; no progress is shown beyond a busy indicator.
- **FILE-009-R6**: The screen MUST offer Refresh, MUST show "Some files could not be counted; sizes
  may be higher." when the result is incomplete, and MUST give each row an accessibility label and value (category and size).
- **FILE-009-R7**: The screen MUST NOT delete anything. Clearing caches belongs to FILE-010, erasing
  user data to FILE-011; temporary folders are already emptied at launch by their owners.
- **FILE-009-R8**: Measurement MUST NOT read file dates or the free or total space of the volume
  (privacy manifest: no new required-reason API use).
- **FILE-009-R9**: The measuring logic MUST be plain Swift behind a replaceable directory reader, so it
  is tested on the Mac host and on Linux; nothing is sent off the device.
- **FILE-009-R10**: Debug builds MUST offer a fixture seed for UI tests (known sizes under a separate
  fixture container, and a way to add one more recording file).

### Key Entities

- **Storage category**: one of the nine, with a title and its folders.
- **Category usage**: content bytes, space used, file count.
- **Storage report**: the usages per category, the totals, and whether the walk was complete.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FILE-009-S1**: For the fixture tree (at least 200 small files, nested folders, a sparse file, an
  empty folder, a link to outside), content bytes equal the bytes written exactly, and space used per
  file is at most its content bytes plus one 4 KiB block (a sparse file uses less than its length
  where the file system reports allocation; the Linux lane reports none and checks content bytes only).
- **FILE-009-S2**: Category mapping: a file placed in each baseline folder (redirected to a temporary
  container) is counted in exactly its category and in no other; the total equals the sum.
- **FILE-009-S3**: The link to outside is never listed; depth and entry limits stop the walk exactly at
  the limit and mark the report incomplete.
- **FILE-009-S4**: On the simulator, the Storage screen shows the seeded sizes, and after adding a
  recording fixture and refreshing, Recordings and the total grow while the others stay the same.
- **FILE-009-S5**: Unit tests run in about 1-2 s each (at most 10 s), each suite in under a minute, the
  UI test in under 30 s.

## Assumptions

- APFS allocates in 4 KiB blocks on every supported device; the overhead bound uses that size and is a
  test constant, not read from the volume (reading it would need a disk-space API).
- Measuring a few thousand files takes well under a second on a device; limits (depth 32, 100,000
  entries per walk) are far above what the app writes.

## Scope

| In this row | Later rows / follow-ups |
|---|---|
| Measuring, nine categories, Storage screen, Refresh, fixture seed, tests | FILE-010 clears caches and intermediates from this screen |
| | FILE-011 erases selected user data |
| | SHOW-001 shows get a category when they land |
| | Device check on D1 with real media (`{device}` task, left open) |
