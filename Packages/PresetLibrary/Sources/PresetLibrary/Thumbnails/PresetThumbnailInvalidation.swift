// PresetThumbnailInvalidation.swift — roadmap PRE-002 (specs/144-pre-002-thumbnail-invalidation;
// data-model "Rules"): which index entries a preset change or the launch listing makes stale. Pure
// selection over the index plus file removal, so the cache actor stays small and this is tested on
// Linux. Only the selected entries are touched: every other entry keeps its file, ID and date.
import Foundation

extension PresetThumbnailIndex {
    /// Stable IDs of `presetID`'s entries whose content hash is not `keepingContentHash` (all of
    /// them when it is nil: the preset left the library).
    public func staleIDs(presetID: String, keepingContentHash: String?) -> [String] {
        entries.compactMap { (id: String, entry: Entry) -> String? in
            entry.presetID == presetID && entry.contentHash != keepingContentHash ? id : nil
        }
    }

    /// Stable IDs of entries whose preset is not in `listing` (preset ID → current content hash) or
    /// is listed with another hash.
    public func unlistedIDs(_ listing: [String: String]) -> [String] {
        entries.compactMap { (id: String, entry: Entry) -> String? in
            listing[entry.presetID] == entry.contentHash ? nil : id
        }
    }

    /// Removes `ids` from the entries and deletes their files (safe names only); returns how many
    /// entries were removed. A file that is already gone is not an error.
    @discardableResult
    mutating func removeEntries(_ ids: [String], in directory: URL, fileManager: FileManager = .default) -> Int {
        var removed = 0
        for id in ids {
            guard let entry = entries.removeValue(forKey: id) else { continue }
            removed += 1
            if Self.isSafeFileName(entry.file) {
                try? fileManager.removeItem(at: directory.appendingPathComponent(entry.file))
            }
        }
        return removed
    }
}
