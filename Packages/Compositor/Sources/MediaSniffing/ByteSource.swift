// ByteSource.swift — bounded, bounds-checked access to untrusted bytes (MED-014-R13; research
// MED-014-D3; contracts/safe-decoder.md). Plain Swift (Foundation only), every platform.
//
// * `MediaSniffError` is why bytes are not a well-formed file of their format; the layer targets map
//   it to their own typed import errors (data-model "MediaSniffError").
// * `ByteSource` is random access with clamped reads: a read never goes past the end and returns
//   fewer bytes there, so a length field can never make a sniffer read or allocate beyond the data.
//   `DataByteSource` wraps bytes in memory; `FileByteSource` reads a file through `FileHandle`
//   (only the few header bytes asked for, so a 500 MB movie is never loaded).
// * `ByteView` is the in-memory view the image sniffer walks: every accessor returns nil outside
//   the buffer instead of trapping.
import Foundation

/// Why bytes are not a well-formed file of the format they claim.
public enum MediaSniffError: Error, Sendable, Equatable {
    /// No bytes at all.
    case empty
    /// The first bytes are not this kind of container (movies; images return `.other` instead).
    case unrecognized
    /// A length or offset points past the end, or the end marker is missing.
    case truncated
    /// A field is illegal, a checksum does not match, or a walk bound was exceeded.
    case corrupt
    /// The bytes could not be read.
    case unreadable
}

/// Random-access bytes with clamped reads.
public protocol ByteSource {
    /// The number of bytes.
    var count: Int64 { get }
    /// Up to `length` bytes at `offset` (fewer at the end, none past it).
    func bytes(at offset: Int64, length: Int) throws(MediaSniffError) -> [UInt8]
}

/// Bytes in memory.
public struct DataByteSource: ByteSource {
    public let data: Data

    public init(_ data: Data) { self.data = data }

    public var count: Int64 { Int64(data.count) }

    public func bytes(at offset: Int64, length: Int) throws(MediaSniffError) -> [UInt8] {
        guard offset >= 0, length > 0, offset < count else { return [] }
        let start = data.startIndex + Int(offset)
        let end = start + Int(min(Int64(length), count - offset))
        return [UInt8](data[start..<end])
    }
}

/// A file read through `FileHandle`, a few bytes at a time.
public final class FileByteSource: ByteSource {
    private let handle: FileHandle
    public let count: Int64

    public init(url: URL) throws(MediaSniffError) {
        do {
            handle = try FileHandle(forReadingFrom: url)
            count = Int64(clamping: try handle.seekToEnd())
        } catch {
            throw .unreadable
        }
    }

    deinit { try? handle.close() }

    public func bytes(at offset: Int64, length: Int) throws(MediaSniffError) -> [UInt8] {
        guard offset >= 0, length > 0, offset < count else { return [] }
        let wanted = Int(min(Int64(length), count - offset))
        do {
            try handle.seek(toOffset: UInt64(offset))
            return [UInt8](try handle.read(upToCount: wanted) ?? Data())
        } catch {
            throw .unreadable
        }
    }
}

/// A bounds-checked view of bytes in memory (big-endian accessors; nil outside the buffer).
struct ByteView {
    let base: UnsafeRawBufferPointer

    var count: Int { base.count }

    func u8(_ i: Int) -> UInt8? { i >= 0 && i < base.count ? base[i] : nil }

    func u16(_ i: Int) -> Int? {
        guard i >= 0, i <= base.count - 2 else { return nil }
        return Int(base[i]) << 8 | Int(base[i + 1])
    }

    func u32(_ i: Int) -> UInt32? {
        guard i >= 0, i <= base.count - 4 else { return nil }
        return UInt32(base[i]) << 24 | UInt32(base[i + 1]) << 16 | UInt32(base[i + 2]) << 8 | UInt32(base[i + 3])
    }

    func hasPrefix(_ prefix: [UInt8]) -> Bool {
        guard base.count >= prefix.count else { return false }
        for (i, b) in prefix.enumerated() where base[i] != b { return false }
        return true
    }
}

/// Big-endian reads from an array (nil outside it).
extension Array where Element == UInt8 {
    func u16(_ i: Int) -> Int? {
        guard i >= 0, i <= count - 2 else { return nil }
        return Int(self[i]) << 8 | Int(self[i + 1])
    }

    func u32(_ i: Int) -> UInt32? {
        guard i >= 0, i <= count - 4 else { return nil }
        return UInt32(self[i]) << 24 | UInt32(self[i + 1]) << 16 | UInt32(self[i + 2]) << 8 | UInt32(self[i + 3])
    }

    func u64(_ i: Int) -> UInt64? {
        guard let high = u32(i), let low = u32(i + 4) else { return nil }
        return UInt64(high) << 32 | UInt64(low)
    }
}

/// A four-character code as a big-endian number (`"moov"` → 0x6D6F6F76).
func fourCC(_ code: StaticString) -> UInt32 {
    precondition(code.utf8CodeUnitCount == 4)
    let p = code.utf8Start
    return UInt32(p[0]) << 24 | UInt32(p[1]) << 16 | UInt32(p[2]) << 8 | UInt32(p[3])
}

/// A four-character code as text (diagnostics, tests).
public func fourCCString(_ code: UInt32) -> String {
    let bytes = [UInt8(code >> 24 & 0xFF), UInt8(code >> 16 & 0xFF), UInt8(code >> 8 & 0xFF), UInt8(code & 0xFF)]
    return String(decoding: bytes, as: UTF8.self)
}
