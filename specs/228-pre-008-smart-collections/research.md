# Research: PRE-008 Smart Collections

- **PRE-008-D1 Storage beside, not inside, collections.json.** A new optional field in `collections.json` would be
  dropped by an older build re-saving the file; a version bump would make older builds treat all manual collections
  as unavailable and rewrite PRE-007 golden fixtures. A separate `smart-collections.json` (as `tags.json`,
  `overrides.json`) isolates both. Rejected: version 2 of the collections file.
- **PRE-008-D2 Condition shape `{kind, values}`.** One uniform shape lets unknown kinds round-trip byte-for-byte
  in meaning (kind string and values kept). Values are OR within a condition; conditions combine by the mode.
- **PRE-008-D3 Membership by set algebra.** Each known condition maps to a set of listed preset IDs (tag index
  sets, a source → IDs map, the energy and colour filters, favorites); All intersects, Any unions; unknown kinds are
  skipped; no applicable condition → empty. Then `alphabeticalListing` orders, and a pass drops repeated IDs and
  repeated non-empty hashes (keeping the first). Deterministic for equal inputs.
- **PRE-008-D4 Scope reuse.** Smart IDs are `smart-<UUID>` and the coordinator merges smart memberships into the
  `collections` map given to `PresetLibrary.members(of: .collection(id))`; storage, stepping and fallback reuse
  PRE-007 code. No new `PresetScope` case (other features switch over it).
- **PRE-008-D5 Backup record.** `collections/smart-collections.json` added without a backup format change (as
  PRE-003 and PRE-016); restore merges by ID: new → add, identical → keep, clash → Replace takes the backup's,
  Keep both / Skip keep the device's; the result is capped at 100.
- **PRE-008-D6 Migration path.** Same as `PresetCollectionsFile`: versions 0…current pass the FILE-007 schema;
  older documents go through pure `Data → Data` steps (none in production yet; tests inject one); newer →
  unavailable; anything else → set aside as `smart-collections.unreadable.json`.
