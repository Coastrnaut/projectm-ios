// MovieHeaderTimes.swift — FILE-008-R6 (research FILE-008-D4): zero the creation and modification
// times in a QuickTime/MP4 movie's headers (`mvhd`, every `tkhd`, every `mdhd`) in place.
//
// The passthrough export behind `VideoSanitizer` writes the current time into these six fields, so two
// imports of one file never gave equal bytes and could not be deduplicated by content hash. Zero times
// are valid (1904-01-01) and change no picture or timing; they also drop the import time from the
// stored copy. Bounded: the `moov` box must be at most 64 MiB, at most 4,096 boxes are visited, and a
// malformed size stops the walk without writing. Plain Swift and FileHandle; builds on Linux.
import Foundation

public enum MovieHeaderTimes {
    public static let maxMoovBytes = 64 << 20
    public static let maxBoxes = 4096

    public struct Field: Equatable, Sendable {
        /// Offset from the start of the bytes given (or of the file).
        public let offset: Int
        /// 4 (version 0) or 8 (version 1).
        public let width: Int
    }

    /// The time fields inside the payload of a `moov` box (`bytes` is the payload, not its header).
    /// `base` is added to every offset.
    public static func fields(inMoovPayload bytes: [UInt8], base: Int = 0) -> [Field] {
        var result: [Field] = []
        var visited = 0
        walk(bytes, start: 0, end: bytes.count, base: base, visited: &visited, into: &result)
        return result
    }

    private static let containers: Set<String> = ["trak", "mdia"]
    private static let headers: Set<String> = ["mvhd", "tkhd", "mdhd"]

    private static func walk(_ bytes: [UInt8], start: Int, end: Int, base: Int, visited: inout Int, into result: inout [Field]) {
        var position = start
        while position + 8 <= end, visited < maxBoxes {
            visited += 1
            guard let box = header(bytes, at: position, limit: end) else { return }
            let payload = position + box.headerSize
            if headers.contains(box.type), payload + 4 <= box.end {
                let version = bytes[payload]
                let width = version == 1 ? 8 : 4
                let creation = payload + 4
                if creation + 2 * width <= box.end {
                    result.append(Field(offset: base + creation, width: width))
                    result.append(Field(offset: base + creation + width, width: width))
                }
            } else if containers.contains(box.type) {
                walk(bytes, start: payload, end: box.end, base: base, visited: &visited, into: &result)
            }
            position = box.end
        }
    }

    private struct BoxHeader {
        let type: String
        let headerSize: Int
        let end: Int
    }

    private static func header(_ bytes: [UInt8], at position: Int, limit: Int) -> BoxHeader? {
        let size32 = readUInt32(bytes, position)
        let type = String(decoding: bytes[(position + 4)..<(position + 8)], as: UTF8.self)
        var headerSize = 8
        var size: UInt64 = UInt64(size32)
        if size32 == 1 {
            guard position + 16 <= limit else { return nil }
            size = readUInt64(bytes, position + 8)
            headerSize = 16
        } else if size32 == 0 {
            size = UInt64(limit - position)
        }
        guard size >= UInt64(headerSize), size <= UInt64(limit - position) else { return nil }
        return BoxHeader(type: type, headerSize: headerSize, end: position + Int(size))
    }

    private static func readUInt32(_ b: [UInt8], _ i: Int) -> UInt32 {
        let high = UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16
        let low = UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
        return high | low
    }

    private static func readUInt64(_ b: [UInt8], _ i: Int) -> UInt64 {
        UInt64(readUInt32(b, i)) << 32 | UInt64(readUInt32(b, i + 4))
    }

    public enum Failure: Error, Equatable { case unreadable, noMovieBox, tooLarge }

    /// Zeroes every header time of the movie at `url` in place; returns how many fields were zeroed.
    @discardableResult
    public static func zero(fileAt url: URL) throws -> Int {
        let handle: FileHandle
        do {
            handle = try FileHandle(forUpdating: url)
        } catch {
            throw Failure.unreadable
        }
        defer { try? handle.close() }
        guard let length = try? handle.seekToEnd() else { throw Failure.unreadable }
        var position: UInt64 = 0
        var visited = 0
        while position + 8 <= length, visited < maxBoxes {
            visited += 1
            try handle.seek(toOffset: position)
            guard let head = try handle.read(upToCount: 16), head.count >= 8 else { throw Failure.unreadable }
            let bytes = [UInt8](head)
            let size32 = readUInt32(bytes, 0)
            let type = String(decoding: bytes[4..<8], as: UTF8.self)
            var headerSize: UInt64 = 8
            var size = UInt64(size32)
            if size32 == 1 {
                guard bytes.count >= 16 else { throw Failure.unreadable }
                size = readUInt64(bytes, 8)
                headerSize = 16
            } else if size32 == 0 {
                size = length - position
            }
            guard size >= headerSize, size <= length - position else { throw Failure.unreadable }
            if type == "moov" {
                let payloadSize = size - headerSize
                guard payloadSize <= UInt64(maxMoovBytes) else { throw Failure.tooLarge }
                let payloadStart = position + headerSize
                try handle.seek(toOffset: payloadStart)
                guard let payload = try handle.read(upToCount: Int(payloadSize)), payload.count == Int(payloadSize) else { throw Failure.unreadable }
                let found = fields(inMoovPayload: [UInt8](payload))
                for field in found {
                    try handle.seek(toOffset: payloadStart + UInt64(field.offset))
                    try handle.write(contentsOf: Data(count: field.width))
                }
                try handle.synchronize()
                return found.count
            }
            position += size
        }
        throw Failure.noMovieBox
    }
}
