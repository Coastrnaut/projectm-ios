# Contract: Archive Checksums (FILE-002)

Extends PRE-014's `contracts/preset-archive.md` §3 and FILE-001's `contracts/scene-archive.md` §4.

## C1 Written

Every entry except `manifest.json` has a record `{path, sha256, byteCount}` in the manifest's `files`
array: `sha256` = lowercase hex SHA-256 of the stored bytes, `byteCount` = their length. Format version
unchanged (scene archive 1).

## C2 Verified on read, in this order; the first failure refuses the whole archive

1. ZIP structure, then each entry's CRC-32 → `zip(.checksumMismatch(path))`.
2. Manifest header and record list (format, version, count).
3. Per record, in manifest order: safe path → `unsafePath`; well-formed digest and size →
   `invalidRecord`; unique → `duplicateListing`; present → `missingFile`; size → `lengthMismatch`;
   SHA-256 → `checksumMismatch`.
4. No entry without a record → `unlistedFile`.

## C3 Import ordering (app)

`SceneArchiveService.importArchive` reports `.verified` only after C2 and FILE-001's scene checks pass,
and no `.staged`, `.adopted` or `.madeCurrent` step happens without it. On any refusal: zero steps,
stores byte-for-byte unchanged, staging folder removed.

## C4 Limit

Checksums give integrity, not authenticity: an archive whose file, record and CRC-32 were all changed
consistently passes C2 (FILE-001's content checks still apply). No signature exists in version 1.

## C5 Incremental hasher

`PortableSHA256.Hasher().update(a).update(b)…finalize()` == `PortableSHA256.hex(a + b + …)` for every
split.
