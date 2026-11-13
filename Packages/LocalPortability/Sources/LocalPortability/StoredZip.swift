// StoredZip.swift — a ZIP writer and reader for stored (uncompressed) entries only
// (PRE-014-R7, R13, R14; research D2, D4; contracts/preset-archive.md §1-3).
//
// Foundation has no public ZIP writer on iOS and third-party code is not allowed, so this is the
// small subset of PKWARE's APPNOTE the app needs:
//   * method 0 (stored), CRC-32, general-purpose flag bit 11 (UTF-8 names) and nothing else;
//   * no encryption, data descriptors, ZIP64, multiple disks, extra fields or comments when
//     writing; the reader skips extra fields of other tools but refuses everything else above;
//   * every entry's date and time is the writer's `modified` date in UTC, so identical input
//     gives identical bytes.
//
// The reader trusts nothing: the end record must sit exactly at the end; every count, size and
// offset is checked against the data and the limits before it is used, and before the bytes it
// describes are read; local and central headers must agree; entries may not overlap; names must
// be safe relative paths (ArchivePath) and unique ignoring case; each CRC-32 is verified. Any
// violation throws `StoredZipError`; no input can make it trap.
import Foundation

public enum StoredZipError: Error, Equatable, Sendable {
    case notAZip
    case truncated
    /// A ZIP feature the app does not read, in words ("compressed entries").
    case unsupported(String)
    /// The structure is inconsistent, in words.
    case malformed(String)
    case unsafePath(String)
    case duplicatePath(String)
    /// More entries than the limit, which is given.
    case tooManyEntries(Int)
    case entryTooLarge(String)
    case archiveTooLarge
    case checksumMismatch(String)
    /// The writer was used after `finish()`.
    case finished

    public var message: String {
        switch self {
        case .notAZip: return "This file is not a ZIP archive."
        case .truncated: return "The archive is incomplete. It may have been cut off."
        case .unsupported(let what): return "The archive uses \(what), which the app does not read."
        case .malformed(let what): return "The archive is damaged (\(what))."
        case .unsafePath(let path): return "The archive names a file outside its own folder: \(path)."
        case .duplicatePath(let path): return "The archive contains \(path) more than once."
        case .tooManyEntries(let limit): return "The archive contains more files than the app reads (\(limit))."
        case .entryTooLarge(let path): return "\(path) in the archive is larger than allowed."
        case .archiveTooLarge: return "The archive is larger than the app reads."
        case .checksumMismatch(let path): return "\(path) in the archive is damaged (checksum mismatch)."
        case .finished: return "The archive was already completed."
        }
    }
}

/// What a reader accepts. `entryLimits` overrides `maxEntryBytes` for particular names.
public struct StoredZipLimits: Sendable, Equatable {
    public var maxEntries: Int
    public var maxEntryBytes: Int
    public var maxArchiveBytes: Int
    public var entryLimits: [String: Int]

    public init(maxEntries: Int, maxEntryBytes: Int, maxArchiveBytes: Int, entryLimits: [String: Int] = [:]) {
        self.maxEntries = maxEntries
        self.maxEntryBytes = maxEntryBytes
        self.maxArchiveBytes = maxArchiveBytes
        self.entryLimits = entryLimits
    }

    public func limit(for path: String) -> Int { entryLimits[path] ?? maxEntryBytes }
}

public struct StoredZipEntry: Sendable, Equatable {
    public let path: String
    public let data: Data
}

enum ZipFormat {
    static let localSignature: UInt32 = 0x0403_4B50
    static let centralSignature: UInt32 = 0x0201_4B50
    static let endSignature: UInt32 = 0x0605_4B50
    static let localHeaderSize = 30
    static let centralHeaderSize = 46
    static let endRecordSize = 22
    static let utf8Flag: UInt16 = 0x0800
    static let versionNeeded: UInt16 = 20
    static let madeBy: UInt16 = 0x0314            // Unix, specification 2.0
    static let fileMode: UInt32 = 0o100644 << 16  // regular file, rw-r--r--
    static let maxUInt32 = Int(UInt32.max)
}

// MARK: - Writer

