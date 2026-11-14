// LibraryBackupArchive.swift — FILE-005 contract C1 (writer) and C2 (reader).
//
// Writer: entries in a fixed order (show, scenes by ID, current scene, preset index, texts by hash,
// collections, settings, photos by name), `manifest.json` last. Equal contents and metadata give
// equal bytes.
//
// Reader: the file size cap, then FILE-002's checks (ZIP, CRC-32, bounded manifest, format, version,
// safe paths, sizes, SHA-256 of every entry), then every path must be one the format defines, then
// each record is decoded by its own reader and cross-checked: a scene file's name is its document's
// ID; every preset text matches its record and passes the static preset check; no full-library copy
// or quarantined record; no text without a record; only included settings; photos are PNG or JPEG.
// Any failure refuses the whole backup, naming the entry. Nothing read is executed.
import Foundation
import LocalPortability
import PresetLibrary
import SceneFormat
import ShowControl

public struct LibraryBackupContents: Sendable, Equatable {
    public let manifest: LibraryBackupManifest
    public let contents: LibraryContents
    /// SHA-256 of the archive's bytes.
    public let sha256: String
}

public enum LibraryBackupWriter {
    public static func write(_ contents: LibraryContents, appVersion: String, createdAt: Date) throws(LibraryBackupError) -> Data {
        var output = Data()
        let writer = PortableArchiveWriter(modified: createdAt) { (chunk: Data) in output.append(chunk) }
        var records: [PortableFileRecord] = []
        do {
            func add(_ path: String, _ data: Data) throws { records.append(try writer.add(path: path, data: data)) }
            if let show = contents.show { try add(LibraryBackupFormat.showPath, show) }
            for id in contents.scenes.keys.sorted() {
                if let bytes = contents.scenes[id] { try add(LibraryBackupFormat.scenePath(id), bytes) }
            }
            if let current = contents.currentScene { try add(LibraryBackupFormat.currentScenePath, current) }
            if !contents.presets.isEmpty {
                let index = UserPresetsFile(presets: contents.presets.map { (preset: LibraryPreset) -> UserPreset in preset.record })
                try add(LibraryBackupFormat.presetIndexPath, try index.encode())
                let texts = contents.presets.sorted { (a: LibraryPreset, b: LibraryPreset) -> Bool in a.record.sha256 < b.record.sha256 }
                for preset in texts { try add(LibraryBackupFormat.presetTextPath(preset.record.sha256), preset.text) }
            }
            if let collections = contents.collections {
                try add(LibraryBackupFormat.collectionsPath, try PresetCollectionsFile(collections: collections).encode())
            }
            try add(LibraryBackupFormat.settingsPath, try encodedSettings(contents.settings))
            for name in contents.photos.keys.sorted() {
                if let bytes = contents.photos[name] { try add(LibraryBackupFormat.photoPath(name), bytes) }
            }
            let manifest = LibraryBackupManifest(format: LibraryBackupFormat.name, formatVersion: LibraryBackupFormat.currentVersion,
                                                 files: records, appVersion: appVersion, createdAt: iso8601(createdAt),
                                                 counts: contents.counts, excluded: contents.excluded)
            try writer.finish(manifest: try sortedEncoder().encode(manifest))
        } catch {
            throw .writeFailed
        }
        return output
    }

    static func encodedSettings(_ settings: [String: LibrarySettingValue]) throws -> Data {
        try sortedEncoder().encode(LibrarySettingsDocument(schemaVersion: 1, values: LibrarySettingsPolicy.filtered(settings)))
    }

    static func sortedEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

public enum LibraryBackupReader {
    public static func read(_ data: Data) throws(LibraryBackupError) -> LibraryBackupContents {
        guard data.count <= LibraryBackupFormat.maxFileBytes else { throw .tooLarge(limit: LibraryBackupFormat.maxFileBytes) }
        let archive: PortableArchiveContents
        do {
            archive = try PortableArchive.read(data, schema: LibraryBackupFormat.schema, limits: LibraryBackupFormat.limits)
        } catch let error as PortableArchiveError {
            throw .archive(error)
        } catch {
            throw .archive(.malformedManifest)
        }
        guard let manifest = try? JSONDecoder().decode(LibraryBackupManifest.self, from: archive.manifest) else {
            throw .archive(.malformedManifest)
        }
        for record in archive.records where !isKnownPath(record.path) { throw .unexpectedEntry(record.path) }
        var contents = LibraryContents()
        contents.excluded = manifest.excluded
        let files = archive.files
        if let show = files[LibraryBackupFormat.showPath] {
            guard let list = try? ShowCueList.decode(show).list else { throw .unreadableRecord(LibraryBackupFormat.showPath) }
            contents.show = list.encoded()
        }
        contents.scenes = try readScenes(files)
        if let current = files[LibraryBackupFormat.currentScenePath] {
            guard let result = try? SceneDocument.decode([UInt8](current), migrator: .standard) else {
                throw .unreadableRecord(LibraryBackupFormat.currentScenePath)
            }
            contents.currentScene = Data(result.document.encoded())
        }
        contents.presets = try readPresets(files)
        if let collections = files[LibraryBackupFormat.collectionsPath] {
            guard let file = try? PresetCollectionsFile.decode(collections).file else { throw .unreadableRecord(LibraryBackupFormat.collectionsPath) }
            contents.collections = file.collections
        }
        contents.settings = try readSettings(files)
        contents.photos = try readPhotos(files)
        return LibraryBackupContents(manifest: manifest, contents: contents, sha256: PortableSHA256.hex(data))
    }

