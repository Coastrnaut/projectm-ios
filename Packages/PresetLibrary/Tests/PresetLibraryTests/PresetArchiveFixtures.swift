// FILE-003-T04: archives for the dry-run tests, written with the real PRE-014 writer (or, for the
// refusal fixtures, the generic archive writer with a crafted manifest). Every text is written for
// this repository. Records are built directly, so the archive's identifiers and names are exact.
import Foundation
import LocalPortability
import XCTest
@testable import PresetLibrary

enum PresetArchiveFixtures {
    typealias F = UserPresetFixtures

    /// A distinct valid text per tag; `license` adds a licence comment line.
    static func text(_ tag: String, license: Bool = true) -> String {
        let extra: [String] = license ? ["// License: CC-BY 4.0, Example Author"] : []
        return ExportFixtures.text(tag, extra: extra)
    }

    /// A user preset record for `text` (any state the archive may carry is irrelevant: export drops it).
    static func record(id suffix: String, name: String, text: String) -> UserPreset {
        let bytes = [UInt8](text.utf8)
        return UserPreset(id: UserPreset.idPrefix + suffix, name: name, author: "", originalFileName: "\(name).milk",
                          sha256: ContentHash.sha256Hex(bytes), blobHash: ContentHash.gitBlobSHA1Hex(bytes), byteCount: bytes.count,
                          importedAt: ExportFixtures.now, state: .playable, provenOnScreen: true, quarantine: nil, warnings: [],
                          license: PresetLicenseMetadata(authorFromFileName: false, linesFound: []))
    }

    /// An archive of `items` (suffix, name, text) through `UserPresetArchiveWriter`.
    static func archive(_ items: [(id: String, name: String, text: String)]) throws -> Data {
        var texts: [String: Data] = [:]
        var records: [UserPreset] = []
        for item in items {
            let preset = record(id: item.id, name: item.name, text: item.text)
            records.append(preset)
            texts[preset.id] = Data(item.text.utf8)
        }
        var output = Data()
        try UserPresetArchiveWriter.write(records, appVersion: "1.1 (2)", exportedAt: ExportFixtures.now,
                                          contents: { (preset: UserPreset) -> Data? in texts[preset.id] },
                                          sink: { (chunk: Data) in output.append(chunk) })
        return output
    }

    /// An archive whose manifest is `change`d after the records are built (refusal fixtures).
    static func craftedArchive(_ items: [(id: String, name: String, text: String)],
                               change: (inout UserPresetArchiveManifest) -> Void) throws -> Data {
        var output = Data()
        let writer = PortableArchiveWriter(modified: ExportFixtures.now, sink: { (chunk: Data) in output.append(chunk) })
        var files: [PortableFileRecord] = []
        var exported: [ExportedUserPreset] = []
        for item in items {
            let preset = record(id: item.id, name: item.name, text: item.text)
            guard let entry = ExportedUserPreset(preset) else { throw NSError(domain: "fixture", code: 1) }
            files.append(try writer.add(path: entry.path, data: Data(item.text.utf8)))
            exported.append(entry)
        }
        var manifest = UserPresetArchiveManifest(appVersion: "1.1 (2)", exportedAt: ExportFixtures.now, files: files, presets: exported)
        change(&manifest)
        try writer.finish(manifest: try manifest.encoded())
        return output
    }

    /// The reader's refusal message for `data` (what the plan must show), or nil if it reads.
    static func readerRefusal(_ data: Data) -> String? {
        do {
            _ = try UserPresetArchiveReader.read(data)
            return nil
        } catch let error as UserPresetArchiveError {
            return error.message
        } catch {
            return "unexpected \(error)"
        }
    }

    /// The seeded library used by most fixtures: "Bright Waves" (playable, with licence), and a
    /// quarantined file "Broken.milk". Returns the library and the seeded records.
    static func seededLibrary(_ test: XCTestCase) async throws -> (library: UserPresetLibrary, directory: URL, bright: UserPreset, broken: UserPreset) {
        let root = try F.tempDirectory(test)
        let directory = root.appendingPathComponent("UserPresets", isDirectory: true)
        let folder = root.appendingPathComponent("Picked", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let library = await ExportFixtures.library(directory, ids: CountingIDs())
        let bright = try await ExportFixtures.importFile(library, named: "Bright Waves.milk", text: text("bright"), in: folder)
        let broken = try await ExportFixtures.importFile(library, named: "Broken.milk", text: brokenText, in: folder)
        return (library, directory, bright, broken)
    }

    /// Fails the static checks (no `[preset00]` header).
    static var brokenText: String { F.preset(header: "") }

    /// The library's folder plus a collections folder next to it: what the acceptance snapshots.
    static func roots(_ directory: URL) -> [URL] {
        [directory, directory.deletingLastPathComponent().appendingPathComponent(PresetCollectionStore.directoryName, isDirectory: true)]
    }
}
