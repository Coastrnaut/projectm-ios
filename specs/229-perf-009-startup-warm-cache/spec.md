# Feature Specification: PERF-009 Startup warm cache

**Feature Branch**: `feature/perf-009` (spec directory `229-perf-009-startup-warm-cache`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement PERF-009 (Startup warm cache) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Cache only safe metadata and shaders for faster next launch." Acceptance,
verbatim: "Cold and warm start measurements recorded and no stale shader used." P2, effort L."

Identifiers carry the roadmap ID: requirements `PERF-009-R1…`, success criteria `PERF-009-S1…`, tasks
`PERF-009-T01…`, research decisions `PERF-009-D1…`. Other features are cited by their own IDs: SC-015 (cold launch,
feature 001), SC-101 and SC-104 (feature 002 library readiness and preset warm-up), FILE-009 (storage categories),
FILE-010 (Clear Caches), PERF-012 (performance report), QA-010 (performance thresholds).

## Baseline: what exists today (audit of 2026-11-14, commit `95142688`)

| Area | Today |
|---|---|
| Launch path | Notice → source chooser (SC-015: D1 median 80 ms process start → chooser). In parallel the preset library loads off the main thread: `PresetLibrary.load(from: .main)` decodes the 4.9 MB `PresetIndex.json` (12,847 presets) plus `PresetPacks.json`, sorts, folds a search key per preset and builds the browsing tree (SC-101: about 106 ms on D1 after feature 002's pre-sorted index). Nothing is reused between launches. |
| Shaders | The app's own Metal shaders (native spectra `FlatShapePass`, the compositor's `CompositorShaders`, layer sources, effects) are Swift string constants compiled at run time with `makeLibrary(source:)` and turned into pipelines on first use. No binary archive exists. |
| Preset shaders | projectM presets render through ANGLE's Metal backend. `PresetPrewarmer` (SC-104) warms upcoming presets in memory after a switch; ANGLE keeps its program cache in memory only. Caching ANGLE or projectM programs on disk would need engine or ANGLE changes (Constitution VIII). |
| Caches folder | FILE-009 counts all of `Library/Caches` as the Caches category; FILE-010 Clear Caches empties it (allowlisted, links never followed). Thumbnails (PRE-001), motion and colour stores already live there. |
| Measurement | AutomationRunner `sc015` (process start → chooser) and `sc101` (chooser → library ready) append samples to Documents; QA-010 judges `coldLaunchMs` from `sc015`. No mode distinguishes a launch with and without cached data. App signposts go through `DiagnosticsLog.signposter` (Points of Interest). |

## Clarifications

### Session 2026-11-14

Answered by the feature agent under owner rule 4 (best judgement, conservative and local-first), recommended
option each time.

- Q: What exactly may the warm cache hold? → A: Only data derived from the app bundle: the prepared bundled preset
  library (presets, packs, archive order, search keys) and a Metal binary archive of the app's own native shader
  pipelines (native spectra and the compositor). Not the user's imported presets, favorites, collections, tags,
  thumbnails (PRE-001 already has its own cache), settings or anything about the device owner. ANGLE/projectM preset
  programs are out of scope (R12): caching them needs ANGLE or engine changes (Constitution VIII), and SC-104's
  in-memory warm-up already covers switches.
- Q: How is the content part of the key computed? → A: SHA-256 of the exact input bytes: `PresetIndex.json` +
  `PresetPacks.json` for the library; the concatenated shader source texts of the archived modules for pipelines;
  plus a per-entry format version. Hardware-backed CryptoKit on Apple platforms, the portable SHA-256 on Linux.
  Build number or file dates alone were rejected: a development build can change the index without a new build
  number, and dates are not content.
- Q: What does "GPU family" mean in the key, and is it used for the library entry? → A: The Metal device name plus
  the highest supported Apple GPU family (for example "Apple A16 GPU/apple8"); only pipeline entries carry it, the
  library entry uses "none". A device restore or migration onto other hardware therefore never reuses an archive.
- Q: When is the pipeline archive written? → A: When the app moves to the background, only if new pipelines were
  added, written to a temporary file and committed with its key and checksum last; never on the render path. A
  device or simulator that cannot make archives reports "unsupported" and compiles as today.
- Q: How are cold and warm launches measured? → A: A new measurement-build launch mode `perf009`: an environment
  option clears the warm cache before anything reads it (cold); a launch without it is warm. Each launch appends one
  labelled sample to `Documents/perf009.json` and exits. `run_device_tests.py warmstart` alternates cold and warm
  launches (10 each by default) and prints medians. Tests use an injected clock and step counters; app launch
  phases are OSSignposter intervals. QA-010's thresholds are not changed (no new budget without device numbers).
- Q: ADR-0024 (SHD-011) forbids Metal binary archives everywhere; how does the shader cache fit? → A: ADR-0062
  amends it with one reviewed exception: only `NativePipelineArchive.swift` may open an archive, only one the app
  serialized from its reviewed module-constant shaders, only on an exact key and checksum match. Tests build their
  pipelines through the real `FlatShapePass` and `Compositor`, so no test file compiles Metal source or opens an
  archive. (Decided during implement, 2026-11-14.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A later launch reuses safe work from an earlier one (Priority: P1)

A person opens the app a second time. The preset library is ready sooner because the app reuses the library
metadata it prepared on the previous launch, and the first native visual starts without recompiling its shaders,
because the compiled pipelines were kept. Nothing about the person (favorites, imported presets, audio, settings) is
in that cache.

**Why this priority**: it is the roadmap behaviour.

**Independent Test**: load the library twice against the same cache folder with a counter on the expensive
preparation step: the first load prepares (cold), the second reuses (warm) and prepares nothing; the two libraries
are identical.

**Acceptance Scenarios**:

1. **Given** an empty cache, **When** the app launches, **Then** it prepares the library as today and stores the
   prepared form for next time.
2. **Given** a cache written by the same app build on the same system, **When** the app launches, **Then** the
   library comes from the cache, the expensive preparation is not run, and the library equals a freshly prepared
   one.
3. **Given** compiled native pipelines stored by the same build on the same system and GPU, **When** a native
   visual starts, **Then** its pipelines come from the stored archive.

### User Story 2 - A stale or damaged cache is never used (Priority: P1)

After an app update, a system update, a move to another device, or a change to the bundled presets or the app's
shader source, the cache no longer matches. The app ignores it, removes it and rebuilds it; it never draws with a
shader compiled for different source, a different system or a different GPU. A damaged cache file behaves the same
way.

**Why this priority**: it is the roadmap acceptance ("no stale shader used").

**Independent Test**: write a cache, then change one identity field at a time (app version, build, system
version, GPU family, content hash, format version) and load again: each reports stale, removes the files and
rebuilds. Truncate or alter the stored data: the load reports damaged and rebuilds.

**Acceptance Scenarios**:

1. **Given** a cache keyed to another app version, build, system version, GPU family or shader source, **When**
   loaded, **Then** it is reported stale, deleted, and the result is rebuilt from source.
2. **Given** a cache file whose checksum does not match, or that cannot be decoded, **When** loaded, **Then** it is
   reported damaged, deleted, and rebuilt.
3. **Given** Clear Caches (FILE-010), **When** it runs, **Then** the warm cache is emptied with the other caches and
   the next launch is cold.

### User Story 3 - Cold and warm launches are measured (Priority: P2)

The owner runs a launch measurement on D1 that alternates launches with the cache cleared (cold) and with the cache
kept (warm), and gets both sets of samples in one report, each sample labelled cold or warm with what the cache
did. The app's launch phases show as named intervals in Instruments.

**Acceptance Scenarios**:

1. **Given** the measurement build, **When** a launch is started with the cold option, **Then** the cache is cleared
   before anything reads it, and the sample is labelled cold with the cache outcome "miss".
2. **Given** a following normal launch, **Then** the sample is labelled warm with the cache outcome "hit".
3. **Given** a simulator rehearsal, **Then** the results are labelled "not evidence".

### Edge Cases

- The cache folder is missing, unreadable or is a link: treated as empty; nothing outside the Caches folder is
  read or written.
- The stored key file is unreadable or of an unknown format version: damaged, rebuilt.
- The payload is larger than a fixed limit: damaged (never read whole).
- Writing the cache fails (disk full): the launch continues; the next launch is cold.
- The device or simulator cannot make pipeline archives: archives are skipped; pipelines compile as today.
- A pipeline the archive does not hold: compiled normally and added to the archive for next time.
- The user's imported presets are added to the library after the cache step and are never written to it.

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-009-R1**: The app keeps a warm cache in one folder inside the Caches folder. It holds only (a) the
  prepared form of the bundled preset library metadata and (b) compiled pipelines of the app's own bundled shaders.
  It never holds user data: no favorites, imported presets, collections, settings, audio, pictures or identifiers.
- **PERF-009-R2**: Every cache entry is stored with an identity key: app version, build number, operating system
  version, GPU family (for shader entries), entry format version and a content hash of the inputs it was made from
  (the bundled index and packs files; the shader source texts).
- **PERF-009-R3**: An entry is used only when every key field equals the current one. Any difference makes the
  entry stale: it is not used, it is deleted, and the result is rebuilt and stored again.
- **PERF-009-R4**: Each entry carries the byte count and checksum of its data. A missing, truncated, oversized,
  checksum-failing or undecodable entry is damaged: not used, deleted, rebuilt.
- **PERF-009-R5**: The warm path for the library skips the expensive preparation (index decode, sort, search keys)
  and yields a library equal to a freshly prepared one; the user's presets are added afterwards exactly as today.
- **PERF-009-R6**: Pipelines for the app's native shaders are created with the stored archive attached when it is
  valid; pipelines created without a stored entry are added to the archive, which is written back when the app leaves
  the foreground (off the main thread). A pipeline whose shader source changed is never served from an archive (R2, R3).
- **PERF-009-R7**: Cache failures never block or fail a launch: every failure falls back to today's path.
- **PERF-009-R8**: Clear Caches empties the warm cache (it lies in the FILE-010 Caches category).
- **PERF-009-R9**: The app marks the launch phases (library load with its cache outcome, pipeline archive open with
  its outcome) as named signpost intervals; dynamic values are private.
- **PERF-009-R10**: The measurement build offers a launch mode that records, per launch, whether the cache was
  cleared (cold) or kept (warm), the cache outcomes, time from process start to the chooser, to the library being
  ready, and the library load time. The device runner offers a step that alternates cold and warm launches on a
  device or a simulator rehearsal and summarizes both sets.
- **PERF-009-R11**: The tests are deterministic: time comes from an injected clock, and the warm path is proven by
  counting the expensive steps, not by timing.
- **PERF-009-R12**: ANGLE and projectM preset programs are not cached on disk by this feature (Constitution VIII).

### Key Entities

- **Warm cache key**: app version, build, OS version, GPU family, format version, content hash.
- **Warm cache entry**: name, key, payload byte count and checksum, payload.
- **Load outcome**: hit, miss, stale (with the first differing key field), damaged (with the reason), unsupported.
- **Launch sample**: cold or warm, outcomes, process start → chooser, process start → library ready, library load.

## Success Criteria *(mandatory)*

- **PERF-009-S1**: In tests, 100% of key changes (each of the six fields) and damaged-entry cases are reported
  stale or damaged, remove the entry and rebuild; no stale or damaged entry is ever returned.
- **PERF-009-S2**: In tests, a warm load runs the expensive preparation 0 times and a cold load once, and both
  libraries are equal.
- **PERF-009-S3**: In tests, a pipeline created against a valid stored archive is served from it (creation that is
  told to fail on an archive miss succeeds); after a shader source change the archive is not opened.
- **PERF-009-S4**: The launch signposts exist in the app (library load and pipeline archive intervals).
- **PERF-009-S5**: On D1, cold and warm launch samples (at least 10 each) are recorded in
  `docs/test-reports/performance.md` `{device}`. Simulator numbers are recorded only as not evidence.

## Assumptions

- Cache data goes in the Caches folder, which the system may purge at any time; a purge simply makes the next
  launch cold.
- The bundled index changes only with an app build; hashing it each launch costs a few milliseconds with the
  system's hardware-backed hash and is the price of never using a stale library.
- Metal itself also keeps a per-app compiler cache; this feature does not rely on it, and its effect is part of
  what "warm" measures on a device.
