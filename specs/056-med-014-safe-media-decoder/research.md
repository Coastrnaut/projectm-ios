# Research: MED-014 Safe Media Decoder

## MED-014-D1: Structure checks in plain Swift before ImageIO

- **Decision**: Own sniffers for PNG, JPEG and HEIF in a dependency-free target; ImageIO stays the decoder.
- **Rationale**: MED-001's test `testDamagedImagesAreRefused` documents that ImageIO decodes a PNG cut
  short with `statusComplete` and blank rows. The PNG format makes the file self-checking (chunk
  lengths, CRC-32 per chunk, IEND), so a cut or flipped file is detected exactly; the same holds for
  JPEG's EOI and segment lengths. Plain Swift runs on Linux CI and cannot itself be exploited by the
  bytes it reads (bounds-checked buffer access only).
- **Alternatives**: `CGImageSourceCreateIncremental` status (still "complete" for cut PNGs);
  `kCGImageSourceShouldCacheImmediately` with a full decode and a row check (decodes before checking,
  cannot tell blank rows from a black picture); a third-party decoder (Constitution IX; not needed).

## MED-014-D2: What each sniffer checks

- **PNG**: 8-byte signature; first chunk IHDR of length 13; width, height 1…2³¹−1; legal bit depth
  per color type (0: 1,2,4,8,16; 2: 8,16; 3: 1,2,4,8; 4: 8,16; 6: 8,16); compression 0, filter 0,
  interlace 0/1; each chunk length ≤ 2³¹−1 and ≤ remaining bytes − 12; chunk type four ASCII letters;
  CRC-32 checked when the type's first letter is upper case (critical); PLTE before IDAT; ≥ 1 IDAT;
  IEND of length 0 ends the walk (bytes after it are ignored). Missing bytes → `.truncated`, anything
  else → `.corrupt`.
- **JPEG**: SOI `FFD8`; markers walked by their 16-bit lengths (≥ 2, within the data), fill `FF`s
  skipped; SOF0-3, 5-7, 9-11, 13-15 give precision, height, width (both ≥ 1) and 1…4 components;
  SOS needs an earlier SOF, then its entropy data is scanned for the next marker (`FF00` and RSTn are
  data); EOI `FFD9` ends the walk (trailing bytes ignored). Missing EOI → `.truncated`.
- **HEIF/AVIF**: first box `ftyp` (size ≥ 16 and within the data) whose major or compatible brands
  include one of `heic heix heim heis hevc hevx mif1 msf1 avif avis` (brands that are not legible
  four-character codes → `.corrupt`; legible brands without an image brand → `.other`, ImageIO
  decides); every top-level box fits;
  `meta` (a full box) required; inside `meta/iprp/ipco` each `ispe` gives width and height; the
  largest are the header size (spec Clarifications).
- **Movie (ISO BMFF / QuickTime)**: box header = 32-bit size + type; size 1 → 64-bit size follows;
  size 0 → box extends to the end of its parent; size < header → `.corrupt`; end > parent end →
  `.truncated`. The first top-level box must have a known type (`ftyp moov mdat free skip wide pnot
  uuid meta`) else `.unrecognized`. Exactly one top-level `moov`. Container boxes descended:
  `moov trak mdia minf stbl`; `hdlr` handler type `vide` marks a video track; `stsd` (full box, entry
  count ≥ 1) first entry: size, format fourcc, then VisualSampleEntry width/height (u16 at entry
  offsets 32 and 34). Limits: 4,096 box headers in all, depth 8, 64 tracks; over → `.corrupt`.
- **Rationale**: these are exactly the fields a decoder trusts to size allocations and loops; every
  one is checked against the bytes that exist before it is used.

## MED-014-D3: Bounded work without a timer

- **Decision**: All loops advance by at least one byte (PNG ≥ 12, box ≥ 8) and stop at the data end or
  a count limit; reads are `min(requested, available)`; the movie sniffer reads at most 16 bytes per
  box header and ≤ 4 KB for `hdlr`/`stsd` entries (larger → read the prefix only). The image is
  decoded only as a thumbnail ≤ 4096 px (`kCGImageSourceCreateThumbnailFromImageAlways`,
  `ShouldCacheImmediately`), and the video probe decodes one picture ≤ 256 px.