/// Streams entries to `sink` (a file handle in the app, a buffer in tests), then the central
/// directory on `finish()`. Not thread-safe; use from one task.
public final class StoredZipWriter {
    private struct Written {
        let name: [UInt8]
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private let sink: (Data) throws -> Void
    private let time: UInt16
    private let date: UInt16
    private var written: [Written] = []
    private var keys: Set<String> = []
    private var isFinished = false
    public private(set) var bytesWritten = 0

    public init(modified: Date, sink: @escaping (Data) throws -> Void) {
        self.sink = sink
        (time, date) = Self.dosDateTime(modified)
    }

    /// Adds one stored entry. Throws `unsafePath`, `duplicatePath` (ignoring case),
    /// `archiveTooLarge` (beyond the 4 GiB a non-ZIP64 archive can address) or the sink's error.
    public func add(path: String, data: Data) throws {
        guard !isFinished else { throw StoredZipError.finished }
        guard ArchivePath.isSafe(path) else { throw StoredZipError.unsafePath(path) }
        let key = ArchivePath.collisionKey(path)
        guard !keys.contains(key) else { throw StoredZipError.duplicatePath(path) }
        let name = Array(path.utf8)
        guard written.count < 0xFFFF, data.count < ZipFormat.maxUInt32,
              bytesWritten + ZipFormat.localHeaderSize + name.count + data.count < ZipFormat.maxUInt32 else {
            throw StoredZipError.archiveTooLarge
        }
        let crc = CRC32.checksum(data)
        var header = ByteWriter()
        header.u32(ZipFormat.localSignature)
        header.u16(ZipFormat.versionNeeded)
        header.u16(ZipFormat.utf8Flag)
        header.u16(0)                                   // stored
        header.u16(time)
        header.u16(date)
        header.u32(crc)
        header.u32(UInt32(data.count))
        header.u32(UInt32(data.count))
        header.u16(UInt16(name.count))
        header.u16(0)                                   // no extra field
        header.bytes(name)
        let offset = UInt32(bytesWritten)
        try emit(header.data)
        try emit(data)
        keys.insert(key)
        written.append(Written(name: name, crc: crc, size: UInt32(data.count), offset: offset))
    }

    /// Writes the central directory and the end record. The writer cannot be used afterwards.
    public func finish() throws {
        guard !isFinished else { throw StoredZipError.finished }
        var central = ByteWriter()
        for entry in written {
            central.u32(ZipFormat.centralSignature)
            central.u16(ZipFormat.madeBy)
            central.u16(ZipFormat.versionNeeded)
            central.u16(ZipFormat.utf8Flag)
            central.u16(0)
            central.u16(time)
            central.u16(date)
            central.u32(entry.crc)
            central.u32(entry.size)
            central.u32(entry.size)
            central.u16(UInt16(entry.name.count))
            central.u16(0)                              // extra
            central.u16(0)                              // comment
            central.u16(0)                              // disk
            central.u16(0)                              // internal attributes
            central.u32(ZipFormat.fileMode)
            central.u32(entry.offset)
            central.bytes(entry.name)
        }
        let centralOffset = bytesWritten
        guard centralOffset + central.data.count + ZipFormat.endRecordSize < ZipFormat.maxUInt32 else { throw StoredZipError.archiveTooLarge }
        var end = ByteWriter()
        end.u32(ZipFormat.endSignature)
        end.u16(0)
        end.u16(0)
        end.u16(UInt16(written.count))
        end.u16(UInt16(written.count))
        end.u32(UInt32(central.data.count))
        end.u32(UInt32(centralOffset))
        end.u16(0)                                      // no comment
        try emit(central.data)
        try emit(end.data)
        isFinished = true
    }

    private func emit(_ data: Data) throws {
        try sink(data)
        bytesWritten += data.count
    }

    /// MS-DOS time and date fields in UTC, clamped to 1980-01-01 ... 2107-12-31 (2-second steps).
    static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let year = parts.year, year >= 1980 else { return (0, 1 << 5 | 1) }
        guard year <= 2107 else { return (23 << 11 | 59 << 5 | 29, 127 << 9 | 12 << 5 | 31) }
        let time = (parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2
        let day = (year - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1)
        return (UInt16(time), UInt16(day))
    }
}

struct ByteWriter {
    var data = Data()
    mutating func u16(_ value: UInt16) { data.append(UInt8(value & 0xFF)); data.append(UInt8(value >> 8)) }
    mutating func u32(_ value: UInt32) { u16(UInt16(value & 0xFFFF)); u16(UInt16(value >> 16)) }
    mutating func bytes(_ value: [UInt8]) { data.append(contentsOf: value) }
}

// MARK: - Reader

public enum StoredZipReader {
    private struct Central {
        let path: String
        let flags: Int
        let crc: Int
        let size: Int
        let nameBytes: [UInt8]
        let localOffset: Int
    }

