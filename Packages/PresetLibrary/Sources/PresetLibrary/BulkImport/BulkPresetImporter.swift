// BulkPresetImporter.swift — the per-file pipeline of a bulk preset import (roadmap PRE-013,
// specs/174-pre-013-bulk-import; PRE-013-R4-R8, R13; contract C3; research PRE-013-D3, D4).
//
// Runs off the main actor and off the library actor: listing, reading, hashing and the PRE-012 static
// checks happen here; only the baseline and each batch's commit go to `UserPresetLibrary`.
// Per file, in byte-wise path order, the first rule that applies decides its kind:
//   unsupported → too large → failed (unreadable) → invalid (empty) → duplicate (same bytes earlier in
//   this import, in My Presets, or built in) → invalid (takedown list, static checks) → draft.
// Every hashed file's SHA-256 is remembered, so a second copy of anything is a duplicate of the first.
// Drafts are saved in batches (all or nothing); a draft's kind is final only once its batch is saved.
// Cancel is checked before each file: the files already handled keep their outcome, the waiting batch
// is saved, and the rest are counted as not handled (R8).
import Foundation
import LocalPortability

public enum BulkPresetImporter {
    public static func run(_ source: BulkImportSource, library: UserPresetLibrary,
                           limits: BulkImportLimits = .standard,
                           isCancelled: @escaping @Sendable () -> Bool = { false },
                           progress: @escaping @Sendable (BulkImportProgress) -> Void = { (_: BulkImportProgress) in }) async -> BulkImportReport {
        let url = source.url
        #if canImport(Darwin)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        let name = UserPresetName.cleanedFileName(url.lastPathComponent)
        guard let baseline = await library.bulkImportBaseline() else { return .refused(name, BulkImportText.libraryUnavailable) }
        let listing = BulkImportListing.make(source, limits: limits)
        if let refusal = listing.refusal { return .refused(listing.sourceName, refusal) }

        var run = Run(listing: listing, baseline: baseline, limits: limits)
        var cancelled = false
        for index in listing.entries.indices {
            if isCancelled() || Task.isCancelled {
                cancelled = true
                break
            }
            run.handle(index)
            if run.drafts.count >= limits.batchSize { await run.flush(library) }
            progress(BulkImportProgress(handled: index + 1, total: listing.entries.count, counts: run.counts))
        }
        await run.flush(library)
        let items: [BulkImportItem] = run.items.compactMap { (item: BulkImportItem?) -> BulkImportItem? in item }
        return BulkImportReport(sourceName: listing.sourceName, total: listing.entries.count, counts: run.counts,
                                hiddenCount: listing.hiddenCount, foldersNotOpened: listing.foldersNotOpened,
                                cancelled: cancelled, refusal: nil, items: items)
    }

    /// The state of one run.
    private struct Run {
        let listing: BulkImportListing
        let baseline: BulkImportBaseline
        let limits: BulkImportLimits
        var items: [BulkImportItem?]
        var counts = BulkImportCounts()
        /// SHA-256 → the first path with those bytes.
        var seen: [String: String] = [:]
        var drafts: [(index: Int, draft: BulkPresetDraft)] = []

        init(listing: BulkImportListing, baseline: BulkImportBaseline, limits: BulkImportLimits) {
            self.listing = listing
            self.baseline = baseline
            self.limits = limits
            items = Array(repeating: nil, count: listing.entries.count)
        }

        mutating func finish(_ index: Int, _ kind: BulkImportKind, _ detail: String, presetID: String? = nil) {
            items[index] = BulkImportItem(path: listing.entries[index].path, kind: kind, detail: detail, presetID: presetID)
            counts.record(kind)
        }

