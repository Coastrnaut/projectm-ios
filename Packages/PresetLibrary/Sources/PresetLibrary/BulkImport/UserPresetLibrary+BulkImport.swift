// UserPresetLibrary+BulkImport.swift — the library side of a bulk preset import (roadmap PRE-013,
// specs/174-pre-013-bulk-import; PRE-013-R5, R6, R11, R13; research PRE-013-D3-D5).
//
// The importer reads, hashes and validates off this actor; only two calls run on it:
//   * `bulkImportBaseline()`: what the files are compared against (stored hashes, built-in hashes,
//     the takedown list, the shipped textures);
//   * `commitBulk(_:)`: one batch. Each draft is checked again (a preset with the same bytes may have
//     arrived since the baseline; the 1,000-preset cap), turned into a record exactly as `importFile`
//     would (PRE-012 naming, waiting for its trial), and the batch is saved through the store's staged
//     `commitImport`: all of it or none of it. Paths come only from content hashes (PRE-012-R4).
import Foundation

/// What a bulk import compares files against.
public struct BulkImportBaseline: Sendable {
    /// SHA-256 → name of every stored preset (any state).
    public var stored: [String: String]
    public var context: PresetImportContext
}

/// One file that passed every check, waiting for its batch (data-model "BulkPresetDraft").
public struct BulkPresetDraft: Sendable, Equatable {
    public var path: String
    public var fileName: String
    public var contents: Data
    public var sha256: String
    public var blobHash: String
    public var warnings: [PresetImportWarning]
    public var licenseLines: [String]
}

public enum BulkCommitResult: Sendable, Equatable {
    case added(UserPreset)
    case duplicate(name: String)
    case libraryFull
    case saveFailed
}

extension UserPresetLibrary {
    /// Nil when the library cannot be changed (a record from a newer version).
    public func bulkImportBaseline() -> BulkImportBaseline? {
        guard let store = loaded(), store.availability == .available else { return nil }
        var stored: [String: String] = [:]
        for preset in store.presets { stored[preset.sha256] = preset.name }
        return BulkImportBaseline(stored: stored, context: context)
    }

    /// Saves one batch, all or nothing; one result per draft, in order. `cap`: waiting or playable
    /// presets My Presets may hold (PRE-012-R27; smaller in tests).
    public func commitBulk(_ drafts: [BulkPresetDraft], cap: Int = PresetImportLimits.maxUserPresets) -> [BulkCommitResult] {
        var results: [BulkCommitResult] = Array(repeating: .saveFailed, count: drafts.count)
        guard let store = loaded(), store.availability == .available else { return results }
        let quarantined: Int = store.presets.filter { (preset: UserPreset) -> Bool in preset.state == .quarantined }.count
        var capacity: Int = min(cap, PresetImportLimits.maxUserPresets) - (store.presets.count - quarantined)
        var hashes: Set<String> = Set(store.presets.map(\.sha256))
        let date = now()
        var items: [(preset: UserPreset, contents: Data)] = []
        var indices: [Int] = []
        for (index, draft) in drafts.enumerated() {
            if let existing = store.preset(sha256: draft.sha256) {
                results[index] = .duplicate(name: existing.name)
                continue
            }
            guard hashes.insert(draft.sha256).inserted else {
                results[index] = .duplicate(name: "")
                continue
            }
            guard capacity > 0 else {
                results[index] = .libraryFull
                continue
            }
            capacity -= 1
            let names = UserPresetName.displayName(fromFileName: draft.fileName)
            let preset = UserPreset(id: UserPreset.idPrefix + makeID(), name: names.name, author: names.author,
                                    originalFileName: UserPresetName.cleanedFileName(draft.fileName), sha256: draft.sha256,
                                    blobHash: draft.blobHash, byteCount: draft.contents.count, importedAt: date, state: .pending,
                                    warnings: draft.warnings,
                                    license: PresetLicenseMetadata(authorFromFileName: !names.author.isEmpty, linesFound: draft.licenseLines))
            items.append((preset, draft.contents))
            indices.append(index)
        }
        guard !items.isEmpty else { return results }
        do {
            try store.commitImport(adding: items, replacing: [])
        } catch {
            return results.enumerated().map { (pair: (offset: Int, element: BulkCommitResult)) -> BulkCommitResult in
                indices.contains(pair.offset) ? .saveFailed : pair.element
            }
        }
        for (item, index) in zip(items, indices) { results[index] = .added(item.preset) }
        return results
    }
}
