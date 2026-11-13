// PresetArchive.swift — reads pack presets out of PresetArchive.bin (feature 002, research R-30;
// format: scripts/build_preset_index.py). Chunks are raw deflate (RFC 1951), decompressed with
// Foundation's public `decompressed(using: .zlib)`; the last chunk read is cached so stepping
// through a folder rarely decompresses twice. PERF-006: memory pressure drops that chunk.
import Foundation
import PresetLibrary

final class PresetArchive {
    enum ArchiveError: Error, Equatable {
        case badHeader
        case unknownPreset(String)
        case corruptChunk(Int)
    }

    private struct Chunk { let offset: Int; let compressedLength: Int; let rawLength: Int }
    private struct Entry { let chunk: Int; let offset: Int; let length: Int }

    private let data: Data
    private let chunks: [Chunk]
    private var entries: [String: Entry] = [:]
    private var cache: (index: Int, data: Data)?

    /// `packIds` are the ids of the pack presets in PresetIndex.json order (the archive's order).
    init(url: URL, packIds: [String]) throws {
        let bytes = try Data(contentsOf: url, options: .alwaysMapped)
        func u32(_ at: Int) -> Int { Int(bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self).littleEndian }) }
        func u64(_ at: Int) -> Int { Int(bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt64.self).littleEndian }) }
        guard bytes.count >= 20, bytes.prefix(4) == Data("PMPA".utf8), u32(4) == 1 else { throw ArchiveError.badHeader }
        let count = u32(8), chunkCount = u32(16)
        guard count == packIds.count, bytes.count >= 20 + 16 * chunkCount + 12 * count else { throw ArchiveError.badHeader }
        data = bytes
        chunks = (0..<chunkCount).map { i in
            let at = 20 + 16 * i
            return Chunk(offset: u64(at), compressedLength: u32(at + 8), rawLength: u32(at + 12))
        }
        let table = 20 + 16 * chunkCount
        for (i, id) in packIds.enumerated() {
            let at = table + 12 * i
            entries[id] = Entry(chunk: u32(at), offset: u32(at + 4), length: u32(at + 8))
        }
    }

    /// The preset file's contents.
    func contents(of id: String) throws -> Data {
        guard let entry = entries[id] else { throw ArchiveError.unknownPreset(id) }
        let raw = try chunkData(entry.chunk)
        guard entry.offset + entry.length <= raw.count else { throw ArchiveError.corruptChunk(entry.chunk) }
        return raw.subdata(in: entry.offset..<(entry.offset + entry.length))
    }

    /// PERF-006-R11: drops the decompressed chunk (memory pressure); returns its size in bytes. The
    /// next read decompresses again.
    @discardableResult
    func dropCache() -> Int {
        let bytes = cache?.data.count ?? 0
        cache = nil
        return bytes
    }

    /// Bytes of the decompressed chunk held now.
    var cachedBytes: Int { cache?.data.count ?? 0 }

    private func chunkData(_ index: Int) throws -> Data {
        if let cache, cache.index == index { return cache.data }
        guard index < chunks.count else { throw ArchiveError.corruptChunk(index) }
        let chunk = chunks[index]
        let compressed = data.subdata(in: chunk.offset..<(chunk.offset + chunk.compressedLength))
        let raw = try (compressed as NSData).decompressed(using: .zlib) as Data
        guard raw.count == chunk.rawLength else { throw ArchiveError.corruptChunk(index) }
        cache = (index, raw)
        return raw
    }
}
