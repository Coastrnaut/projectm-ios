// LooseZipReader.swift — a per-entry reader for ordinary ZIP archives (roadmap PRE-013,
// specs/174-pre-013-bulk-import; research PRE-013-D1, D2; contract C1).
//
// `StoredZipReader` reads the app's own archives and refuses the whole archive for any entry it does
// not accept. Preset packs found elsewhere are ordinary archives: deflated, often with a `__MACOSX`
// folder or a stray link. This reader gives every entry its own verdict instead, and reads one entry
// on demand. It shares the trust rules of `StoredZipReader`:
//   * the structure (end record, central directory) is bounds-checked before any byte it describes is
//     used, and refused as a whole only when it cannot be walked (no end record, ZIP64, several disks,
//     a central directory out of bounds);
//   * every name goes through `ArchivePath` first, so `../x`, `/x`, `a\b` and the like are never
//     joined to anything ("unsafe", never read);
//   * an entry is read only through its local header, which must agree with the central record and
//     stay inside the data; the result must have exactly the declared size and CRC-32;
//   * inflating never produces more than the declared size plus one byte, and the declared size is
//     checked against the caller's limit before anything is inflated.
// Deflate (method 8) uses Apple's Compression framework (public SDK API, raw DEFLATE); where it does
// not exist (Linux) a deflated entry is `.unsupportedMethod`. No input can make this code trap.
import Foundation
#if canImport(Compression)
import Compression
#endif

public enum LooseZipError: Error, Equatable, Sendable {
    /// Not a ZIP archive, or one whose directory cannot be walked (in words).
    case unreadable(String)
    /// An entry's data could not be read back as declared (in words).
    case damaged(String)
    /// The entry is larger than the caller's limit.
    case tooLarge
    /// The entry is not one that can be read (see `LooseZipEntry.Verdict`).
    case notReadable
}

public struct LooseZipEntry: Sendable, Equatable {
    public enum Verdict: Sendable, Equatable {
        /// A regular file that can be read with `LooseZipReader.data(of:in:limit:)`.
        case file
        /// A folder record; it names no data.
        case directory
        /// The name breaks an `ArchivePath` rule (outside the archive's folder, absolute, …).
        case unsafePath(ArchivePathError)
        /// A Unix symbolic link or special file.
        case link
        case encrypted
        /// A compression method this reader does not inflate (its number).
        case unsupportedMethod(Int)
    }

    /// The name as stored (UTF-8; otherwise non-ASCII bytes become "?"); a directory's without its trailing "/".
    public let path: String
    public let verdict: Verdict
    /// Declared uncompressed size.
    public let size: Int
    let method: Int
    let flags: Int
    let crc: Int
    let compressedSize: Int
    let localOffset: Int
}

public enum LooseZipReader {
    /// The most entries listed; an archive declaring more is unreadable as a whole.
    public static let maxEntries = 0xFFFE

    /// Every central-directory entry with its verdict, in directory order.
    public static func entries(_ data: Data) throws -> [LooseZipEntry] {
        let bytes = Bytes(data)
        let end = try endRecord(bytes)
        let disk = bytes.u16(end + 4), centralDisk = bytes.u16(end + 6)
        let onDisk = bytes.u16(end + 8), total = bytes.u16(end + 10)
        let centralSize = bytes.u32(end + 12), centralOffset = bytes.u32(end + 16)
        if onDisk == 0xFFFF || total == 0xFFFF || centralSize == ZipFormat.maxUInt32 || centralOffset == ZipFormat.maxUInt32 {
            throw LooseZipError.unreadable("ZIP64")
        }
        guard disk == 0, centralDisk == 0, onDisk == total else { throw LooseZipError.unreadable("multiple disks") }
        guard total <= maxEntries, centralOffset + centralSize <= end else { throw LooseZipError.unreadable("central directory") }

        var result: [LooseZipEntry] = []
        result.reserveCapacity(total)
        var at = centralOffset
        for _ in 0..<total {
            guard at + ZipFormat.centralHeaderSize <= end, bytes.u32(at) == Int(ZipFormat.centralSignature) else {
                throw LooseZipError.unreadable("central directory")
            }
            let nameLength = bytes.u16(at + 28), extraLength = bytes.u16(at + 30), commentLength = bytes.u16(at + 32)
            let next = at + ZipFormat.centralHeaderSize + nameLength + extraLength + commentLength
            guard next <= end else { throw LooseZipError.unreadable("central directory") }
            result.append(entry(bytes, at: at, nameLength: nameLength))
            at = next
        }
        return result
    }

