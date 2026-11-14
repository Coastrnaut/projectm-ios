// WarmCacheStore.swift — PERF-009 (contracts/warm-cache.md W1, W2, W4; research PERF-009-D8): one folder of
// key-checked cache entries. Each entry is `<name>.bin` (the payload) plus `<name>.key.json` (its key, byte count
// and SHA-256). An entry is returned only when every key field matches and the payload checks out; a stale or
// damaged entry is deleted when found. The payload is written first and the key file last, so an interrupted
// write is a miss or a checksum failure, never a wrong hit. Nothing outside the folder is touched, and a folder
// that is a symbolic link is not used at all.
import Foundation

/// What a lookup found (`label` is the form reports and signposts use).
public enum WarmCacheOutcome: Sendable, Equatable {
    public enum Damage: String, Sendable, Equatable {
        /// The key file is missing parts, unreadable or of another schema.
        case keyFile
        case missingPayload
        /// The payload's byte count differs from the key file's.
        case size
        case checksum
        /// The payload passed its checksum but its producer could not decode it.
        case decode
        /// Larger than `maxPayloadBytes`: never read.
        case tooLarge
        /// An entry file is a symbolic link.
        case link
    }

    case hit
    case miss
    case stale(WarmCacheKey.Field)
    case damaged(Damage)
    /// The platform cannot hold this kind of entry (for example no Metal binary archives).
    case unsupported
    /// The folder is a link or cannot be created.
    case unavailable

    public var label: String {
        switch self {
        case .hit: "hit"
        case .miss: "miss"
        case .stale(let field): "stale-" + field.rawValue
        case .damaged(let damage): "damaged-" + damage.rawValue
        case .unsupported: "unsupported"
        case .unavailable: "unavailable"
        }
    }

    public var isHit: Bool { self == .hit }
}

public struct WarmCacheStore: Sendable {
    /// Format of the key file.
    public static let keyFileSchema = 1
    public static let defaultMaxPayloadBytes = 64 << 20

    public let directory: URL
    public let maxPayloadBytes: Int

    public init(directory: URL, maxPayloadBytes: Int = WarmCacheStore.defaultMaxPayloadBytes) {
        self.directory = directory
        self.maxPayloadBytes = maxPayloadBytes
    }

    /// `[a-z0-9-]`, 1-64 characters.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 64
            && name.utf8.allSatisfy { (c: UInt8) -> Bool in (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 45 }
    }

    public func payloadURL(_ name: String) -> URL { directory.appendingPathComponent(name + ".bin", isDirectory: false) }
    public func keyURL(_ name: String) -> URL { directory.appendingPathComponent(name + ".key.json", isDirectory: false) }

    struct KeyFile: Codable, Equatable {
        var schema: Int
        var key: WarmCacheKey
        var payloadBytes: Int
        var payloadSHA256: String
    }

    // MARK: - Reading (W1, W2)

    /// The payload when the entry is valid for `key`; otherwise the outcome (stale and damaged entries removed).
    public func read(_ name: String, key: WarmCacheKey) -> (outcome: WarmCacheOutcome, payload: Data?) {
        let checked = validate(name, key: key)
        return (checked.outcome, checked.payload)
    }

    /// Like `read`, for consumers that open the file themselves (a Metal binary archive): the payload file's URL
    /// after the same checks.
    public func lookup(_ name: String, key: WarmCacheKey) -> (outcome: WarmCacheOutcome, url: URL?) {
        let checked = validate(name, key: key)
        return (checked.outcome, checked.outcome.isHit ? payloadURL(name) : nil)
    }

