# Contract: content-addressed media folder (FILE-008)

`ContentAddressedMediaFolder(directory:, extensions:)` in LocalPortability. All methods are synchronous,
thread-safe (one lock per folder path) and throw only where stated.

| # | Operation | Contract |
|---|---|---|
| M1 | `intern(_ source: URL, as id: UUID, consumingSource: Bool) throws -> URL` | Hashes `source` streaming; if `<sha>.<ext>` exists with equal size, no payload is written (a consumed source is deleted); otherwise the source is moved (consumed) or copied to the payload name. Then the registry maps `id` to it (replacing any earlier entry for `id`). Returns the payload URL. A failure before the registry write leaves no reference. `ext` must be one of `extensions`. |
| M2 | `resolve(_ id: UUID) -> URL?` | A legacy `<id>.<ext>` file if present, else the registered payload if it exists; nil otherwise. Never a path outside the folder. |
| M3 | `references() -> [UUID]`, `payloadName(of:)`, `sharesPayload(_:_:)` | Registry state plus legacy identifiers. |
| M4 | `release(_ ids: Set<UUID>)` | Removes the entries and any legacy files of those ids, then deletes payloads left without a reference. |
| M5 | `releaseOthersSharing(payloadOf:keeping:)` | Used by the stores: releases every reference sharing a payload except the kept ids. |
| M6 | `trim(payloadOf:keeping:limit:)` | Keeps at most `limit` (32) references per payload, releasing the oldest except `keeping`. |
| M7 | `prepare()` | Removes `.incoming-*` files and legacy files that are the same file (resource identifier) as their registered payload. Reads no file content. |
| M8 | `reconcile() -> ReconcileReport` | Registers every legacy file (link or copy to the payload name, then registry), then deletes unreferenced payloads and stray non-store files of payload shape. Idempotent. |
| M9 | `usage() -> MediaFolderUsage` | `references`, `payloads`, `logicalBytes` (sum over references), `physicalBytes` (sum over payloads). |
| M10 | `logicalFiles() -> [String: URL]` | `<UUID>.<ext>` → file, for every resolving identifier (FILE-005 backup reader). |
| M11 | `fault` hook | Called before each step (`placePayload`, `writeRegistry`, `removeSource`, `deletePayload`, `linkLegacy`); a throw aborts like a crash. Tests only. |

## Store behaviour (app)

- S1 `PhotoStore.stage` / `VideoStore.stage`: sanitized copy at `.incoming-<UUID>.<ext>`, then M1 consuming it.
- S2 `adopt(staged)`: M1 of the staged payload into this folder (consuming), then nothing else.
- S3 `makeCurrent(x)`: set the key; if the previous current shares x's payload, keep it; else M4 on the previous id and every id sharing its payload; then M6.
- S4 `remove()`: M4 on the current id and every id sharing its payload; clear the key(s).
- S5 `discard(x)`: M4 on x unless x is current.
- S6 `knownIDs()`: M3, used for scene availability.
