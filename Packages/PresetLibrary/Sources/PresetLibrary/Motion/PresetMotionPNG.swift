// PresetMotionPNG.swift — roadmap PRE-005: the motion score travels inside the thumbnail PNG as a
// `tEXt` chunk (spec PRE-005-R4; research PRE-005-D4; contract C3), so it shares the picture's lifetime
// (PRE-002 invalidation, Clear Caches) without touching PRE-001's index. Plain Swift (CRC-32 included),
// so it is tested on Linux.
//
// Chunk: keyword `projectM-motion`, NUL, text "<score version>:<score>", inserted before IEND.
import Foundation

public enum PresetMotionPNG {
    public static let keyword = "projectM-motion"
    static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// The PNG with the score's chunk inserted before IEND (an existing motion chunk is replaced); nil
    /// when the bytes are not a well-formed PNG or the score is negative.
    public static func embed(score: Int, in png: Data) -> Data? {
        guard score >= 0, let chunks = chunks(png) else { return nil }
        guard let end = chunks.first(where: { (chunk: Chunk) -> Bool in chunk.type == "IEND" }) else { return nil }
        var payload: [UInt8] = Array(keyword.utf8)
        payload.append(0)
        payload.append(contentsOf: Array("\(PresetMotionScore.version):\(score)".utf8))
        let bytes: [UInt8] = [UInt8](png)
        var output: [UInt8] = Array(bytes[0..<8])
        for chunk in chunks where chunk.type != "IEND" && !isMotion(chunk, in: bytes) {
            output.append(contentsOf: bytes[chunk.start..<chunk.end])
        }
        output.append(contentsOf: Self.chunk(type: "tEXt", data: payload))
        output.append(contentsOf: bytes[end.start..<end.end])
        return Data(output)
    }

    /// The score in the PNG's motion chunk; nil without one, for another score version or bad text.
    public static func score(in png: Data) -> Int? {
        guard let chunks = chunks(png) else { return nil }
        let bytes: [UInt8] = [UInt8](png)
        for chunk in chunks where isMotion(chunk, in: bytes) {
            let text: [UInt8] = Array(bytes[(chunk.dataStart + keyword.utf8.count + 1)..<chunk.dataEnd])
            let parts: [Substring] = String(decoding: text, as: UTF8.self).split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, Int(parts[0]) == PresetMotionScore.version,
                  let value = Int(parts[1]), value >= 0 else { return nil }
            return value
        }
        return nil
    }

    // MARK: - Chunks

    struct Chunk {
        let type: String
        /// The whole chunk: length, type, data, CRC.
        let start: Int
        let end: Int
        let dataStart: Int
        let dataEnd: Int
    }

    /// The chunks of a PNG; nil when the signature or a length is wrong.
    static func chunks(_ png: Data) -> [Chunk]? {
        let bytes: [UInt8] = [UInt8](png)
        guard bytes.count >= 8, Array(bytes[0..<8]) == signature else { return nil }
        var result: [Chunk] = []
        var offset = 8
        while offset + 12 <= bytes.count {
            let length: Int = (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16) | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
            let end: Int = offset + 12 + length
            guard length >= 0, end <= bytes.count else { return nil }
            let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            result.append(Chunk(type: type, start: offset, end: end, dataStart: offset + 8, dataEnd: offset + 8 + length))
            offset = end
            if type == "IEND" { break }
        }
        return result.isEmpty ? nil : result
    }

    static func isMotion(_ chunk: Chunk, in bytes: [UInt8]) -> Bool {
        guard chunk.type == "tEXt" else { return false }
        let prefix: [UInt8] = Array(keyword.utf8) + [0]
        guard chunk.dataEnd - chunk.dataStart >= prefix.count else { return false }
        return Array(bytes[chunk.dataStart..<(chunk.dataStart + prefix.count)]) == prefix
    }

    static func chunk(type: String, data: [UInt8]) -> [UInt8] {
        let count = UInt32(data.count)
        var out: [UInt8] = [UInt8(count >> 24), UInt8((count >> 16) & 0xFF), UInt8((count >> 8) & 0xFF), UInt8(count & 0xFF)]
        let typed: [UInt8] = Array(type.utf8) + data
        out.append(contentsOf: typed)
        let crc: UInt32 = crc32(typed)
        out.append(contentsOf: [UInt8(crc >> 24), UInt8((crc >> 16) & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF)])
        return out
    }

    /// PNG's CRC-32 (ISO 3309, polynomial 0xEDB88320).
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