- **Rationale**: owner constraint "time-bound by bounded work, not wall clock"; deterministic tests.

## MED-014-D4: The priority-inversion notice (MED-002 report)

- **Finding**: MED-002 saw the Thread Performance Checker's "Hang Risk / priority inversion" notice in
  `VideoStoreTests` and the video UI test: a user-initiated thread waiting on a lower-QoS thread. The
  import path runs at `.userInitiated` (`Task.detached(priority: .userInitiated)` in the coordinator)
  and blocks in two synchronous calls: `NSFileCoordinator.coordinate(readingItemAt:…)` (waits on the
  coordination machinery) and, in `VideoProbe.decodesFirstPicture`, `AVAssetReader.startReading` +
  `copyNextSampleBuffer` (waits on AVFoundation's decode threads, which run at lower QoS).
- **Decision**: (a) the first-picture check uses `AVAssetImageGenerator.image(at:)`, an async API that
  suspends instead of blocking a thread, with `maximumSize` 256 × 256 and tolerance after infinite so
  the first decodable picture is taken; (b) the coordinated picked-file reads are changed only if the
  checker attributes a warning to them; (c) the playback decode thread keeps its blocking
  `AVAssetReader` reads by design (MED-002 D1: a dedicated pull thread); if the checker still reports
  an inversion from it, it is recorded, not hidden.
- **Measured (2026-11-13, iOS 27.2 simulator, the checker's runtime warnings in the `.xcresult`)**:
  `PhotoStoreTests` + `VideoStoreTests` (15 tests) with the old probe: 2 inversion warnings (one
  attributed to `VideoStoreTests.swift`); with the new probe: 0. The store tests run the whole import
  including the coordinated read, so (b) is not a source and the stores are unchanged. Remaining: 1
  warning in `VideoLayerUITests` alone (playback), 0 in `PhotoLayerUITests` alone and 0 in
  `SafeMediaUITests` (seed writer, import, failing reader open), so it comes from (c): recorded in
  ADR-0022's amendment as a device question, not changed blind.
- **Alternatives**: lowering the import task to `.utility` (slower imports, hides rather than fixes);
  keeping `AVAssetReader` for the probe (the blocking call is the cause).

## MED-014-D5: Where the checks run

- Import: photo — `ImageSanitizer.sanitize` → `ImageIODecoder.decode` (sniff first). Video —
  `VideoProbe.check` (size → sniff → AVFoundation → first picture).
- Load: photo layer — the same decoder on its load queue. Video layer — `AVVideoFrameReader.open`
  sniffs before the first track load and before every reopen (loop, seek), so a file replaced while
  playing fails at the next open; a read error mid-file already ends the session (`.damaged`).
- A failed layer stays failed until its content changes (spec Clarifications).

## MED-014-D6: Fuzz

- **Decision**: a SplitMix64 generator with a fixed seed; 2,000+ mutations (bit flip, byte overwrite,
  truncate, duplicate a range, insert random bytes, set a length field to 0xFFFFFFFF) over valid tiny
  PNG, JPEG, HEIF-header and movie-header byte arrays built in code; each result must be a facts value
  or a `MediaSniffError` (Linux shape). On Apple platforms a smaller fuzz (≈ 300) also runs the full
  `ImageIODecoder` and asserts a picture or an `ImageImportError`.
- **Rationale**: deterministic (same seed → same cases → reproducible failures), < 1 s.

## MED-014-D7: Fixtures without checked-in media

- PNGs are assembled byte by byte (chunks with computed CRCs, an uncompressed `stored` zlib stream so
  no compressor is needed on Linux); JPEG, the valid movie and the HEIF-control come from ImageIO /
  AVAssetWriter at test time on Apple platforms; minimal movie boxes are assembled byte by byte.
