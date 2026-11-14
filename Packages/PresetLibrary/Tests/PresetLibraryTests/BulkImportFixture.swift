// BulkImportFixture.swift — PRE-013-T08: the 100-file fixture of the roadmap acceptance
// ("Fixture of 100 files reports exact added/skipped counts"), generated at test time in the temporary
// folder; nothing binary is committed. Preset texts are written for this repository.
//
//   70 valid and unique          (20 of them in a subfolder)
//   10 exact copies of 10 of those 70 (other names)
//    5 copies of the 5 presets the store is seeded with
//    8 the static checks reject  (no [preset00] header; each different)
//    4 over the 512 KiB limit
//    3 not presets               (.txt, .jpg, .md)
// plus one hidden `.DS_Store` (not one of the 100: hidden entries are not listed).
import Foundation
import XCTest
@testable import PresetLibrary

enum BulkImportFixture {
    struct File {
        var path: String
        var data: Data
    }

    static func valid(_ tag: Int) -> String {
        UserPresetFixtures.preset(perFrame: ["wave_r = 0.5 + 0.5*sin(time*1.\(tag));", "rot = 0.02*sin(time*0.3) + 0.0\(tag)*bass;"])
    }

    static func seeded(_ tag: Int) -> String {
        UserPresetFixtures.preset(perPixel: ["zoom = zoom + 0.0\(tag + 1)*sin(rad*7 + time);"])
    }

    static func invalid(_ tag: Int) -> String {
        UserPresetFixtures.preset(header: "", settings: ["zoom=1.0\(tag)"])
    }

    static func oversized(_ tag: Int) -> String {
        var text = valid(1000 + tag)
        let line = "// padding \(tag) " + String(repeating: "x", count: 1_000) + "\n"
        while text.utf8.count <= PresetImportLimits.maxFileBytes { text += line }
        return text
    }

    /// The 100 files (paths relative to the fixture folder), plus the hidden one.
    static func files() -> [File] {
        var files: [File] = []
        for tag in 0..<70 {
            let folder: String = tag < 20 ? "Subfolder/" : ""
            files.append(File(path: folder + "Artist - Valid \(tag).milk", data: Data(valid(tag).utf8)))
        }
        for tag in 0..<10 { files.append(File(path: "Copies/Copy of \(tag).milk", data: Data(valid(tag).utf8))) }
        for tag in 0..<5 { files.append(File(path: "Already \(tag).MILK", data: Data(seeded(tag).utf8))) }
        for tag in 0..<8 { files.append(File(path: "Broken/Broken \(tag).milk", data: Data(invalid(tag).utf8))) }
        for tag in 0..<4 { files.append(File(path: "Huge \(tag).milk", data: Data(oversized(tag).utf8))) }
        files.append(File(path: "notes.txt", data: Data("Presets collected over the years.\n".utf8)))
        files.append(File(path: "cover.jpg", data: Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])))
        files.append(File(path: "Subfolder/readme.md", data: Data("# Read me\n".utf8)))
        return files
    }

    static let hidden = File(path: ".DS_Store", data: Data([0, 0, 0, 1, 0x42, 0x75, 0x64, 0x31]))

    static func writeFolder(_ files: [File], in parent: URL, name: String = "Preset Pack") throws -> URL {
        let root = parent.appendingPathComponent(name, isDirectory: true)
        for file in files {
            let url = root.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: url)
        }
        return root
    }

    static func writeArchive(_ files: [File], to url: URL, method: Int, macMetadata: Bool = true) throws {
        var zip = RawZip()
        for file in files { zip.add(file.path, file.data, method: method) }
        if macMetadata { zip.add("__MACOSX/._Artist - Valid 30.milk", Data([0, 5, 22, 7, 0, 2, 0, 0]), method: method) }
        try zip.build().write(to: url)
    }

    /// A library in `parent/UserPresets` seeded with the 5 presets the fixture copies.
    static func seededLibrary(in parent: URL) async throws -> UserPresetLibrary {
        let library = UserPresetLibrary(directory: parent.appendingPathComponent("UserPresets", isDirectory: true))
        let seeds = parent.appendingPathComponent("seeds", isDirectory: true)
        try FileManager.default.createDirectory(at: seeds, withIntermediateDirectories: true)
        for tag in 0..<5 {
            let url = seeds.appendingPathComponent("Seed \(tag).milk")
            try Data(seeded(tag).utf8).write(to: url)
            let outcome = await library.importFile(at: url)
            guard case .waiting = outcome else { throw NSError(domain: "fixture", code: tag, userInfo: [NSLocalizedDescriptionKey: "\(outcome)"]) }
        }
        return library
    }

    static func temporaryFolder(_ test: XCTestCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pre013-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

/// Cancel after a number of handled files (set from the progress callback).
final class CancelAfter: @unchecked Sendable {
    private let lock = NSLock()
    private var handled = 0
    let limit: Int

    init(_ limit: Int) { self.limit = limit }

    func progress(_ value: BulkImportProgress) {
        lock.lock(); handled = value.handled; lock.unlock()
    }

    func isCancelled() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return handled >= limit
    }
}