    /// Every entry in central-directory order, or the first problem found.
    public static func read(_ data: Data, limits: StoredZipLimits) throws -> [StoredZipEntry] {
        let bytes = Bytes(data)
        guard data.count <= limits.maxArchiveBytes else { throw StoredZipError.archiveTooLarge }
        let end = try endRecord(bytes)

        // End record (research D4 step 2).
        let disk = bytes.u16(end + 4), centralDisk = bytes.u16(end + 6)
        let onDisk = bytes.u16(end + 8), total = bytes.u16(end + 10)
        let centralSize = bytes.u32(end + 12), centralOffset = bytes.u32(end + 16)
        if onDisk == 0xFFFF || total == 0xFFFF || centralSize == ZipFormat.maxUInt32 || centralOffset == ZipFormat.maxUInt32 {
            throw StoredZipError.unsupported("ZIP64")
        }
        guard disk == 0, centralDisk == 0, onDisk == total else { throw StoredZipError.unsupported("multiple disks") }
        guard total <= limits.maxEntries else { throw StoredZipError.tooManyEntries(limits.maxEntries) }
        guard centralOffset + centralSize == end else { throw StoredZipError.malformed("central directory") }

        // Central headers (step 3).
        var entries: [Central] = []
        var keys: Set<String> = []
        var at = centralOffset
        for _ in 0..<total {
            guard at + ZipFormat.centralHeaderSize <= end, bytes.u32(at) == Int(ZipFormat.centralSignature) else {
                throw StoredZipError.malformed("central directory")
            }
            let flags = bytes.u16(at + 8), method = bytes.u16(at + 10)
            let crc = bytes.u32(at + 16), compressed = bytes.u32(at + 20), size = bytes.u32(at + 24)
            let nameLength = bytes.u16(at + 28), extraLength = bytes.u16(at + 30), commentLength = bytes.u16(at + 32)
            let diskStart = bytes.u16(at + 34), localOffset = bytes.u32(at + 42)
            let next = at + ZipFormat.centralHeaderSize + nameLength + extraLength + commentLength
            guard next <= end else { throw StoredZipError.malformed("central directory") }
            if flags & 0x0001 != 0 { throw StoredZipError.unsupported("encryption") }
            if flags & ~Int(ZipFormat.utf8Flag) != 0 { throw StoredZipError.unsupported("options the app does not read") }
            if compressed == ZipFormat.maxUInt32 || size == ZipFormat.maxUInt32 || localOffset == ZipFormat.maxUInt32 {
                throw StoredZipError.unsupported("ZIP64")
            }
            if method != 0 { throw StoredZipError.unsupported("compressed entries") }
            if diskStart != 0 { throw StoredZipError.unsupported("multiple disks") }
            guard compressed == size else { throw StoredZipError.malformed("sizes disagree") }
            guard nameLength > 0 else { throw StoredZipError.malformed("an empty name") }
            let nameBytes = bytes.slice(at + ZipFormat.centralHeaderSize, nameLength)
            guard let path = String(bytes: nameBytes, encoding: .utf8) else { throw StoredZipError.malformed("a name that is not UTF-8") }
            if flags & Int(ZipFormat.utf8Flag) == 0, nameBytes.contains(where: { $0 >= 0x80 }) {
                throw StoredZipError.unsupported("names that are not marked as UTF-8")
            }
            guard ArchivePath.isSafe(path) else { throw StoredZipError.unsafePath(path) }
            guard keys.insert(ArchivePath.collisionKey(path)).inserted else { throw StoredZipError.duplicatePath(path) }
            guard size <= limits.limit(for: path) else { throw StoredZipError.entryTooLarge(path) }
            entries.append(Central(path: path, flags: flags, crc: crc, size: size, nameBytes: nameBytes, localOffset: localOffset))
            at = next
        }
        guard at == end else { throw StoredZipError.malformed("central directory") }

        // Local headers and data ranges (step 4).
        var ranges: [(start: Int, end: Int, path: String)] = []
        var dataStarts: [Int] = []
        for entry in entries {
            let local = entry.localOffset
            guard local + ZipFormat.localHeaderSize <= centralOffset, bytes.u32(local) == Int(ZipFormat.localSignature) else {
                throw StoredZipError.malformed("local header of \(entry.path)")
            }
            let nameLength = bytes.u16(local + 26), extraLength = bytes.u16(local + 28)
            let start = local + ZipFormat.localHeaderSize + nameLength + extraLength
            guard start + entry.size <= centralOffset else { throw StoredZipError.malformed("data of \(entry.path) out of bounds") }
            guard bytes.u16(local + 6) == entry.flags, bytes.u16(local + 8) == 0, bytes.u32(local + 14) == entry.crc,
                  bytes.u32(local + 18) == entry.size, bytes.u32(local + 22) == entry.size,
                  nameLength == entry.nameBytes.count, bytes.slice(local + ZipFormat.localHeaderSize, nameLength) == entry.nameBytes else {
                throw StoredZipError.malformed("headers of \(entry.path) disagree")
            }
            ranges.append((local, start + entry.size, entry.path))
            dataStarts.append(start)
        }
        let sorted = ranges.sorted { $0.start < $1.start }
        for (earlier, later) in zip(sorted, sorted.dropFirst()) where earlier.end > later.start {
            throw StoredZipError.malformed("\(earlier.path) and \(later.path) overlap")
        }

        // Contents and checksums (step 5).
        var result: [StoredZipEntry] = []
        result.reserveCapacity(entries.count)
        for (entry, start) in zip(entries, dataStarts) {
            let content = bytes.data(start, entry.size)
            guard Int(CRC32.checksum(content)) == entry.crc else { throw StoredZipError.checksumMismatch(entry.path) }
            result.append(StoredZipEntry(path: entry.path, data: content))
        }
        return result
    }

