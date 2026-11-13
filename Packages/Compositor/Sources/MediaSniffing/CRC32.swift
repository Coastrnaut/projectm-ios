// CRC32.swift — the CRC-32 of PNG chunks (ISO 3309 / ITU-T V.42 polynomial 0xEDB88320, reflected;
// research MED-014-D2). Plain Swift, every platform.

public enum CRC32 {
    static let table: [UInt32] = (0..<256).map { (n: Int) -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    /// The CRC of `view[range]` (the range must lie inside the view).
    static func checksum(_ view: ByteView, _ range: Range<Int>) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        table.withUnsafeBufferPointer { (t: UnsafeBufferPointer<UInt32>) in
            for i in range { c = t[Int((c ^ UInt32(view.base[i])) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }

    /// The CRC of a byte array (fixtures, tests).
    public static func checksum(_ bytes: [UInt8]) -> UInt32 {
        bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> UInt32 in checksum(ByteView(base: raw), 0..<raw.count) }
    }
}
