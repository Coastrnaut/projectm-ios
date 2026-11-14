# Data Model: FILE-008 User Asset Deduplication

## Payload

- File `<sha256>.<ext>` in the store folder; `sha256` is 64 lowercase hex characters of the file's
  bytes; `ext` is one of the store's extensions (`png`, `jpg` for photos; `mov` for videos).
- Immutable once placed. Deleted when no reference names it.

## Reference

- `id`: canonical UUID string (the store identifier that settings, scenes and cues hold).
- `payload`: a payload file name.
- Order: registry order is age order (oldest first); at most 32 references per payload.

## Registry (`references.json`)

```json
{"format": "org.projectmios.media-references", "version": 1,
 "references": [{"id": "<UUID>", "payload": "<sha256>.<ext>"}]}
```

- At most 1 MiB; an unreadable, oversize, foreign-format or newer-version file reads as no references.
- Entries with a non-canonical id, a malformed payload name or a duplicate id are dropped on read.
- Written atomically, keys sorted.

## Legacy file

- `<UUID>.<ext>` (MED-001/002 layout, or written by a FILE-005 restore). Resolves before the registry;
  registered by `reconcile`; removed by the next `prepare` once it is the same file as its payload.

## Temporary file

- `.incoming-<UUID>.<ext>`: an import in progress; removed by `prepare`.

## State transitions (one identifier)

`absent` → (import / adopt) → `referenced` → (release, makeCurrent of other content, Remove) → `absent`
`legacy` → (reconcile) → `legacy + referenced` → (next prepare) → `referenced`
