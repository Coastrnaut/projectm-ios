// ContentHash.swift — SHA-1 and SHA-256 in plain Swift (PRE-012 research D3). Since PRE-014 the
// SHA-256 implementation is LocalPortability's `PortableSHA256`; this type keeps its API.
//
// The package is tested on Linux, where CryptoKit does not exist, and the inputs are small (a
// preset file is at most 512 KiB). SHA-256 names the stored copy of an imported preset. The git
// blob id (SHA-1 over "blob <length>\0" + content) is what scripts/build_preset_index.py writes
// into PresetIndex.json and what PresetBlocklist.json holds, so an imported file can be compared
// with the built-in library and the takedown list. SHA-1 is used here as that identifier only,
// not as a security control.
import Foundation
import LocalPortability

public enum ContentHash {
    /// PRE-014: the SHA-256 code lives in LocalPortability, shared with the archive layer.
    public static func sha256Hex(_ bytes: [UInt8]) -> String { PortableSHA256.hex(bytes) }
    public static func sha1Hex(_ bytes: [UInt8]) -> String { hex(sha1(bytes)) }

    /// The id `git hash-object` gives the content.
    public static func gitBlobSHA1Hex(_ bytes: [UInt8]) -> String {
        sha1Hex(Array("blob \(bytes.count)\u{0}".utf8) + bytes)
    }

    public static func isHex(_ text: String, count: Int) -> Bool {
        text.utf8.count == count && text.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    private static func hex(_ words: [UInt32]) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var out: [UInt8] = []
        out.reserveCapacity(words.count * 8)
        for word in words {
            for shift in stride(from: 28, through: 0, by: -4) {
                out.append(digits[Int((word >> UInt32(shift)) & 0xF)])
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// The message followed by 0x80, zeros and the bit length, in 64-byte blocks.
    private static func padded(_ bytes: [UInt8]) -> [UInt8] {
        var message = bytes
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        let bits = UInt64(bytes.count) &* 8
        for shift in stride(from: 56, through: 0, by: -8) { message.append(UInt8((bits >> UInt64(shift)) & 0xFF)) }
        return message
    }

    private static func word(_ message: [UInt8], _ at: Int) -> UInt32 {
        UInt32(message[at]) << 24 | UInt32(message[at + 1]) << 16 | UInt32(message[at + 2]) << 8 | UInt32(message[at + 3])
    }

    private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }

    static func sha1(_ bytes: [UInt8]) -> [UInt32] {
        var h: [UInt32] = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
        let message = padded(bytes)
        var w = [UInt32](repeating: 0, count: 80)
        for block in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 { w[i] = word(message, block + i * 4) }
            for i in 16..<80 { w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1) }
            var (a, b, c, d, e) = (h[0], h[1], h[2], h[3], h[4])
            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0..<20: f = (b & c) | (~b & d); k = 0x5A827999
                case 20..<40: f = b ^ c ^ d; k = 0x6ED9EBA1
                case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC
                default: f = b ^ c ^ d; k = 0xCA62C1D6
                }
                let t = rotl(a, 5) &+ f &+ e &+ k &+ w[i]
                (e, d, c, b, a) = (d, c, rotl(b, 30), a, t)
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e
        }
        return h
    }
}
