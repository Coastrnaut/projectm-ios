// CRC32.swift — CRC-32 (IEEE 802.3, reflected polynomial 0xEDB88320), the checksum every ZIP
// entry carries (PRE-014-R7; research D2). Plain Swift so it runs on Linux too.
import Foundation

public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1 }
        return value
    }

    /// The checksum of `bytes`. Pass an earlier result as `initial` to continue over more bytes.
    public static func checksum<Bytes: Sequence>(_ bytes: Bytes, initial: UInt32 = 0) -> UInt32 where Bytes.Element == UInt8 {
        var crc = ~initial
        table.withUnsafeBufferPointer { table in
            for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        }
        return ~crc
    }

    /// The checksum of `data`, read through its contiguous storage.
    public static func checksum(_ data: Data, initial: UInt32 = 0) -> UInt32 {
        data.withUnsafeBytes { checksum($0.bindMemory(to: UInt8.self), initial: initial) }
    }
}
