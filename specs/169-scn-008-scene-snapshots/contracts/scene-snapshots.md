# Contract: scene snapshots (SCN-008)

**N1 Encoding.** The document gains an optional key `snapshots`, written only when non-nil:
```json
"snapshots": [{"name": "S1", "values": {"effect.bloom.intensity": {"kind": "continuous", "value": 0.2},
                                        "effect.bloom.radius": {"kind": "continuous", "value": 0.05}}}]
```
Entries are written exactly as stored (canonical JSON key order).

**N2 Decoding.** Missing → nil. Not an array, or an entry that is not an object → `malformed` (the file is refused, as for `triggers`). More than 64 entries → `tooMany`. Otherwise every entry is kept verbatim.

**N3 Reading.** `SceneSnapshotEntry.read(entries)` → `(snapshots: [SceneSnapshot?], issues)`: per position; nil and `invalidSnapshot` at `$.snapshots[i].<key>` for a missing/invalid `name`, `values` not an object, more than 64 values, or a malformed value; positions ≥ 16 → nil and `invalidSnapshot` at `$.snapshots[i]`.

**N4 Validation.** `validate(registry:)` adds N3's issues and `unknownSnapshotParameter` at `$.snapshots[i].values.<id>` for each ID the registry does not know (usable snapshots only). All warnings.

**N5 Round trip.** decode → encode is byte-identical; a document without `snapshots` keeps its bytes; live state and capture carry the list unchanged.

**N6 Editing.** `SceneSnapshotEditing.adding(name:values:to:)` refuses at 16 usable+unusable positions (`limitReached`), an invalid name (`invalidName`) or a duplicate (`duplicateName`). `renaming(at:to:in:)` changes only `name`. `removing(at:from:)` removes the entry. `nextDefaultName(in:)` = "Snapshot N", smallest unused N ≥ 1.

**N7 Recall plan.** See data model. The app writes `plan.writes` whose value differs from the current one through `ParameterInspectorTargets`, then records one undo step "Recall <name>" when anything was written.
