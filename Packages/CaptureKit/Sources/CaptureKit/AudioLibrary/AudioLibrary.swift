// AudioLibrary.swift — the app-managed library of imported audio (AUD-001;
// specs/003-aud-001-import-drm-free-audio-files/contracts/audio-library.md).
//
// Layout under `directory` (Application Support/AudioLibrary in the app):
//   index.json               the versioned record, only ever replaced atomically
//   index.damaged.json       an unreadable record kept aside by a recovery
//   assets/<sha256>.<ext>    one immutable copy per distinct content
//   incoming/<uuid>.<ext>    imports in flight; emptied at every load
//
// Import is a transaction: copy to `incoming` while hashing and enforcing the size limit, validate
// the copy, rename it into `assets`, write the record. Any failure removes what the import
// created, so the library is exactly what it was (AUD-001-R5). The picked URL is used only inside
// `stage` and is never stored (AUD-001-R3).
#if canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)
import CryptoKit
import Foundation
import UniformTypeIdentifiers

public actor AudioLibrary {
    /// The largest file that can be imported: 500 MB (AUD-001-R4).
    public static let maxFileBytes: Int64 = AudioLibraryIndex.maxTrackBytes
    static let copyChunkBytes = 1 << 20

    private let directory: URL
    private let inspector: any AudioFileInspecting
    private let maxFileBytes: Int64
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private let indexWriter: @Sendable (Data, URL) throws -> Void

    private var loaded = false
    private var index = AudioLibraryIndex()
    private var tail: Task<Void, Never>?

    /// `ready` once `load()` has run, unless the library cannot be used.
    public private(set) var state: AudioLibraryState = .ready
    /// Imported tracks in import order (oldest first). Empty until `load()` and while unavailable.
    public var tracks: [ImportedTrack] { index.tracks }

    /// `Library/Application Support/AudioLibrary`: private to the app, persistent, never purged.
    public static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("AudioLibrary", isDirectory: true)
    }

    public init(directory: URL, inspector: any AudioFileInspecting = AVAudioFileInspector(),
                maxFileBytes: Int64 = AudioLibrary.maxFileBytes,
                now: @escaping @Sendable () -> Date = { Date() },
                makeID: @escaping @Sendable () -> UUID = { UUID() }) {
        self.init(directory: directory, inspector: inspector, maxFileBytes: maxFileBytes, now: now, makeID: makeID,
                  indexWriter: AudioLibrary.atomicWrite)
    }

    /// Tests replace `indexWriter` to prove that a failed record write rolls back.
    init(directory: URL, inspector: any AudioFileInspecting, maxFileBytes: Int64, now: @escaping @Sendable () -> Date,
         makeID: @escaping @Sendable () -> UUID, indexWriter: @escaping @Sendable (Data, URL) throws -> Void) {
        self.directory = directory
        self.inspector = inspector
        self.maxFileBytes = min(max(maxFileBytes, 1), AudioLibraryIndex.maxTrackBytes)
        self.now = now
        self.makeID = makeID
        self.indexWriter = indexWriter
    }

    static let atomicWrite: @Sendable (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }

    private var assetsURL: URL { directory.appendingPathComponent("assets", isDirectory: true) }
    private var incomingURL: URL { directory.appendingPathComponent("incoming", isDirectory: true) }
    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private var damagedIndexURL: URL { directory.appendingPathComponent("index.damaged.json") }

    // MARK: - Public operations (one at a time)

    /// Reads the record, recovers from damage and removes leftovers. Idempotent.
    @discardableResult
    public func load() async -> AudioLibraryState {
        await serialized { await self.loadLocked() }
    }

    /// Validates and copies one picked file. Never throws; see `AudioImportOutcome`.
    public func importFile(at url: URL) async -> AudioImportOutcome {
        await serialized { await self.importLocked(url) }
    }

    /// Imports several files in order, one at a time.
    public func importFiles(at urls: [URL]) async -> [AudioImportOutcome] {
        var outcomes: [AudioImportOutcome] = []
        outcomes.reserveCapacity(urls.count)
        for url in urls { outcomes.append(await importFile(at: url)) }
        return outcomes
    }

    /// Removes a track: its record entry, then its stored copy. Unknown ids are ignored.
    public func remove(_ id: UUID) async throws(AudioImportError) {
        let failure: AudioImportError? = await serialized { await self.removeLocked(id) }
        if let failure { throw failure }
    }

    /// The stored copy of a track, or nil when the track is unknown or its copy is missing.
    public func fileURL(for id: UUID) -> URL? {
        guard let track = index.tracks.first(where: { $0.id == id }) else { return nil }
        let url = assetsURL.appendingPathComponent(track.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Where a track's copy is stored, whether or not the file is still there; nil for an unknown
    /// id. Playback uses this so that a missing copy fails as "In-App Playback failed" instead of
    /// being skipped silently (AUD-001-R19).
    public func storedFileURL(for id: UUID) -> URL? {
        index.tracks.first(where: { $0.id == id }).map { assetsURL.appendingPathComponent($0.fileName) }
    }

    // MARK: - Serialization

    /// Runs `operation` after every earlier one has finished. The inspector is `async`, and actor
    /// methods are re-entrant at each `await`, so without this two imports of the same content
    /// could both pass the duplicate check (research AUD-001-D9).
    private func serialized<T: Sendable>(_ operation: @escaping @Sendable () async -> T) async -> T {
        let previous = tail
        let task = Task { () -> T in
            await previous?.value
            return await operation()
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    // MARK: - Load, recovery and sweep

    private func loadLocked() async -> AudioLibraryState {
        guard !loaded else { return state }
        loaded = true
        let files = FileManager.default
        do {
            try files.createDirectory(at: assetsURL, withIntermediateDirectories: true)
            try files.createDirectory(at: incomingURL, withIntermediateDirectories: true)
        } catch {
            state = .unavailable(.storage)
            return state
        }

        var needsWrite = false
        if files.fileExists(atPath: indexURL.path) {
            let decoded = (try? Data(contentsOf: indexURL)).flatMap { try? AudioLibraryIndex.decode($0) }
            switch decoded {
            case .index(let stored):
                index = stored
            case .newerFormat:
                // AUD-001-R15: a newer app wrote this. Touch nothing, not even leftovers.
                state = .unavailable(.newerFormat)
                return state
            case nil:
                // AUD-001-R14: keep the damaged record aside and rebuild from the copies.
                try? files.removeItem(at: damagedIndexURL)
                try? files.moveItem(at: indexURL, to: damagedIndexURL)
                index = await rebuiltIndex()
                needsWrite = true
            }
        }

        // AUD-001-R16: entries without a copy, temporary files, copies without an entry.
        let present = index.tracks.filter { files.fileExists(atPath: assetsURL.appendingPathComponent($0.fileName).path) }
        if present.count != index.tracks.count {
            index.tracks = present
            needsWrite = true
        }
        Self.removeContents(of: incomingURL, keeping: [])
        Self.removeContents(of: assetsURL, keeping: Set(index.tracks.map(\.fileName)))
        if needsWrite { try? writeIndex(index) }
        state = .ready
        return state
    }

    /// Rebuilds the record from the stored copies that still pass inspection. File names carry the
    /// content hash; titles are lost and become "Recovered track N".
    private func rebuiltIndex() async -> AudioLibraryIndex {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: assetsURL.path)) ?? []).sorted()
        var tracks: [ImportedTrack] = []
        for name in names {
            let hash = String(name.prefix { $0 != "." })
            guard ImportedTrack.isSHA256(hash), name == ImportedTrack.storedFileName(sha256: hash, originalFileName: name),
                  !tracks.contains(where: { $0.sha256 == hash }) else { continue }
            let url = assetsURL.appendingPathComponent(name)
            guard let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                  let info = try? await inspector.inspect(url) else { continue }
            let track = ImportedTrack(id: makeID(), title: ImportedTrack.recoveredTitle(tracks.count + 1), originalFileName: name,
                                      sha256: hash, fileName: name, byteCount: Int64(bytes), durationSeconds: info.durationSeconds,
                                      sampleRate: info.sampleRate, channelCount: info.channelCount, importedAt: now())
            if track.isValid { tracks.append(track) }
        }
        return AudioLibraryIndex(tracks: tracks)
    }

    private static func removeContents(of folder: URL, keeping names: Set<String>) {
        let files = FileManager.default
        for name in (try? files.contentsOfDirectory(atPath: folder.path)) ?? [] where !names.contains(name) {
            try? files.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private func writeIndex(_ newIndex: AudioLibraryIndex) throws {
        try indexWriter(try newIndex.encoded(), indexURL)
    }

    // MARK: - Import

    private func importLocked(_ url: URL) async -> AudioImportOutcome {
        let name = String(url.lastPathComponent.prefix(ImportedTrack.maxOriginalFileNameLength))
        guard await loadLocked() == .ready else { return .failed(fileName: name, .libraryUnavailable) }
        let files = FileManager.default
        let ext = ImportedTrack.storedExtension(fromFileName: name)
        let temporary = incomingURL.appendingPathComponent(ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)")
        do {
            let staged = try Self.stage(url, to: temporary, limit: maxFileBytes)
            if let existing = index.tracks.first(where: { $0.sha256 == staged.sha256 }) {
                try? files.removeItem(at: temporary)
                return .duplicate(existing)                       // AUD-001-R8
            }
            let info = try await inspector.inspect(temporary)
            let track = ImportedTrack(id: makeID(), title: ImportedTrack.title(fromFileName: name), originalFileName: name,
                                      sha256: staged.sha256,
                                      fileName: ImportedTrack.storedFileName(sha256: staged.sha256, originalFileName: name),
                                      byteCount: staged.byteCount, durationSeconds: info.durationSeconds,
                                      sampleRate: info.sampleRate, channelCount: info.channelCount, importedAt: now())
            guard track.isValid else { throw AudioImportError.unreadable }
            let asset = assetsURL.appendingPathComponent(track.fileName)
            do {
                try? files.removeItem(at: asset)                  // an unreferenced leftover, if any
                try files.moveItem(at: temporary, to: asset)      // same volume: a rename
            } catch {
                throw Self.storageError(error)
            }
            var updated = index
            updated.tracks.append(track)
            do {
                try writeIndex(updated)
            } catch {
                try? files.removeItem(at: asset)                  // roll back: the record does not list it
                throw Self.storageError(error)
            }
            index = updated
            return .imported(track)
        } catch {
            try? files.removeItem(at: temporary)
            return .failed(fileName: name, (error as? AudioImportError) ?? .libraryUnavailable)
        }
    }

    /// Copies the picked file into `destination`, hashing it and stopping at `limit` bytes. This is
    /// the only place that touches the picked URL: the security scope and the coordinated read both
    /// end when it returns. Throws `AudioImportError`.
    private static func stage(_ source: URL, to destination: URL, limit: Int64) throws -> (sha256: String, byteCount: Int64) {
        let scoped = source.startAccessingSecurityScopedResource()   // false for URLs that need no scope
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var result: Result<(sha256: String, byteCount: Int64), any Error> = .failure(AudioImportError.sourceUnavailable)
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: .withoutChanges,
                                                         error: &coordinationError) { readable in
            result = Result { try copy(readable, to: destination, limit: limit) }
        }
        if coordinationError != nil { throw AudioImportError.sourceUnavailable }
        return try result.get()
    }

    private static func copy(_ source: URL, to destination: URL, limit: Int64) throws -> (sha256: String, byteCount: Int64) {
        // (a) Declared type: what the system says the file is, else what its extension says.
        let type = (try? source.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: source.pathExtension)
        guard let type, type.conforms(to: .audio) else { throw AudioImportError.notAudio }

        let input: FileHandle
        do {
            input = try FileHandle(forReadingFrom: source)
        } catch {
            throw AudioImportError.sourceUnavailable
        }
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw AudioImportError.libraryUnavailable
        }
        let output: FileHandle
        do {
            output = try FileHandle(forWritingTo: destination)
        } catch {
            throw AudioImportError.libraryUnavailable
        }
        defer { try? output.close() }

        var hasher = SHA256()
        var total: Int64 = 0
        while true {
            // (b) The limit applies to the bytes actually read, whatever size the file reports.
            let chunk: Data
            do {
                chunk = try autoreleasepool { try input.read(upToCount: copyChunkBytes) } ?? Data()
            } catch {
                throw AudioImportError.sourceUnavailable
            }
            if chunk.isEmpty { break }
            total += Int64(chunk.count)
            guard total <= limit else { throw AudioImportError.tooLarge(limitBytes: limit) }
            hasher.update(data: chunk)
            do {
                try output.write(contentsOf: chunk)
            } catch {
                throw storageError(error)
            }
        }
        guard total > 0 else { throw AudioImportError.unreadable }
        let digest = hasher.finalize().map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
        return (digest, total)
    }

    /// A failed write inside the library: out of space, or the library cannot be written.
    private static func storageError(_ error: any Error) -> AudioImportError {
        if let known = error as? AudioImportError { return known }
        var next: NSError? = error as NSError
        while let current = next {
            if current.domain == NSCocoaErrorDomain && current.code == CocoaError.Code.fileWriteOutOfSpace.rawValue {
                return .insufficientStorage
            }
            if current.domain == NSPOSIXErrorDomain && (current.code == Int(ENOSPC) || current.code == Int(EDQUOT)) {
                return .insufficientStorage
            }
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return .libraryUnavailable
    }

    // MARK: - Removal

    private func removeLocked(_ id: UUID) async -> AudioImportError? {
        guard await loadLocked() == .ready else { return .libraryUnavailable }
        guard let track = index.tracks.first(where: { $0.id == id }) else { return nil }
        var updated = index
        updated.tracks.removeAll { $0.id == id }
        do {
            try writeIndex(updated)                               // record first: a crash leaves an orphan, swept at load
        } catch {
            return Self.storageError(error)
        }
        index = updated
        try? FileManager.default.removeItem(at: assetsURL.appendingPathComponent(track.fileName))
        return nil
    }
}
#endif