    static func isKnownPath(_ path: String) -> Bool {
        if path == LibraryBackupFormat.showPath || path == LibraryBackupFormat.currentScenePath || path == LibraryBackupFormat.presetIndexPath
            || path == LibraryBackupFormat.collectionsPath || path == LibraryBackupFormat.settingsPath { return true }
        if let id = stripped(path, prefix: LibraryBackupFormat.scenesPrefix, suffix: LibraryBackupFormat.sceneSuffix) {
            return ShowCueList.isSceneID(id)
        }
        if let hash = stripped(path, prefix: LibraryBackupFormat.presetTextsPrefix, suffix: LibraryBackupFormat.presetTextSuffix) {
            return ContentHash.isHex(hash, count: 64) && hash == hash.lowercased()
        }
        if path.hasPrefix(LibraryBackupFormat.photosPrefix) {
            return LibraryBackupFormat.isPhotoName(String(path.dropFirst(LibraryBackupFormat.photosPrefix.count)))
        }
        return false
    }

    static func stripped(_ path: String, prefix: String, suffix: String) -> String? {
        guard path.hasPrefix(prefix), path.hasSuffix(suffix), path.count > prefix.count + suffix.count else { return nil }
        return String(path.dropFirst(prefix.count).dropLast(suffix.count))
    }

    private static func readScenes(_ files: [String: Data]) throws(LibraryBackupError) -> [String: Data] {
        var scenes: [String: Data] = [:]
        for path in files.keys.sorted() {
            guard let id = stripped(path, prefix: LibraryBackupFormat.scenesPrefix, suffix: LibraryBackupFormat.sceneSuffix),
                  let bytes = files[path] else { continue }
            guard let result = try? SceneDocument.decode([UInt8](bytes), migrator: .standard), result.document.id == id else {
                throw .unreadableRecord(path)
            }
            scenes[id] = Data(result.document.encoded())
        }
        return scenes
    }

    private static func readPresets(_ files: [String: Data]) throws(LibraryBackupError) -> [LibraryPreset] {
        let textPaths = files.keys.filter { (path: String) -> Bool in path.hasPrefix(LibraryBackupFormat.presetTextsPrefix) }
        guard let index = files[LibraryBackupFormat.presetIndexPath] else {
            if let stray = textPaths.sorted().first { throw .unexpectedEntry(stray) }
            return []
        }
        guard let file = try? UserPresetsFile.decode(index).file else { throw .unreadableRecord(LibraryBackupFormat.presetIndexPath) }
        var used: Set<String> = []
        var presets: [LibraryPreset] = []
        for record in file.presets {
            let path = LibraryBackupFormat.presetTextPath(record.sha256)
            if record.state == .quarantined || UserPresetExportPlan.exclusion(of: record, held: false) == .fullLibraryCopy {
                throw .excludedRecord(path)
            }
            guard let text = files[path], text.count == record.byteCount, text.count <= PresetImportLimits.maxFileBytes,
                  ContentHash.sha256Hex([UInt8](text)) == record.sha256,
                  MilkdropPresetValidator.validate([UInt8](text), knownTextures: []).rejection == nil else {
                throw .unreadableRecord(path)
            }
            used.insert(path)
            presets.append(LibraryPreset(record: record, text: text))
        }
        if let stray = textPaths.filter({ (path: String) -> Bool in !used.contains(path) }).sorted().first { throw .unexpectedEntry(stray) }
        return presets
    }

    private static func readSettings(_ files: [String: Data]) throws(LibraryBackupError) -> [String: LibrarySettingValue] {
        guard let data = files[LibraryBackupFormat.settingsPath] else { return [:] }
        guard (try? BoundedJSON.validate(data, limits: JSONLimits(maxBytes: 4 << 20, maxDepth: 6, maxStringBytes: 1 << 20,
                                                                  maxNumberBytes: 32, maxElements: 4_096))) != nil,
              let document = try? JSONDecoder().decode(LibrarySettingsDocument.self, from: data), document.schemaVersion == 1 else {
            throw .unreadableRecord(LibraryBackupFormat.settingsPath)
        }
        if let unknown = document.values.keys.sorted().first(where: { (key: String) -> Bool in !LibrarySettingsPolicy.isIncluded(key) }) {
            throw .excludedRecord(LibraryBackupFormat.settingsPath + "#" + unknown)
        }
        return document.values
    }

    private static func readPhotos(_ files: [String: Data]) throws(LibraryBackupError) -> [String: Data] {
        var photos: [String: Data] = [:]
        for path in files.keys.sorted() where path.hasPrefix(LibraryBackupFormat.photosPrefix) {
            guard let bytes = files[path] else { continue }
            let name = String(path.dropFirst(LibraryBackupFormat.photosPrefix.count))
            guard hasImageSignature(bytes, png: name.hasSuffix(".png")) else { throw .unreadableRecord(path) }
            photos[name] = bytes
        }
        guard photos.count <= LibraryBackupFormat.maxPhotos else { throw .tooManyPhotos(limit: LibraryBackupFormat.maxPhotos) }
        return photos
    }

    static func hasImageSignature(_ bytes: Data, png: Bool) -> Bool {
        let head = [UInt8](bytes.prefix(8))
        if png { return head == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] }
        return head.count >= 3 && head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF
    }
}