        mutating func handle(_ index: Int) {
            let entry = listing.entries[index]
            if case .unsupported(let reason) = entry.verdict { return finish(index, .unsupported, reason) }
            if entry.size > limits.maxFileBytes { return finish(index, .tooLarge, BulkImportText.tooLarge) }
            let bytes: [UInt8]
            switch read(entry) {
            case .success(let read): bytes = read
            case .failure(let failure): return finish(index, failure.kind, failure.detail)
            }
            if bytes.isEmpty { return finish(index, .invalid, BulkImportText.empty) }
            let sha256 = ContentHash.sha256Hex(bytes)
            if let first = seen[sha256] { return finish(index, .duplicate, BulkImportText.sameInImport(first)) }
            seen[sha256] = entry.path
            if let name = baseline.stored[sha256] { return finish(index, .duplicate, BulkImportText.inMyPresets(name)) }
            let blobHash = ContentHash.gitBlobSHA1Hex(bytes)
            if let builtIn = baseline.context.builtIn[blobHash] {
                return finish(index, .duplicate, BulkImportText.builtIn(builtIn.name, builtIn.pack))
            }
            if baseline.context.blockedHashes.contains(blobHash) { return finish(index, .invalid, BulkImportText.blocked) }
            let validation = MilkdropPresetValidator.validate(bytes, knownTextures: baseline.context.knownTextures)
            if let rejection = validation.rejection { return finish(index, .invalid, rejection.message) }
            let fileName = (entry.path as NSString).lastPathComponent
            drafts.append((index, BulkPresetDraft(path: entry.path, fileName: fileName, contents: Data(bytes), sha256: sha256,
                                                  blobHash: blobHash, warnings: validation.warnings,
                                                  licenseLines: validation.licenseLines)))
        }

        mutating func flush(_ library: UserPresetLibrary) async {
            guard !drafts.isEmpty else { return }
            let batch = drafts
            drafts = []
            let results = await library.commitBulk(batch.map(\.draft), cap: limits.maxLibraryPresets)
            for (waiting, result) in zip(batch, results) {
                switch result {
                case .added(let preset): finish(waiting.index, .added, BulkImportText.added(preset.name), presetID: preset.id)
                case .duplicate(let name):
                    finish(waiting.index, .duplicate, name.isEmpty ? BulkImportText.sameInImport(waiting.draft.path) : BulkImportText.inMyPresets(name))
                case .libraryFull: finish(waiting.index, .failed, BulkImportText.libraryFull(limits.maxLibraryPresets))
                case .saveFailed: finish(waiting.index, .failed, BulkImportText.saveFailed)
                }
            }
        }

        private struct ReadFailure: Error {
            var kind: BulkImportKind
            var detail: String
        }

        /// At most the per-file limit plus one byte; a folder file is read only if it is still a
        /// regular file (not a link).
        private func read(_ entry: BulkImportEntry) -> Result<[UInt8], ReadFailure> {
            switch entry.location {
            case .file(let url):
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      attributes[.type] as? FileAttributeType == .typeRegular,
                      let handle = try? FileHandle(forReadingFrom: url) else {
                    return .failure(ReadFailure(kind: .failed, detail: BulkImportText.unreadable))
                }
                defer { try? handle.close() }
                guard let data = try? handle.read(upToCount: limits.maxFileBytes + 1) else {
                    return .success([])   // nothing to read: an empty file
                }
                if data.count > limits.maxFileBytes { return .failure(ReadFailure(kind: .tooLarge, detail: BulkImportText.tooLarge)) }
                return .success([UInt8](data))
            case .zip(let zipEntry):
                guard let archive = listing.archive else { return .failure(ReadFailure(kind: .failed, detail: BulkImportText.unreadable)) }
                do {
                    return .success([UInt8](try LooseZipReader.data(of: zipEntry, in: archive, limit: limits.maxFileBytes)))
                } catch LooseZipError.tooLarge {
                    return .failure(ReadFailure(kind: .tooLarge, detail: BulkImportText.tooLarge))
                } catch {
                    return .failure(ReadFailure(kind: .failed, detail: BulkImportText.damaged))
                }
            }
        }
    }
}
