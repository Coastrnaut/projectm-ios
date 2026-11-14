# Contract: PRE-016 preset overrides

## C1 — `PresetTextOverlay` (PresetLibrary, public, pure)

```swift
public enum PresetTextOverlay {
    /// Each allowed parameter's value as the engine reads `bytes` (first occurrence; default if absent).
    public static func originalValues(_ bytes: Data) -> [PresetOverrideParameter: Double]
    /// `bytes` with each override applied (research PRE-016-D2). Empty overrides → `bytes` unchanged.
    public static func apply(_ overrides: [String: Double], to bytes: Data) -> Data
    /// "1.05", "0.95", "1", "-0.1" — 4 decimals, POSIX, trailing zeros trimmed.
    public static func valueText(_ value: Double) -> String
}
```

Guarantees: input never mutated; unknown keys in `overrides` ignored; values re-clamped; output with
no overrides is byte-identical.

## C2 — `PresetOverridesFile` / `PresetOverrideStore` (PresetLibrary, public)

Document as in data-model.md. `decode` throws `.newerVersion(v)` or `.unreadable`; lenient body.
Store: `init(directory:write:)`, `fileName = "overrides.json"`, `unreadableFileName =
"overrides.unreadable.json"`, `set(_:_:for:) throws(PresetOverrideError) -> Double`,
`remove(_:for:) throws -> Bool`, `reset(_:) throws -> Bool`, `prune(_:) throws -> Bool`,
`overrides(for:) -> [String: Double]`.

## C3 — Backup (LibraryBackup)

- `LibraryFolders.overridesFileName = "overrides.json"`, `overridesFile`.
- `LibraryBackupFormat.overridesPath = "collections/overrides.json"` (optional, accepted by the reader).
- `LibraryContents.presetOverrides: PresetOverrideMap?`; `LibraryRecords` key `preset-overrides`.
- `LibraryRestoreSection.overrides`; entries `overrides/<preset id>`; `LibraryRestorePlan.presetOverrides`
  (nil when unchanged); staged into `PresetCollections/overrides.json`.
- `LibraryEraseInventory` Collections count + presets with overrides.

## C4 — App UI

- Row menu item "Adjust Parameters…" (`adjustPresetParameters`), for unlocked playable presets.
- Sheet `presetOverrides`: per parameter a slider (`.accessibleParameter`, identifier
  `presetOverride.<key>`), a value label `presetOverrideValue.<key>` reading "<current>" and an original
  label "Original <value>", per-row reset `presetOverrideReset.<key>` (only when overridden), the button
  "Reset to Original" (`presetOverridesResetAll`), Done (`presetOverridesDone`), and the note "Adjustments
  set starting values. The preset's own code may still change them."
- Announcements (library lane): "<Label> set to <value> for <preset>.", "<Label> restored for <preset>.",
  "<preset> restored to its original values."; refusals announce the error message.