    /// The bytes of one `.file` entry of `data` (the same archive `entries` listed), at most `limit`.
    public static func data(of entry: LooseZipEntry, in data: Data, limit: Int) throws -> Data {
        guard entry.verdict == .file else { throw LooseZipError.notReadable }
        guard entry.size <= limit else { throw LooseZipError.tooLarge }
        let bytes = Bytes(data)
        let local = entry.localOffset
        guard local >= 0, local + ZipFormat.localHeaderSize <= bytes.count, bytes.u32(local) == Int(ZipFormat.localSignature) else {
            throw LooseZipError.damaged("local header")
        }
        let start = local + ZipFormat.localHeaderSize + bytes.u16(local + 26) + bytes.u16(local + 28)
        guard bytes.u16(local + 8) == entry.method, start + entry.compressedSize <= bytes.count else {
            throw LooseZipError.damaged("local header")
        }
        let raw = bytes.data(start, entry.compressedSize)
        let content: Data
        switch entry.method {
        case 0:
            guard entry.compressedSize == entry.size else { throw LooseZipError.damaged("sizes disagree") }
            content = raw
        case 8:
            content = try inflate(raw, size: entry.size)
        default:
            throw LooseZipError.notReadable
        }
        guard content.count == entry.size, Int(CRC32.checksum(content)) == entry.crc else {
            throw LooseZipError.damaged("checksum")
        }
        return content
    }

    /// Whether deflated entries can be read on this platform.
    public static var readsDeflate: Bool {
        #if canImport(Compression)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Private

    private static func entry(_ bytes: Bytes, at: Int, nameLength: Int) -> LooseZipEntry {
        let flags = bytes.u16(at + 8), method = bytes.u16(at + 10)
        let crc = bytes.u32(at + 16), compressed = bytes.u32(at + 20), size = bytes.u32(at + 24)
        let madeBy = bytes.u16(at + 4), externalAttributes = bytes.u32(at + 38), localOffset = bytes.u32(at + 42)
        let nameBytes = bytes.slice(at + ZipFormat.centralHeaderSize, nameLength)
        // A name that is not UTF-8 cannot be shown faithfully: its non-ASCII bytes become "?".
        let raw: String = String(bytes: nameBytes, encoding: .utf8) ?? String(decoding: nameBytes.map { (b: UInt8) -> UInt8 in b < 0x80 ? b : 0x3F }, as: UTF8.self)
        let isDirectory: Bool = raw.hasSuffix("/")
        let path: String = isDirectory ? String(raw.dropLast()) : raw
        func make(_ verdict: LooseZipEntry.Verdict) -> LooseZipEntry {
            LooseZipEntry(path: path, verdict: verdict, size: size, method: method, flags: flags, crc: crc,
                          compressedSize: compressed, localOffset: localOffset)
        }
        do {
            try ArchivePath.validate(path)
        } catch let error as ArchivePathError {
            return make(.unsafePath(error))
        } catch {
            return make(.unsafePath(.empty))
        }
        if isDirectory { return make(.directory) }
        if madeBy >> 8 == ZipFormat.unixHost {
            let fileType = (externalAttributes >> 16) & ZipFormat.fileTypeMask
            if fileType == 0o040000 { return make(.directory) }
            if fileType != 0 && fileType != ZipFormat.regularFileType { return make(.link) }
        }
        if flags & 0x0001 != 0 || flags & 0x0040 != 0 { return make(.encrypted) }
        if compressed == ZipFormat.maxUInt32 || size == ZipFormat.maxUInt32 || localOffset == ZipFormat.maxUInt32 {
            return make(.unsupportedMethod(method))   // ZIP64 sizes
        }
        guard method == 0 || (method == 8 && readsDeflate) else { return make(.unsupportedMethod(method)) }
        return make(.file)
    }

    /// The end record: the last 22 bytes, or further back when an archive comment reaches the end.
    private static func endRecord(_ bytes: Bytes) throws -> Int {
        let count = bytes.count
        guard count >= ZipFormat.endRecordSize else { throw LooseZipError.unreadable("not a ZIP archive") }
        let earliest = max(0, count - ZipFormat.endRecordSize - 0xFFFF)
        var at = count - ZipFormat.endRecordSize
        while at >= earliest {
            if bytes.u32(at) == Int(ZipFormat.endSignature), at + ZipFormat.endRecordSize + bytes.u16(at + 20) == count {
                return at
            }
            at -= 1
        }
        throw LooseZipError.unreadable("not a ZIP archive")
    }

    private static func inflate(_ raw: Data, size: Int) throws -> Data {
        #if canImport(Compression)
        if size == 0 { return Data() }
        guard !raw.isEmpty else { throw LooseZipError.damaged("no data") }
        let capacity = size + 1
        var output = Data(count: capacity)
        let written: Int = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            raw.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let d = dst.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let s = src.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(d, capacity, s, raw.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw LooseZipError.damaged("inflate") }
        output.count = written
        return output
        #else
        throw LooseZipError.notReadable
        #endif
    }
}
