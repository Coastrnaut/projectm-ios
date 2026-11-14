// BackupFileAccess.swift — FILE-006 contract B2 (research FILE-006-D3, D7): the only path through which a
// folder backup or a media restore reads media bytes, so a test can count them per file. `status` reads
// metadata only (size; the modification date only when asked, which the backup does only for files in
// the app's container: the privacy manifest declares C617.1). `copy` streams 1 MiB chunks into the
// destination while a SHA-256 runs (CryptoKit on Apple platforms, FILE-002's portable hasher on Linux
// or with `-DLIBRARYBACKUP_NO_CRYPTOKIT`), so a new or changed file is read exactly once.
import Foundation
import LocalPortability
#if canImport(CryptoKit) && !LIBRARYBACKUP_NO_CRYPTOKIT
import CryptoKit
#endif

public struct BackupFileStatus: Sendable, Equatable {
    public var byteCount: Int64
    /// Seconds since 1970; nil unless asked for.
    public var modified: Double?

    public init(byteCount: Int64, modified: Double? = nil) {
        self.byteCount = byteCount
        self.modified = modified
    }
}

/// A file's SHA-256 (64 lowercase hex) and its byte count.
public struct BackupDigest: Sendable, Equatable {
    public var sha256: String
    public var byteCount: Int64

    public init(sha256: String, byteCount: Int64) {
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

public protocol BackupFileAccess: Sendable {
    /// Metadata only; nil when the file is missing or not a regular file.
    func status(of url: URL, includingDate: Bool) -> BackupFileStatus?
    /// Streams the file through SHA-256.
    func digest(of url: URL) throws -> BackupDigest
    /// Copies `source` to `destination` (created or replaced) in one streaming read, hashing it.
    func copy(from source: URL, to destination: URL) throws -> BackupDigest
}

public struct LocalBackupFileAccess: BackupFileAccess {
    public static let chunkSize = 1 << 20

    public init() {}

    public func status(of url: URL, includingDate: Bool) -> BackupFileStatus? {
        var keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        if includingDate { keys.insert(.contentModificationDateKey) }
        guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true, let size = values.fileSize else { return nil }
        let date: Double? = includingDate ? values.contentModificationDate?.timeIntervalSince1970 : nil
        return BackupFileStatus(byteCount: Int64(size), modified: date)
    }

    public func digest(of url: URL) throws -> BackupDigest {
        try stream(url, into: nil)
    }

    public func copy(from source: URL, to destination: URL) throws -> BackupDigest {
        let files = FileManager.default
        try? files.removeItem(at: destination)
        guard files.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        return try stream(source, into: output)
    }

    private func stream(_ url: URL, into output: FileHandle?) throws -> BackupDigest {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hasher = BackupHasher()
        var count: Int64 = 0
        while true {
            let chunk: Data = try input.read(upToCount: Self.chunkSize) ?? Data()
            if chunk.isEmpty { break }
            count += Int64(chunk.count)
            hasher.update(chunk)
            try output?.write(contentsOf: chunk)
        }
        try output?.synchronize()
        return BackupDigest(sha256: hasher.finalize(), byteCount: count)
    }
}

/// SHA-256 in chunks, lowercase hex out.
struct BackupHasher {
    #if canImport(CryptoKit) && !LIBRARYBACKUP_NO_CRYPTOKIT
    private var hasher = SHA256()
    mutating func update(_ data: Data) { hasher.update(data: data) }
    func finalize() -> String {
        let digits: [Character] = Array("0123456789abcdef")
        var text = ""
        for byte in hasher.finalize() {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return text
    }
    #else
    private var hasher = PortableSHA256.Hasher()
    mutating func update(_ data: Data) { hasher.update(data) }
    func finalize() -> String { hasher.finalize() }
    #endif
}