    /// The offset of the end record, which must be the last 22 bytes (no archive comment).
    private static func endRecord(_ bytes: Bytes) throws -> Int {
        let count = bytes.count
        let startsLikeZip = count >= 4 && bytes.u32(0) == Int(ZipFormat.localSignature)
        let isEmptyZip = count >= 4 && bytes.u32(0) == Int(ZipFormat.endSignature)
        if count >= ZipFormat.endRecordSize, bytes.u32(count - ZipFormat.endRecordSize) == Int(ZipFormat.endSignature),
           bytes.u16(count - 2) == 0 {
            return count - ZipFormat.endRecordSize
        }
        // An end record further back with a comment that reaches exactly to the end.
        let earliest = max(0, count - ZipFormat.endRecordSize - 0xFFFF)
        var at = count - ZipFormat.endRecordSize - 1
        while at >= earliest {
            if bytes.u32(at) == Int(ZipFormat.endSignature), at + ZipFormat.endRecordSize + bytes.u16(at + 20) == count {
                throw StoredZipError.unsupported("an archive comment")
            }
            at -= 1
        }
        throw startsLikeZip || isEmptyZip ? StoredZipError.truncated : StoredZipError.notAZip
    }
}

/// Bounds-checked little-endian reads; a read outside the data returns 0 (callers check bounds
/// before reading, this only guarantees no trap).
private struct Bytes {
    let data: Data
    let count: Int
    private let base: Int

    init(_ data: Data) {
        self.data = data
        count = data.count
        base = data.startIndex
    }

    func u8(_ at: Int) -> Int { at >= 0 && at < count ? Int(data[base + at]) : 0 }
    func u16(_ at: Int) -> Int { u8(at) | u8(at + 1) << 8 }
    func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }

    func slice(_ at: Int, _ length: Int) -> [UInt8] {
        guard at >= 0, length >= 0, at + length <= count else { return [] }
        return [UInt8](data[(base + at)..<(base + at + length)])
    }

    func data(_ at: Int, _ length: Int) -> Data {
        guard at >= 0, length >= 0, at + length <= count else { return Data() }
        return Data(data[(base + at)..<(base + at + length)])
    }
}
