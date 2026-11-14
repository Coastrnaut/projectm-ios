// MediaContentHash.swift — FILE-008-R2 (research FILE-008-D2): the SHA-256 of a file, read in 1 MiB
// chunks so a large video is never held in memory. CryptoKit on Apple platforms (hardware-accelerated),
// `PortableSHA256.Hasher` elsewhere (Linux CI); both give the same lowercase hex digest.
import Foundation
#if canImport(CryptoKit) && !LOCALPORTABILITY_NO_CRYPTOKIT
import CryptoKit
#endif

public enum MediaContentHash {
    public static let chunkSize = 1 << 20

    public struct Digest: Sendable, Equatable {
        /// 64 lowercase hex characters.
        public let sha256: String
        public let byteCount: Int64
    }

    /// Streams the file at `url`. Throws when it cannot be opened or read.
    public static func digest(ofFileAt url: URL) throws -> Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var count: Int64 = 0
        #if canImport(CryptoKit) && !LOCALPORTABILITY_NO_CRYPTOKIT
        var hasher = SHA256()
        #else
        var hasher = PortableSHA256.Hasher()
        #endif
        while true {
            let chunk: Data = try autoreleasepoolIfAvailable { () throws -> Data in
                try handle.read(upToCount: chunkSize) ?? Data()
            }
            if chunk.isEmpty { break }
            count += Int64(chunk.count)
            hasher.update(data: chunk)
        }
        #if canImport(CryptoKit) && !LOCALPORTABILITY_NO_CRYPTOKIT
        let hex = hasher.finalize().map { (byte: UInt8) -> String in
            let digits: [Character] = Array("0123456789abcdef")
            return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
        }.joined()
        #else
        let hex = hasher.finalize()
        #endif
        return Digest(sha256: hex, byteCount: count)
    }

    /// True for 64 lowercase hex characters.
    public static func isSHA256Hex(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (c: UInt8) -> Bool in (c >= 48 && c <= 57) || (c >= 97 && c <= 102) }
    }
}

#if !canImport(CryptoKit) || LOCALPORTABILITY_NO_CRYPTOKIT
extension PortableSHA256.Hasher {
    mutating func update(data: Data) { update(data) }
}
#endif

#if canImport(ObjectiveC)
@inline(__always)
func autoreleasepoolIfAvailable<T>(_ body: () throws -> T) rethrows -> T { try autoreleasepool(invoking: body) }
#else
@inline(__always)
func autoreleasepoolIfAvailable<T>(_ body: () throws -> T) rethrows -> T { try body() }
#endif
