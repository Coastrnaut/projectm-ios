# Contract: PERF-009 warm cache

- **W1** An entry is returned only if its key file parses (schema 1), every key field equals the caller's key, the
  payload exists, is at most `maxPayloadBytes`, has the stored byte count and the stored SHA-256.
- **W2** A stale or damaged entry is deleted (both files) when found and reported with its reason; the caller
  rebuilds and stores again.
- **W3** `WarmStartLoader.load` runs `build` only on non-hit or on a decode failure (reported `damaged-decode`);
  a store write failure never fails the load.
- **W4** The store touches only `<folder>/<name>.bin|.key.json|.tmp`; a folder that is a symbolic link makes it
  `unavailable` (nothing read or written).
- **W5** The library entry (`preset-library`, format 1, gpu `none`) hashes `PresetIndex.json` then
  `PresetPacks.json`; its warm value equals the cold value (presets, packs, home, archive order, search).
- **W6** The archive entry (`native-pipelines`, format 1) hashes the archived shader sources in order and carries
  the GPU family; it is opened only on a hit; pipelines made through `NativePipelineArchive.makeRenderPipeline`
  are served from it when present, otherwise made normally and queued; `writeBack()` adds the queued ones and
  commits payload then key.
- **W7** Clear Caches (FILE-010) removes the folder's contents.
- **W8** No user data, identifiers or UserDefaults keys are stored.