    private func validate(_ name: String, key: WarmCacheKey) -> (outcome: WarmCacheOutcome, payload: Data?) {
        guard Self.isValidName(name), folderIsUsable(create: false) != false else { return (.unavailable, nil) }
        let keyPath = keyURL(name).path
        let payloadPath = payloadURL(name).path
        let fileManager = FileManager.default
        if Self.isLink(keyPath) || Self.isLink(payloadPath) { return discard(name, .damaged(.link)) }
        guard fileManager.fileExists(atPath: keyPath) else { return (.miss, nil) }
        guard let keyData = try? Data(contentsOf: keyURL(name)),
              let stored = try? JSONDecoder().decode(KeyFile.self, from: keyData),
              stored.schema == Self.keyFileSchema, stored.payloadBytes >= 0,
              MediaContentHash.isSHA256Hex(stored.payloadSHA256) else {
            return discard(name, .damaged(.keyFile))
        }
        if let field = stored.key.firstMismatch(key) { return discard(name, .stale(field)) }
        guard let attributes = try? fileManager.attributesOfItem(atPath: payloadPath),
              let size = (attributes[.size] as? NSNumber)?.intValue else {
            return discard(name, .damaged(.missingPayload))
        }
        if size > maxPayloadBytes || stored.payloadBytes > maxPayloadBytes { return discard(name, .damaged(.tooLarge)) }
        if size != stored.payloadBytes { return discard(name, .damaged(.size)) }
        guard let payload = try? Data(contentsOf: payloadURL(name), options: .mappedIfSafe) else {
            return discard(name, .damaged(.missingPayload))
        }
        guard payload.count == stored.payloadBytes else { return discard(name, .damaged(.size)) }
        guard WarmCacheHash.sha256Hex(payload) == stored.payloadSHA256 else { return discard(name, .damaged(.checksum)) }
        return (.hit, payload)
    }

    private func discard(_ name: String, _ outcome: WarmCacheOutcome) -> (outcome: WarmCacheOutcome, payload: Data?) {
        remove(name)
        return (outcome, nil)
    }

    // MARK: - Writing

    /// Stores `payload` for `key`, replacing any entry of that name. Throws when the folder is unusable or a write
    /// fails; callers treat that as "no cache next time" (PERF-009-R7).
    public func write(_ name: String, key: WarmCacheKey, payload: Data) throws {
        try prepare(name, payloadBytes: payload.count)
        try payload.write(to: payloadURL(name), options: .atomic)
        try writeKey(name, key: key, payloadBytes: payload.count, sha256: WarmCacheHash.sha256Hex(payload))
    }

    /// Stores the file at `file` (inside this folder, for example a serialized Metal archive written to
    /// `temporaryURL(for:)`) as the payload for `key`: the file is moved into place, then the key file is written.
    public func commit(_ name: String, key: WarmCacheKey, fileAt file: URL) throws {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        try prepare(name, payloadBytes: data.count)
        let digest = WarmCacheHash.sha256Hex(data)
        let destination = payloadURL(name)
        if FileManager.default.fileExists(atPath: destination.path) || Self.isLink(destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: file, to: destination)
        try writeKey(name, key: key, payloadBytes: data.count, sha256: digest)
    }

    /// A scratch file name inside the folder for `commit` (created by the caller).
    public func temporaryURL(for name: String) throws -> URL {
        guard Self.isValidName(name), folderIsUsable(create: true) == true else { throw WarmCacheError.unavailable }
        return directory.appendingPathComponent(name + ".tmp", isDirectory: false)
    }

    private func prepare(_ name: String, payloadBytes: Int) throws {
        guard Self.isValidName(name), folderIsUsable(create: true) == true else { throw WarmCacheError.unavailable }
        guard payloadBytes <= maxPayloadBytes else { throw WarmCacheError.tooLarge }
        // The key goes first so a failure below leaves a miss, never an old key over a new payload's name.
        if FileManager.default.fileExists(atPath: keyURL(name).path) || Self.isLink(keyURL(name).path) {
            try FileManager.default.removeItem(at: keyURL(name))
        }
    }

    private func writeKey(_ name: String, key: WarmCacheKey, payloadBytes: Int, sha256: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let file = KeyFile(schema: Self.keyFileSchema, key: key, payloadBytes: payloadBytes, payloadSHA256: sha256)
        try encoder.encode(file).write(to: keyURL(name), options: .atomic)
    }

    // MARK: - Removal

    /// Deletes one entry's files (links removed as links).
    public func remove(_ name: String) {
        guard Self.isValidName(name), folderIsUsable(create: false) == true else { return }
        for url in [keyURL(name), payloadURL(name), directory.appendingPathComponent(name + ".tmp")] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Deletes every file in the folder (the folder itself stays). PERF-009-D9's cold launches.
    public func clear() {
        guard folderIsUsable(create: false) == true,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
    }

    // MARK: - Helpers

    /// true: a real folder; false: a link or a file (never used); nil: absent (and not created).
    private func folderIsUsable(create: Bool) -> Bool? {
        let path = directory.path
        if Self.isLink(path) { return false }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) { return isDirectory.boolValue }
        guard create else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    /// `attributesOfItem` does not follow a final link (lstat).
    static func isLink(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }
}

public enum WarmCacheError: Error, Equatable {
    case unavailable
    case tooLarge
}
