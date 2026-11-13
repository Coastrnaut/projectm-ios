// Test helpers: read and patch the little-endian fields of a stored ZIP built by the tests.
import Foundation

enum ZipBytes {
    static func u16(_ data: Data, _ at: Int) -> Int { Int(data[data.startIndex + at]) | Int(data[data.startIndex + at + 1]) << 8 }
    static func u32(_ data: Data, _ at: Int) -> Int { u16(data, at) | u16(data, at + 2) << 16 }

    static func set16(_ data: inout Data, _ at: Int, _ value: Int) {
        data[data.startIndex + at] = UInt8(value & 0xFF)
        data[data.startIndex + at + 1] = UInt8((value >> 8) & 0xFF)
    }

    static func set32(_ data: inout Data, _ at: Int, _ value: Int) {
        set16(&data, at, value & 0xFFFF)
        set16(&data, at + 2, (value >> 16) & 0xFFFF)
    }

    static func endRecord(_ data: Data) -> Int { data.count - 22 }
    static func centralOffset(_ data: Data) -> Int { u32(data, endRecord(data) + 16) }

    /// Offsets of every central header, in order.
    static func centralHeaders(_ data: Data) -> [Int] {
        var offsets: [Int] = []
        var at = centralOffset(data)
        for _ in 0..<u16(data, endRecord(data) + 10) {
            offsets.append(at)
            at += 46 + u16(data, at + 28) + u16(data, at + 30) + u16(data, at + 32)
        }
        return offsets
    }

    static func localHeader(_ data: Data, entry: Int) -> Int { u32(data, centralHeaders(data)[entry] + 42) }

    static func dataStart(_ data: Data, entry: Int) -> Int {
        let local = localHeader(data, entry: entry)
        return local + 30 + u16(data, local + 26) + u16(data, local + 28)
    }
}
