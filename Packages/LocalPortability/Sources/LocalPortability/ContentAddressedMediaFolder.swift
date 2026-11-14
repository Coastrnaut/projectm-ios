// ContentAddressedMediaFolder.swift — FILE-008 (contract specs/117-file-008-user-asset-deduplication/
// contracts/media-store.md; research FILE-008-D1-D3, ADR-0043): a store folder that keeps each distinct
// content once.
//
//   <sha256>.<ext>            a payload: one immutable copy per content (SHA-256 of its bytes + size)
//   references.json           the registry: store identifier (canonical UUID) → payload name
//   <UUID>.<ext>              a legacy copy (MED-001/002 layout, or written by a FILE-005 restore)
//   .incoming-<UUID>.<ext>    an import in progress
//
// Crash safety without a separate journal (research D3): every mutation is a sequence of single atomic
// file-system steps (rename, link, atomic registry write, remove) whose every intermediate state is
// valid; `prepare` and `reconcile` at launch finish or clean what an interruption left. Resolution
// prefers a legacy file, then the registry, so an identifier resolves at every point of a migration.
// One recursive lock per folder path serializes every mutation (two imports of one content give one
// payload). `fault` is called before each step so tests can abort there as if the app were killed.
// Reads only file sizes and file numbers: no file dates, no volume capacity (privacy manifest).
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public struct MediaFolderUsage: Sendable, Equatable {
    /// Resolving identifiers.
    public var references: Int
    /// Distinct stored files (payloads and legacy copies that are not the same file as a payload).
    public var payloads: Int
    /// The bytes the references would take as separate copies.
    public var logicalBytes: Int64
    /// The bytes stored.
    public var physicalBytes: Int64

    public init(references: Int = 0, payloads: Int = 0, logicalBytes: Int64 = 0, physicalBytes: Int64 = 0) {
        self.references = references
        self.payloads = payloads
        self.logicalBytes = logicalBytes
        self.physicalBytes = physicalBytes
    }

    /// Space saved by sharing.
    public var savedBytes: Int64 { max(0, logicalBytes - physicalBytes) }
}

public enum MediaFolderError: Error, Sendable, Equatable {
    case unsupportedExtension
    case unreadable
    case writeFailed
}

public struct ContentAddressedMediaFolder: Sendable {
    /// The steps a test can abort before (contract M11).
    public enum Step: String, Sendable, CaseIterable {
        case placePayload, writeRegistry, removeSource, deletePayload, linkLegacy
    }

    public static let registryName = "references.json"
    public static let incomingPrefix = ".incoming-"
    public static let format = "org.projectmios.media-references"
    public static let version = 1
    public static let maxReferencesPerPayload = 32
    public static let maxRegistryBytes = 1 << 20

    public let directory: URL
    /// Lowercase extensions this store keeps (`png`, `jpg`; `mov`).
    public let extensions: [String]
    /// Tests only: thrown errors abort the operation at that step.
    public var fault: (@Sendable (Step, URL) throws -> Void)?

    public init(directory: URL, extensions: [String], fault: (@Sendable (Step, URL) throws -> Void)? = nil) {
        self.directory = directory
        self.extensions = extensions
        self.fault = fault
    }

    // MARK: - Names

    public func payloadURL(_ name: String) -> URL { directory.appendingPathComponent(name, isDirectory: false) }

