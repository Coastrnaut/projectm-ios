# Research: AUD-001 Import DRM-free audio files

Decisions are numbered `AUD-001-D1…`. Nothing here needed outside research; every API is public and
present in the iOS 26.5 and 27.2 SDKs and on macOS 15.

## AUD-001-D1 Where the library lives: Application Support

- **Decision**: `Library/Application Support/AudioLibrary/` in the app container.
- **Rationale**: private to the app, persistent, included in backups, never purged by the system.
  `Caches` and `tmp` can be purged; `Documents` is user-visible if file sharing is ever enabled.
- **Alternatives**: security-scoped bookmarks to the original (rejected: acceptance, breakage when
  the original moves); `Documents` (rejected: not app-managed).

## AUD-001-D2 Content-addressed copies, extension kept

- **Decision**: `assets/<sha256 hex>.<ext>`, where `<ext>` is the original extension lowercased and
  reduced to at most 8 ASCII letters or digits.
- **Rationale**: the roadmap's "Local formats" asks for `assets/<sha256>` with an atomic reference
  index; the hash gives duplicate detection (AUD-001-R8) for free. The extension is kept because
  the system audio decoder uses it as a type hint (MP3 in particular). The index stores the file
  name relative to `assets/`, never an absolute path, because the container path changes between
  installs and restores.
- **Alternatives**: UUID file names (no dedupe); no extension (decode risk).

## AUD-001-D3 Atomic import: temp file in the same folder tree, then rename

- **Decision**: stream the source in 1 MiB chunks into `incoming/<uuid>.<ext>`, hashing and counting
  bytes as they pass; validate the temporary copy; `moveItem` it into `assets/`; then write the
  index. `incoming/` is on the same volume, so the move is a rename.
- **Rationale**: the size limit is enforced on real bytes (a provider can report any size);
  validation runs on the app's own copy, so the source cannot change between check and use; a crash
  at any point leaves at most a file in `incoming/` or an unreferenced asset, both swept at the next
  load (AUD-001-R16).
- **Alternatives**: `FileManager.copyItem` then validate (cannot cap size while copying, no hash).

## AUD-001-D4 Index: versioned Codable JSON, atomic replace

- **Decision**: `index.json` = `{ "schemaVersion": 1, "tracks": [...] }`, encoded with sorted keys
  and ISO-8601 dates, written with `Data.write(options: .atomic)`.
- **Rationale**: the roadmap's document boundary (versioned, Codable, atomic). A probe decodes only
  `schemaVersion` first, so a newer file is recognized even if its shape changed (AUD-001-R15).
- **Recovery**: unreadable index → renamed to `index.damaged.json` (one generation kept) and
  rebuilt from the assets (AUD-001-R14). File names carry the hash, so identity survives; titles
  become "Recovered track N".

## AUD-001-D5 Validation and DRM

- **Decision**: (1) type: the URL's `contentType` resource value, else `UTType(filenameExtension:)`,
  must conform to `UTType.audio`; (2) protection: `AVURLAsset.load(.hasProtectedContent)` true →
  refused as protected; a load error is ignored and the next check decides; (3) decode:
  `AVAudioFile(forReading:)` must open, report `length > 0`, sample rate > 0, 1 or 2 channels, and
  one read of up to 4096 frames must succeed.
- **Rationale**: public APIs only; a protected file is detected and refused, never worked around
  (Constitution I). FairPlay-protected purchases also fail the decode check, so the refusal does
  not depend on the protection flag alone.
- **Not verifiable here**: no protected fixture can be generated, so the protected path is tested
  through the inspector seam, and with a real protected file only in the device phase.

## AUD-001-D6 Reading the picked file

- **Decision**: `startAccessingSecurityScopedResource()` (result ignored: it is false for
  non-scoped URLs such as test files) and an `NSFileCoordinator` read with `.withoutChanges`, both
  ended in `defer` as soon as the copy finishes.
- **Rationale**: Apple's documented pattern for URLs from the document picker; coordination lets the
  system materialize a file from a file provider. The app adds no networking code (FR-068).

## AUD-001-D7 Streaming, looping playback

- **Decision**: for a library file, `AVAudioPlayerNode.scheduleFile(_:at:completionCallbackType:
  .dataConsumed)`; the completion handler schedules the file again unless the graph was stopped.
  One schedule is queued at a time.
- **Rationale**: the reference track is 60 s and is loaded into one buffer; an imported file may be
  hours long, so it must stream (AUD-001-R20). The completion handler runs on a non-real-time
  thread owned by the player, where scheduling is allowed; a lock-protected flag stops the loop
  before `player.stop()` so no handler touches a stopped graph (Constitution VII: idempotent stop).
- **Trade-off**: a gap of a few milliseconds at the loop point is possible; acceptable for a
  visualizer and replaced by real transport in AUD-006.
- **Alternatives**: `AVAudioPlayer` (no tap), reading the whole file (memory), `AVPlayerLooper`
  (different pipeline, no mixer tap).

## AUD-001-D8 Host-testable playback graph

- **Decision**: move engine construction, tap and scheduling out of `AVInAppPlaybackBackend` into
  `InAppPlaybackGraph`, compiled wherever AVFAudio exists; the backend keeps `AVAudioSession` and
  notification handling (iOS only).
- **Rationale**: lets the macOS host run the real scheduling and tap code in AVAudioEngine's
  offline manual-rendering mode, deterministically and without audio hardware.

## AUD-001-D9 Concurrency

- **Decision**: `AudioLibrary` is an actor. Mutating operations run one at a time through an
  internal serial chain, because the inspector is `async` and actor methods are re-entrant at
  `await`.
- **Rationale**: two imports of the same content cannot both pass the duplicate check.

## AUD-001-D10 UI placement and the shared chooser

- **Decision**: `SourceChooserView` gains an optional trailing-sections view builder (default
  empty), so CaptureLab and existing call sites compile unchanged; `ImportedAudioSection` is a
  separate public view placed there by `projectM-iOS`.
- **Rationale**: FR-080's three rows stay as they are (AUD-001-R21); the harness app is unchanged.

## AUD-001-D11 Required-reason APIs and the privacy manifest

- **Decision**: use no file-timestamp or disk-space API: sizes are counted while copying, the
  import date is the clock at import, and out-of-space is detected from the write error.
- **Rationale**: no new privacy-manifest reason is needed; `scripts/check_privacy_manifest.py` on
  the built app confirms it (main session, needs the app build).

## AUD-001-D12 Privacy check on devices

- **Decision**: `scripts/run_device_tests.py` `privacy_problems` keeps flagging any audio file in
  the container except files directly inside `Library/Application Support/AudioLibrary/assets/`
  or `…/incoming/`.
- **Rationale**: the check must keep catching recorded audio anywhere else, while the user's
  imported library is allowed by AUD-001-R22.
