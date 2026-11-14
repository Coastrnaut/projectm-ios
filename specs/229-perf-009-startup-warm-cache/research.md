# Research: PERF-009 Startup warm cache

- **PERF-009-D1 What is safe to cache.** Decision: only bundle-derived data — the prepared bundled preset library
  and the native pipeline binary archive. Rationale: both are pure functions of the app bundle, the OS and the GPU,
  so they carry no personal data and can be keyed exactly. Rejected: the user's imported presets (user data,
  PRE-012 already reads them each launch), thumbnails (PRE-001 has its own key-checked cache), ANGLE/projectM
  program binaries (need ANGLE's blob-cache hooks or engine changes; Constitution VIII; SC-104 warm-up covers
  switches).
- **PERF-009-D2 Key.** Decision: `appVersion`, `build`, `osVersion`, `gpuFamily`, `formatVersion`,
  `contentHash`, all compared for equality; the first differing field is reported. Rationale: any one of them can
  change compiled output or the snapshot layout. Rejected: file dates (not content), build number alone (development
  builds reuse it).
- **PERF-009-D3 Content hash.** Decision: SHA-256 (CryptoKit on Apple, `PortableSHA256` on Linux, same digest as
  FILE-008's `MediaContentHash`) of the input bytes: index + packs files; for pipelines, every shader source constant
  whose pipelines use the archive (`FlatShapePass.shaderSource`, `CompositorShaders.archivedSources`). Rationale:
  exact, cheap with hardware hashing.
- **PERF-009-D4 Second guard for shaders.** Measured on the Mac host (probe, 2026-11-14): a pipeline whose function
  differs from what the archive holds is a miss — Metal's lookup key includes the function hash ("Unable to find
  function ... in binary archives") — and a damaged archive file is refused by `makeBinaryArchive` ("invalid
  format"). So even an entry that slipped past the key could not serve a stale shader; the key check means the
  archive is not even opened. Adding pipelines to an archive loaded from a file and serializing it keeps the old and
  the new ones (probe).
- **PERF-009-D5 Where the archive is used.** Decision: `FlatShapePass` (native spectra) and
  `CompositorShaders.pipeline` (every compositor render pipeline). Layer sources with their own libraries, bloom and
  compute pipelines keep today's path (follow-up if device numbers show value). A process-wide
  `NativePipelineArchive.shared` (lock-protected) is set by the app; when absent, pipelines are made exactly as
  before. Rationale: two call sites cover the pipelines built when a native or compositor visual first appears;
  minimal edits in files other agents touch.
- **PERF-009-D6 Hit/miss without double compiles.** Decision: with a loaded archive, first try
  `makeRenderPipelineState(descriptor:options: .failOnBinaryArchiveMiss)`; on success count a hit; on failure make it
  normally and queue the descriptor. Queued descriptors are added (`addRenderPipelineFunctions`) and the archive
  serialized only on `writeBack()` when the scene leaves the foreground, off the main actor. Rationale: the render
  path never pays an extra compile; hits are counted, not timed.
- **PERF-009-D7 Library snapshot format.** Decision: a little-endian binary snapshot ("PMWS", format 1): packs as
  JSON, then per preset id, name, author, source, path, hash, folder parts, flash rules and the folded search key as
  length-prefixed UTF-8, then the archive order as indices. The home tree and lookup table are rebuilt (linear).
  Rationale: avoids JSON parsing, sorting and `folding(options:)` per preset; length checks make truncation a
  decode error (damaged). Rejected: Codable binary plist (slower than JSON decoding in Swift), caching the home
  tree (recursive, cheap to rebuild).
- **PERF-009-D8 Store layout and safety.** Decision: `<name>.bin` + `<name>.key.json` (schema 1: key, payload byte
  count, payload SHA-256); payload written first (atomic), key last, so a crash leaves a payload with no key (miss)
  or an old key with a new payload (checksum mismatch → damaged). A folder that is a link is refused (unavailable);
  payloads over 64 MB are damaged without reading. Entry names are `[a-z0-9-]` only.
- **PERF-009-D9 Measurement.** Decision: launch mode `perf009` (in `AutomationRunner.launchModes`) with
  `PROJECTM_WARMCACHE=cold` clearing the store before the library load; one sample per launch in
  `Documents/perf009.json`: `{cache, libraryOutcome, archiveOutcome, chooserMs, libraryReadyMs, libraryLoadMs}`.
  `run_device_tests.py warmstart` alternates cold and warm (10 each) and prints medians per label. Signposts
  "WarmStart library" and "WarmStart pipeline archive" intervals (Points of Interest, private values). No QA-010
  threshold change before device numbers exist.
- **PERF-009-D10 Clear Caches.** `Library/Caches` is the FILE-010 cleanable Caches root, so the store is emptied
  with it; nothing needs adding. An archive already open in memory may be written again at the next background,
  which is correct cache behaviour (it is still keyed).
