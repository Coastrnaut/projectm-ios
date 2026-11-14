// PresetLibrarySnapshot.swift — PERF-009 (research PERF-009-D7): the prepared bundled library as a compact binary
// snapshot, so a warm launch skips the JSON decode, the sort and the per-preset search-key folding. Only the bundled
// library is written (the user's imported presets are added afterwards, PERF-009-R1); the home tree and the lookup
// table are rebuilt from the decoded presets. Little-endian; every length is checked, so a truncated or altered
// snapshot throws (the warm cache then deletes it and rebuilds).
//
// Layout (format 1): "PMWS", UInt32 format, packs JSON (length-prefixed), UInt32 count, then per preset id, name,
// author, source, path, hash (length-prefixed UTF-8), folder parts and flash rules (UInt32 count + strings), search
// key; then UInt32 archive count and UInt32 indices into the presets.
import Foundation

extension PresetLibrary {
    public static let snapshotFormatVersion = 1
    static let snapshotMagic: [UInt8] = Array("PMWS".utf8)

    /// The bundled part of this library (never the user's imported presets).
    public func snapshotData() throws -> Data {
        var writer = SnapshotWriter()
        writer.bytes(Self.snapshotMagic)
        writer.uint32(UInt32(Self.snapshotFormatVersion))
        writer.blob(try JSONEncoder().encode(packs))
        let bundled = presets.prefix(builtInCount)
        writer.uint32(UInt32(bundled.count))
        for (index, preset) in bundled.enumerated() {
            writer.string(preset.id)
            writer.string(preset.name)
            writer.string(preset.author)
            writer.string(preset.source)
            writer.string(preset.path)
            writer.string(preset.hash)
            writer.strings(preset.folder)
            writer.strings(preset.flash ?? [])
            writer.string(searchKeys[index])
        }
        let positions: [Int] = archiveOrder.compactMap { (id: String) -> Int? in byId[id] }
        guard positions.count == archiveOrder.count else { throw PresetLibraryError.badArchiveTable }
        writer.uint32(UInt32(positions.count))
        for position in positions { writer.uint32(UInt32(position)) }
        return writer.data
    }

    /// A library from `snapshotData()`. Throws `SnapshotError` on any malformed input.
    public convenience init(snapshot: Data) throws {
        var reader = SnapshotReader(snapshot)
        guard try reader.bytes(4) == Self.snapshotMagic else { throw SnapshotError.malformed }
        guard try reader.uint32() == UInt32(Self.snapshotFormatVersion) else { throw SnapshotError.unsupportedFormat }
        let packs = try JSONDecoder().decode([PresetPackInfo].self, from: try reader.blob())
        let count = Int(try reader.uint32())
        guard count <= reader.remaining / 4 else { throw SnapshotError.malformed }   // each preset takes more than 4 bytes
        var presets: [IndexedPreset] = []
        var keys: [String] = []
        presets.reserveCapacity(count)
        keys.reserveCapacity(count)
        for _ in 0..<count {
            let id = try reader.string(), name = try reader.string(), author = try reader.string()
            let source = try reader.string(), path = try reader.string(), hash = try reader.string()
            let folder = try reader.strings()
            let flash = try reader.strings()
            presets.append(IndexedPreset(id: id, name: name, author: author, source: source, folder: folder, path: path,
                                         hash: hash, flash: flash.isEmpty ? nil : flash))
            keys.append(try reader.string())
        }
        let archiveCount = Int(try reader.uint32())
        guard archiveCount <= reader.remaining / 4 else { throw SnapshotError.malformed }
        var archiveOrder: [String] = []
        archiveOrder.reserveCapacity(archiveCount)
        for _ in 0..<archiveCount {
            let position = Int(try reader.uint32())
            guard position < presets.count else { throw SnapshotError.malformed }
            archiveOrder.append(presets[position].id)
        }
        guard reader.remaining == 0 else { throw SnapshotError.malformed }
        let byId = Dictionary(presets.enumerated().map { (pair: (offset: Int, element: IndexedPreset)) -> (String, Int) in
            (pair.element.id, pair.offset)
        }, uniquingKeysWith: { (first: Int, _: Int) -> Int in first })
        self.init(presets: presets, packs: packs, home: Self.buildHome(presets, packs: packs), archiveOrder: archiveOrder,
                  byId: byId, searchKeys: keys, lockedSources: Set(packs.filter(\.locked).map(\.id)),
                  builtInCount: presets.count)
    }

    public enum SnapshotError: Error, Equatable {
        case malformed
        case unsupportedFormat
    }
}

struct SnapshotWriter {
    private(set) var data = Data()

    mutating func bytes(_ bytes: [UInt8]) { data.append(contentsOf: bytes) }

    mutating func uint32(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { (raw: UnsafeRawBufferPointer) in data.append(contentsOf: raw) }
    }

    mutating func blob(_ blob: Data) {
        uint32(UInt32(blob.count))
        data.append(blob)
    }

    mutating func string(_ text: String) { blob(Data(text.utf8)) }

    mutating func strings(_ texts: [String]) {
        uint32(UInt32(texts.count))
        for text in texts { string(text) }
    }
}

struct SnapshotReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    var remaining: Int { bytes.count - offset }

    mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, count <= remaining else { throw PresetLibrary.SnapshotError.malformed }
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }

    mutating func uint32() throws -> UInt32 {
        guard remaining >= 4 else { throw PresetLibrary.SnapshotError.malformed }
        let value = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        offset += 4
        return value
    }

    mutating func blob() throws -> Data { Data(try bytes(Int(try uint32()))) }

    mutating func string() throws -> String {
        let length = Int(try uint32())
        guard length <= remaining else { throw PresetLibrary.SnapshotError.malformed }
        defer { offset += length }
        guard let text = String(validating: bytes[offset..<offset + length], as: UTF8.self) else {
            throw PresetLibrary.SnapshotError.malformed
        }
        return text
    }

    mutating func strings() throws -> [String] {
        let count = Int(try uint32())
        guard count <= remaining / 4 else { throw PresetLibrary.SnapshotError.malformed }
        var texts: [String] = []
        texts.reserveCapacity(count)
        for _ in 0..<count { texts.append(try string()) }
        return texts
    }
}
