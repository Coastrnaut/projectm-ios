// ContentHash.swift — SHA-1 and SHA-256 in plain Swift (PRE-012 research D3).
//
// The package is tested on Linux, where CryptoKit does not exist, and the inputs are small (a
// preset file is at most 512 KiB). SHA-256 names the stored copy of an imported preset. The git
// blob id (SHA-1 over "blob <length>\0" + content) is what scripts/build_preset_index.py writes
// into PresetIndex.json and what PresetBlocklist.json holds, so an imported file can be compared
// with the built-in library and the takedown list. SHA-1 is used here as that identifier only,
// not as a security control.
import Foundation

public enum ContentHash {
    public static func sha256Hex(_ bytes: [UInt8]) -> String { hex(sha256(bytes)) }
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
    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

    private static let k256: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func sha256(_ bytes: [UInt8]) -> [UInt32] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        let message = padded(bytes)
        var w = [UInt32](repeating: 0, count: 64)
        for block in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 { w[i] = word(message, block + i * 4) }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k256[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        return h
    }

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
