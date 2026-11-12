# Research: PRE-012 Preset import validation

Decisions D1-D12. Measurements: `.milk` files built into the app (14,604), script run 2026-11-12.

## D1. What the engine does with bad input

**Decision**: three layers (static limits, off-screen trial, durable record); see the audit table
in spec.md. **Rationale**: read from the pinned source: `PresetFileParser.cpp` (1 MiB cap, NUL
refused, `key=value` or `key value`, first key wins, `GetCode` stops at the first numbering gap),
`ProjectM::LoadPresetData` (all exceptions caught and reported through the switch-failed
callback, which `PMBridge.mm` turns into `PMEngineErrorPresetLoadFailed`),
`MilkdropPreset::Initialize` (equations are compiled and init code runs during the load; warp and
composite shaders are translated and compiled during the load), `PerPixelMesh::CompileWarpShader`
(a failing shader is dropped, not fatal), `TextureManager::TryLoadingTexture` (placeholder),
`projectm-eval/TreeFunctions.c` (`MAX_LOOP_COUNT 1048576` per loop, loops nest).
**Alternatives**: trusting the engine's own failure path only (the status quo) leaves hangs and
recursion crashes uncontained.

## D2. Limits

**Decision**: the numbers in spec Clarifications. **Measurements**: largest file 168,391 bytes
(p50 9,367; p99 25,396; p99.9 36,652); longest line 1,525 bytes; most lines 3,220; largest code
block 31,999 bytes; longest equation statement 4,891 bytes, shader statement 1,311; deepest
bracket nesting 21 (equations), 16 (shaders); every file has `[preset00]` as its first
non-version line; 0 files with NUL or other control characters; 37 files not valid UTF-8; 3,740
with CRLF; loops nested up to 4 deep. **Alternatives**: the engine's 1 MiB cap as the size limit
(no margin against the engine's own bound); rejecting nested loops (would reject built-in
presets).

## D3. Hashing without CryptoKit

**Decision**: pure-Swift SHA-1 and SHA-256 in `PresetLibrary`. The git blob id (SHA-1 of
`"blob <n>\0"` + content) is what `build_preset_index.py` writes into the index and what
`PresetBlocklist.json` holds, so duplicates of built-in presets and takedowns are matched without
reading built-in files. SHA-256 names stored files (roadmap "Local formats": `assets/<sha256>`).
**Rationale**: the package is tested on Linux in CI; CryptoKit is Apple-only. The inputs are at
most 512 KiB. SHA-1 here is an identifier that must match existing data, not a security control.
**Alternatives**: `#if canImport(CryptoKit)` (would leave the Linux tests without the import
path); adding swift-crypto (a new dependency).

## D4. Validation works on bytes

**Decision**: the validator takes `[UInt8]`, splits lines on CR/LF, and compares ASCII keys.
**Rationale**: 37 built-in presets are not UTF-8; `String(decoding:)` would repair bytes and
change offsets; byte scanning is linear and cannot be slowed by Unicode normalization.

## D5. Quarantine keeps a copy; refusals keep nothing

**Decision**: files that are not `.milk`, unreadable, empty, oversize, duplicates or on the
takedown list are refused. A `.milk` file within the size limit that fails validation or the
trial is kept in `quarantine/` with a record. **Rationale**: the acceptance check says
"quarantined"; a kept copy lets the user see what was refused and lets PRE-018 re-scan; oversize
and takedown content must not be kept at all. The quarantine folder is separate from `files/` so
no code path that plays presets can reach it.

## D6. Trial design

**Decision**: one thread per trial, fresh engine and unshared context each time, 30 frames, 10 s
limit, 512 KiB stack. **Rationale**: `PresetPrewarmer` proves a second engine on a second context
works on ANGLE's Metal backend. A fresh engine isolates trials from each other. The visible
renderer runs on the main thread (1 MiB stack on iOS); a smaller trial stack means recursion
depth that passes the trial fits on screen. **Alternatives**: reuse the prewarmer (its failures
are ignored by design and its engine is long-lived); a separate process (iOS offers no public way
for an app to run a helper process for this).

## D7. A hung trial

**Decision**: on timeout the caller gets `timedOut`, the thread is abandoned, the runner reports
`unavailable` until that thread ends (which it may never do). **Rationale**: threads cannot be
killed safely with public API; at most one abandoned thread bounds the cost to one busy core.

## D8. Durable record

**Decision**: `trial.json` `{schemaVersion, presetID, phase}` written atomically before a trial
(`trial`) or before an unproven preset's first visible load (`proving`); removed afterwards. At
`load()`, a record means the app ended inside that window: quarantine with
`interruptedDuringCheck` or `interruptedOnScreen`. **Rationale**: the only in-process defence
against a crash loop. **Trade-off**: a force-quit inside the window quarantines an innocent
preset; the user can delete it and import again.

## D9. Proving period

**Decision**: 3 s after the visible load, if the preset is still current and the renderer
presented frames in that time, mark `provenOnScreen`. Otherwise drop the record without proof.
**Rationale**: a crash in the first visible frames would otherwise repeat at every launch,
because the app restores the last preset.

## D10. User presets in the library

**Decision**: `withUserPresets`; ids `user/<uuid>`; source `user`. **Rationale**: favorites and
collections store ids only, so nothing in their formats changes (S6). A permanent id separate from
the content hash lets PRE-015/016/017 change content without changing identity.
**Alternatives**: content-hash ids (identity would change on edit).

## D11. Picker and test hook

**Decision**: SwiftUI `fileImporter` with `UTType(filenameExtension: "milk") ?? .data` plus
`.data`, single selection; the extension is checked again in the package. UI tests pass
`-uitestImportPreset <path>` (Debug builds), the route AUD-001 uses.

## D12. Takedown list at run time

**Decision**: bundle `PresetBlocklist.json` (remove its `excludes` line in `project.yml`).
**Rationale**: imports must honor the same list as the build; the file is tiny.
