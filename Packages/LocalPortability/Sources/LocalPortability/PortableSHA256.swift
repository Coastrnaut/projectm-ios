// PortableSHA256.swift — SHA-256 in plain Swift (FIPS 180-4). Moved here from PresetLibrary's
// ContentHash (PRE-012 research D3) for PRE-014 so the archive layer and the preset library share
// one implementation; `ContentHash.sha256Hex` delegates to it. CryptoKit does not exist on Linux,
// where the packages are tested.
import Foundation

public enum PortableSHA256 {
    /// Lowercase hex of the digest.
    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.withUnsafeBufferPointer { hex(of: digestWords($0)) }
    }

    public static func hex(_ data: Data) -> String {
        data.withUnsafeBytes { hex(of: digestWords($0.bindMemory(to: UInt8.self))) }
    }

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

    /// Full 64-byte blocks are read in place; only the tail is copied for padding.
    static func digestWords(_ bytes: UnsafeBufferPointer<UInt8>) -> [UInt32] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var w = [UInt32](repeating: 0, count: 64)
        func compress(_ block: UnsafeBufferPointer<UInt8>) {
            for i in 0..<16 {
                w[i] = UInt32(block[i * 4]) << 24 | UInt32(block[i * 4 + 1]) << 16 | UInt32(block[i * 4 + 2]) << 8 | UInt32(block[i * 4 + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ s0 &+ maj)
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        let fullBlocks = bytes.count / 64
        for block in 0..<fullBlocks {
            compress(UnsafeBufferPointer(rebasing: bytes[(block * 64)..<(block * 64 + 64)]))
        }
        var tail = Array(bytes[(fullBlocks * 64)...])
        tail.append(0x80)
        while tail.count % 64 != 56 { tail.append(0) }
        let bits = UInt64(bytes.count) &* 8
        for shift in stride(from: 56, through: 0, by: -8) { tail.append(UInt8((bits >> UInt64(shift)) & 0xFF)) }
        tail.withUnsafeBufferPointer { padded in
            for block in 0..<(padded.count / 64) {
                compress(UnsafeBufferPointer(rebasing: padded[(block * 64)..<(block * 64 + 64)]))
            }
        }
        return h
    }

    static func hex(of words: [UInt32]) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var out: [UInt8] = []
        out.reserveCapacity(words.count * 8)
        for word in words {
            for shift in stride(from: 28, through: 0, by: -4) { out.append(digits[Int((word >> UInt32(shift)) & 0xF)]) }
        }
        return String(decoding: out, as: UTF8.self)
    }
}