    public func isPayloadName(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: ".") else { return false }
        let base = String(name[..<dot])
        let ext = String(name[name.index(after: dot)...])
        return extensions.contains(ext) && MediaContentHash.isSHA256Hex(base)
    }

    /// `<canonical UUID>.<ext>` → the identifier.
    public func legacyID(_ name: String) -> UUID? {
        guard let dot = name.lastIndex(of: ".") else { return nil }
        let base = String(name[..<dot])
        let ext = String(name[name.index(after: dot)...])
        guard extensions.contains(ext), let id = UUID(uuidString: base), id.uuidString == base else { return nil }
        return id
    }

    public func legacyURL(_ id: UUID) -> URL? {
        extensions.lazy.map { (ext: String) -> URL in self.payloadURL("\(id.uuidString).\(ext)") }
            .first { (url: URL) -> Bool in FileManager.default.fileExists(atPath: url.path) }
    }

    /// A temporary file name for an import in progress.
    public func incomingURL(for id: UUID, extension ext: String) -> URL {
        payloadURL("\(Self.incomingPrefix)\(id.uuidString).\(ext)")
    }

    // MARK: - Registry

    struct Entry: Codable, Equatable, Sendable {
        var id: String
        var payload: String
    }

    private struct RegistryFile: Codable {
        var format: String
        var version: Int
        var references: [Entry]
    }

    private var registryURL: URL { payloadURL(Self.registryName) }

    /// Validated entries in age order (oldest first). Anything unreadable reads as none.
    func entries() -> [Entry] {
        guard let size = Self.size(of: registryURL), size <= Int64(Self.maxRegistryBytes),
              let data = try? Data(contentsOf: registryURL),
              let file = try? JSONDecoder().decode(RegistryFile.self, from: data),
              file.format == Self.format, file.version == Self.version else { return [] }
        var seen: Set<String> = []
        var result: [Entry] = []
        for entry in file.references {
            guard let id = UUID(uuidString: entry.id), id.uuidString == entry.id, isPayloadName(entry.payload),
                  !seen.contains(entry.id) else { continue }
            seen.insert(entry.id)
            result.append(entry)
        }
        return result
    }

    private func write(_ entries: [Entry]) throws {
        try fault?(.writeRegistry, registryURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(RegistryFile(format: Self.format, version: Self.version, references: entries))
        try data.write(to: registryURL, options: .atomic)
    }

    // MARK: - Queries (M2, M3, M9, M10)

    /// A legacy file, else the registered payload; nil when neither exists.
    public func resolve(_ id: UUID) -> URL? {
        if let legacy = legacyURL(id) { return legacy }
        guard let name = entries().first(where: { (e: Entry) -> Bool in e.id == id.uuidString })?.payload else { return nil }
        let url = payloadURL(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Registered identifiers (oldest first), then legacy-only ones; only those that resolve.
    public func references() -> [UUID] {
        var ids: [UUID] = entries().compactMap { (e: Entry) -> UUID? in UUID(uuidString: e.id) }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        for name in names {
            if let id = legacyID(name), !ids.contains(id) { ids.append(id) }
        }
        return ids.filter { (id: UUID) -> Bool in resolve(id) != nil }
    }

    /// The registered payload name of `id` (nil for a legacy-only or unknown identifier).
    public func payloadName(of id: UUID) -> String? {
        entries().first(where: { (e: Entry) -> Bool in e.id == id.uuidString })?.payload
    }

    public func sharesPayload(_ a: UUID, _ b: UUID) -> Bool {
        guard let first = payloadName(of: a) else { return false }
        return first == payloadName(of: b)
    }

    /// Payload files present in the folder.
    public func payloadNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter(isPayloadName).sorted()
    }

    /// `<UUID>.<ext>` → file for every resolving identifier (the FILE-005 backup's names).
    public func logicalFiles() -> [String: URL] {
        var files: [String: URL] = [:]
        for id in references() {
            guard let url = resolve(id) else { continue }
            files["\(id.uuidString).\(url.pathExtension)"] = url
        }
        return files
    }

    public func usage() -> MediaFolderUsage {
        var usage = MediaFolderUsage()
        var counted: Set<FileNumber> = []
        func addPhysical(_ url: URL) {
            guard let number = Self.fileNumber(url), !counted.contains(number) else { return }
            counted.insert(number)
            usage.payloads += 1
            usage.physicalBytes += Self.size(of: url) ?? 0
        }
        for id in references() {
            guard let url = resolve(id) else { continue }
            usage.references += 1
            usage.logicalBytes += Self.size(of: url) ?? 0
            addPhysical(url)
        }
        for name in payloadNames() { addPhysical(payloadURL(name)) }
        return usage
    }

    // MARK: - Mutations (M1, M4-M6)

    /// Interns `source` as `id` (contract M1). Hashing happens before the lock is taken.
    @discardableResult
    public func intern(_ source: URL, as id: UUID, consumingSource: Bool) throws -> URL {
        let ext = source.pathExtension.lowercased()
        guard extensions.contains(ext) else { throw MediaFolderError.unsupportedExtension }
        let digest: MediaContentHash.Digest
        do {
            digest = try MediaContentHash.digest(ofFileAt: source)
        } catch {
            throw MediaFolderError.unreadable
        }
        return try withLock { () throws -> URL in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = "\(digest.sha256).\(ext)"
            let payload = payloadURL(name)
            let existing = Self.size(of: payload)
            if existing == digest.byteCount {
                if consumingSource {
                    try fault?(.removeSource, source)
                    try? FileManager.default.removeItem(at: source)
                }
            } else {
                try fault?(.placePayload, payload)
                if existing != nil { try? FileManager.default.removeItem(at: payload) }   // a damaged payload of that name
                do {
                    if consumingSource {
                        try FileManager.default.moveItem(at: source, to: payload)
                    } else {
                        try FileManager.default.copyItem(at: source, to: payload)
                    }
                } catch {
                    throw MediaFolderError.writeFailed
                }
            }
            var list = entries().filter { (e: Entry) -> Bool in e.id != id.uuidString }
            list.append(Entry(id: id.uuidString, payload: name))
            try write(list)
            return payload
        }
    }

    /// Removes the identifiers' entries and legacy files, then payloads left without a reference (M4).
    public func release(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        try withLock { () throws in
            let keys = Set(ids.map(\.uuidString))
            let all = entries()
            let kept = all.filter { (e: Entry) -> Bool in !keys.contains(e.id) }
            if kept.count != all.count { try write(kept) }
            for id in ids {
                for ext in extensions {
                    let url = payloadURL("\(id.uuidString).\(ext)")
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    try fault?(.removeSource, url)
                    try? FileManager.default.removeItem(at: url)
                }
            }
            try collectGarbageLocked(referenced: Set(kept.map(\.payload)))
        }
    }

    /// Releases every identifier sharing `id`'s payload (and `id` itself) except `keeping` (M5).
    public func releaseSharing(payloadOf id: UUID, keeping: Set<UUID> = []) throws {
        try withLock { () throws in
            var targets: Set<UUID> = [id]
            if let name = payloadName(of: id) {
                for entry in entries() where entry.payload == name {
                    if let other = UUID(uuidString: entry.id) { targets.insert(other) }
                }
            }
            try release(targets.subtracting(keeping))
        }
    }

    /// Keeps at most `limit` references to `id`'s payload, releasing the oldest except `keeping` (M6).
    public func trim(payloadOf id: UUID, keeping: Set<UUID>, limit: Int = ContentAddressedMediaFolder.maxReferencesPerPayload) throws {
        try withLock { () throws in
            guard let name = payloadName(of: id) else { return }
            let sharing = entries().filter { (e: Entry) -> Bool in e.payload == name }.compactMap { (e: Entry) -> UUID? in UUID(uuidString: e.id) }
            var excess = sharing.count - max(1, limit)
            var victims: Set<UUID> = []
            for candidate in sharing where excess > 0 && !keeping.contains(candidate) {
                victims.insert(candidate)
                excess -= 1
            }
            try release(victims)
        }
    }

    // MARK: - Launch (M7, M8)

    /// Cheap synchronous clean-up: temporary files, and legacy files that are the same file as their
    /// registered payload (migrated by an earlier `reconcile`). Reads no content.
    public func prepare() {
        withLock { () in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            let registered = Dictionary(entries().map { (e: Entry) -> (String, String) in (e.id, e.payload) },
                                        uniquingKeysWith: { (first: String, _: String) -> String in first })
            for name in names {
                let url = payloadURL(name)
                if name.hasPrefix(Self.incomingPrefix) {
                    try? FileManager.default.removeItem(at: url)
                    continue
                }
                guard let id = legacyID(name), let payload = registered[id.uuidString] else { continue }
                guard Self.isSameFile(url, payloadURL(payload)) else { continue }
                do {
                    try fault?(.removeSource, url)
                } catch {
                    continue   // a test's abort: the legacy name stays, as after a crash
                }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    public struct ReconcileReport: Sendable, Equatable {
        public var migrated: Int = 0
        public var collected: Int = 0
    }

    /// Registers every legacy file, then deletes unreferenced payloads (M8). Idempotent; a thrown
    /// fault leaves a state the next call completes.
    @discardableResult
    public func reconcile() throws -> ReconcileReport {
        var report = ReconcileReport()
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        for name in names {
            guard let id = legacyID(name) else { continue }
            let legacy = payloadURL(name)
            if let registered = payloadName(of: id), Self.isSameFile(legacy, payloadURL(registered)) { continue }
            guard let digest = try? MediaContentHash.digest(ofFileAt: legacy) else { continue }
            if try migrate(legacy, id: id, digest: digest) { report.migrated += 1 }
        }
        report.collected = try withLock { () throws -> Int in
            try collectGarbageLocked(referenced: Set(entries().map(\.payload)))
        }
        return report
    }

    /// One legacy file: link (or copy) it to its payload name, or make it a link of an equal payload,
    /// then register it. The legacy name stays until the next `prepare`.
    private func migrate(_ legacy: URL, id: UUID, digest: MediaContentHash.Digest) throws -> Bool {
        try withLock { () throws -> Bool in
            guard FileManager.default.fileExists(atPath: legacy.path) else { return false }
            let ext = legacy.pathExtension
            let name = "\(digest.sha256).\(ext)"
            let payload = payloadURL(name)
            let existing = Self.size(of: payload)
            if existing == digest.byteCount {
                if !Self.isSameFile(legacy, payload) {
                    // Make the legacy name a link of the payload, so `prepare` can remove it later.
                    let temp = incomingURL(for: UUID(), extension: ext)
                    try fault?(.linkLegacy, legacy)
                    if (try? FileManager.default.linkItem(at: payload, to: temp)) != nil {
                        if rename(temp.path, legacy.path) != 0 { try? FileManager.default.removeItem(at: temp) }
                    }
                }
            } else {
                try fault?(.linkLegacy, payload)
                if existing != nil { try? FileManager.default.removeItem(at: payload) }
                if (try? FileManager.default.linkItem(at: legacy, to: payload)) == nil {
                    do {
                        try FileManager.default.copyItem(at: legacy, to: payload)
                    } catch {
                        return false
                    }
                }
            }
            var list = entries().filter { (e: Entry) -> Bool in e.id != id.uuidString }
            list.append(Entry(id: id.uuidString, payload: name))
            try write(list)
            return true
        }
    }

    @discardableResult
    private func collectGarbageLocked(referenced: Set<String>) throws -> Int {
        var removed = 0
        for name in payloadNames() where !referenced.contains(name) {
            let url = payloadURL(name)
            try fault?(.deletePayload, url)
            if (try? FileManager.default.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }

    // MARK: - Files

    struct FileNumber: Hashable {
        let device: UInt64
        let file: UInt64
    }

    static func fileNumber(_ url: URL) -> FileNumber? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let file = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value else { return nil }
        return FileNumber(device: device, file: file)
    }

    static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        guard let first = fileNumber(a) else { return false }
        return first == fileNumber(b)
    }

    static func size(of url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType, type == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.int64Value else { return nil }
        return size
    }

    // MARK: - Lock

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        let lock = FolderLocks.shared.lock(for: directory)
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

/// One recursive lock per folder path, for the whole process.
final class FolderLocks: @unchecked Sendable {
    static let shared = FolderLocks()
    private let guardLock = NSLock()
    private var locks: [String: NSRecursiveLock] = [:]

    func lock(for directory: URL) -> NSRecursiveLock {
        let key = directory.standardizedFileURL.path
        guardLock.lock()
        defer { guardLock.unlock() }
        if let existing = locks[key] { return existing }
        let lock = NSRecursiveLock()
        locks[key] = lock
        return lock
    }
}
