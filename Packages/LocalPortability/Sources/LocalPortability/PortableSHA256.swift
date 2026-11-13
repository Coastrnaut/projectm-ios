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

    static let initialState: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]

    /// One 64-byte block into `h`; `w` is the caller's 64-word scratch schedule (reused, no allocation).
    static func compress(_ h: inout [UInt32], _ w: inout [UInt32], _ block: UnsafeBufferPointer<UInt8>) {
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

    /// The padding for a message of `length` bytes whose last `tail` bytes (< 64) are not yet
    /// compressed: tail, 0x80, zeros, the bit length (64 or 128 bytes).
    static func paddedTail(_ tail: [UInt8], length: Int) -> [UInt8] {
        var padded = tail
        padded.append(0x80)
        while padded.count % 64 != 56 { padded.append(0) }
        let bits = UInt64(length) &* 8
        for shift in stride(from: 56, through: 0, by: -8) { padded.append(UInt8((bits >> UInt64(shift)) & 0xFF)) }
        return padded
    }

    /// Full 64-byte blocks are read in place; only the tail is copied for padding.
    static func digestWords(_ bytes: UnsafeBufferPointer<UInt8>) -> [UInt32] {
        var h = initialState
        var w = [UInt32](repeating: 0, count: 64)
        let fullBlocks = bytes.count / 64
        for block in 0..<fullBlocks {
            compress(&h, &w, UnsafeBufferPointer(rebasing: bytes[(block * 64)..<(block * 64 + 64)]))
        }
        let padded = paddedTail(Array(bytes[(fullBlocks * 64)...]), length: bytes.count)
        padded.withUnsafeBufferPointer { (p: UnsafeBufferPointer<UInt8>) in
            for block in 0..<(p.count / 64) {
                compress(&h, &w, UnsafeBufferPointer(rebasing: p[(block * 64)..<(block * 64 + 64)]))
            }
        }
        return h
    }

    /// Incremental SHA-256 (FILE-002-R6; research FILE-002-D3): feed the bytes in chunks of any size,
    /// then `finalize()`. Its state is fixed-size (8 words, a 64-word schedule, fewer than 64 pending
    /// bytes and a length), so hashing a file chunk by chunk needs no memory proportional to the file.
    /// Gives the same digest as `hex(_:)` for every split of the input.
    public struct Hasher: Sendable {
        private var h = PortableSHA256.initialState
        private var w = [UInt32](repeating: 0, count: 64)
        private var pending: [UInt8] = []
        private var length = 0

        public init() {
            pending.reserveCapacity(64)
        }

        public mutating func update(_ data: Data) {
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in update(raw.bindMemory(to: UInt8.self)) }
        }

        public mutating func update(_ bytes: [UInt8]) {
            bytes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt8>) in update(buffer) }
        }

        public mutating func update(_ bytes: UnsafeBufferPointer<UInt8>) {
            length += bytes.count
            var start = 0
            if !pending.isEmpty {
                let take = min(64 - pending.count, bytes.count)
                pending.append(contentsOf: bytes[0..<take])
                start = take
                guard pending.count == 64 else { return }
                pending.withUnsafeBufferPointer { (block: UnsafeBufferPointer<UInt8>) in PortableSHA256.compress(&h, &w, block) }
                pending.removeAll(keepingCapacity: true)
            }
            while start + 64 <= bytes.count {
                PortableSHA256.compress(&h, &w, UnsafeBufferPointer(rebasing: bytes[start..<(start + 64)]))
                start += 64
            }
            if start < bytes.count { pending.append(contentsOf: bytes[start...]) }
        }

        /// Lowercase hex of the digest. The hasher can be finalized more than once (it is a value).
        public func finalize() -> String {
            var state = h
            var schedule = w
            let padded = PortableSHA256.paddedTail(pending, length: length)
            padded.withUnsafeBufferPointer { (p: UnsafeBufferPointer<UInt8>) in
                for block in 0..<(p.count / 64) {
                    PortableSHA256.compress(&state, &schedule, UnsafeBufferPointer(rebasing: p[(block * 64)..<(block * 64 + 64)]))
                }
            }
            return PortableSHA256.hex(of: state)
        }
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
