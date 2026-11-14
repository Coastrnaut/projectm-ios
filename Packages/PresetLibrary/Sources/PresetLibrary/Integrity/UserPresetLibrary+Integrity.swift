// UserPresetLibrary+Integrity.swift — roadmap PRE-018 (R2, R3, R7, R8, R14; research D1-D4, D7): the
// library check's user preset side. The inventory reads and never writes (R2); `relink` writes back only
// bytes whose checksum the record already names (MED-013 pattern); `quarantineByUser` moves a preset to
// Quarantine with the reason `movedByUser`. The actor runs all of it off the main thread.
import Foundation

public enum PresetRelinkOutcome: Sendable, Equatable {
    case restored(name: String)
    /// The bytes are not the record's (size or SHA-256 differ): nothing was written.
    case checksumMismatch
    /// The stored file is already intact.
    case notMissing
    case unknownPreset
    case unavailable
    case saveFailed
}

extension UserPresetLibrary {
    /// Each waiting or playable record (also copies awaiting the unlock): is its file intact, does its
    /// text still pass the static checks, which textures does it miss. Quarantined records are known
    /// IDs but are not read (they never play).
    public func integrityInventory(limits: PresetIntegrityLimits = .standard) -> UserPresetIntegrityInventory {
        guard let store = loaded() else { return .empty }
        guard store.availability == .available else {
            return UserPresetIntegrityInventory(entries: [], knownIDs: [], available: false)
        }
        let known = Set(store.presets.map(\.id))
        var entries: [UserPresetIntegrityEntry] = []
        var bytesRead = 0
        var incomplete = false
        for preset in store.presets where preset.state != .quarantined {
            guard entries.count < limits.maxRecords, bytesRead + preset.byteCount <= limits.maxTextBytes else {
                incomplete = true
                break
            }
            bytesRead += preset.byteCount
            entries.append(entry(for: preset, store: store))
        }
        return UserPresetIntegrityInventory(entries: entries, knownIDs: known, available: true, incomplete: incomplete)
    }

    private func entry(for preset: UserPreset, store: UserPresetStore) -> UserPresetIntegrityEntry {
        let origin: String? = preset.duplicateOf.flatMap { (copy: PresetDuplicateOrigin) -> String? in
            copy.sha256 == preset.sha256 ? copy.presetID : nil
        }
        guard let bytes = store.storedBytes(of: preset), ContentHash.sha256Hex(bytes) == preset.sha256 else {
            return UserPresetIntegrityEntry(id: preset.id, name: preset.name, fileIntact: false, libraryOriginID: origin)
        }
        let validation = MilkdropPresetValidator.validate(bytes, knownTextures: context.knownTextures)
        let textures: [String] = validation.warnings.filter { $0.kind == .missingTexture }.map(\.detail)
        return UserPresetIntegrityEntry(id: preset.id, name: preset.name, fileIntact: true, missingTextures: textures,
                                        rejection: validation.rejection?.message, libraryOriginID: origin)
    }

    /// R7: writes the stored copy back from `data` when its size and SHA-256 equal the record's.
    public func relink(_ id: String, with data: Data) -> PresetRelinkOutcome {
        guard let store = loaded() else { return .unavailable }
        guard store.availability == .available else { return .unavailable }
        guard let preset = store.preset(id: id), preset.state != .quarantined else { return .unknownPreset }
        if let stored = store.storedBytes(of: preset), ContentHash.sha256Hex(stored) == preset.sha256 { return .notMissing }
        let bytes = [UInt8](data)
        guard bytes.count == preset.byteCount, ContentHash.sha256Hex(bytes) == preset.sha256 else { return .checksumMismatch }
        do {
            try store.restoreContents(id, contents: data)
            return .restored(name: preset.name)
        } catch {
            return .saveFailed
        }
    }

    /// R6, R8: moves a waiting or playable preset to Quarantine; `detail` names the issue. False when
    /// it is unknown, already quarantined, or the change could not be saved.
    public func quarantineByUser(_ id: String, detail: String) -> Bool {
        guard let store = loaded(), let preset = store.preset(id: id), preset.state != .quarantined else { return false }
        do {
            try store.update(id) {
                $0.state = .quarantined
                $0.quarantine = PresetQuarantineReason(.movedByUser, detail: detail)
            }
            return true
        } catch {
            return false
        }
    }
}
