// PRE-014: a user-preset library with every kind of record, built through the real
// UserPresetLibrary (fixed clock, counting id maker, scripted trial). Preset texts are written
// for this repository; none is a third-party file.
import Foundation
import XCTest
@testable import PresetLibrary

final class CountingIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var next = 0
    func make() -> String {
        lock.withLock {
            next += 1
            return String(format: "00000000-0000-4000-8000-%012d", next)
        }
    }
}

enum ExportFixtures {
    typealias F = UserPresetFixtures

    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let later = Date(timeIntervalSince1970: 1_800_000_600)

    static func text(_ tag: String, extra: [String] = []) -> String {
        F.preset(settings: ["fRating=3.000000", "zoom=1.0\(tag.utf8.count)", "rot=0.0\(tag.utf8.reduce(0) { $0 + Int($1) } % 90 + 10)"],
                 perFrame: ["wave_r = 0.5 + 0.5*sin(time*1.\(tag.utf8.count));", "// \(tag)"],
                 warp: F.warpShader, comp: F.compShader, extra: extra)
    }

    static func library(_ directory: URL, ids: CountingIDs, now: Date = ExportFixtures.now, trial: FakeTrial? = FakeTrial(),
                        unlocked: Bool = false) async -> UserPresetLibrary {
        let library = UserPresetLibrary(directory: directory, now: { now }, makeID: { ids.make() })
        _ = await library.load()
        await library.setContext(.empty)
        await library.setTrial(trial)
        await library.setLibraryUnlocked(unlocked)
        return library
    }

    static func source(_ name: String, text: String, packID: String, locked: Bool) -> BundledPresetSource {
        BundledPresetSource(id: "\(packID)/\(name).milk", name: name, author: "Example Author", fileName: "\(name).milk", packID: packID,
                            packTitle: packID == "included" ? "Included" : "Cream of the Crop",
                            licenseStatement: packID == "included" ? "Bundled with projectM; see the app's licenses screen." : "Pack statement.",
                            blobHash: ContentHash.gitBlobSHA1Hex(Array(text.utf8)), requiresLibraryUnlock: locked)
    }

    @discardableResult
    static func importFile(_ library: UserPresetLibrary, named name: String, text: String, in folder: URL) async throws -> UserPreset {
        let url = try F.write(text, named: name, in: folder)
        switch await library.importFile(at: url) {
        case .added(let preset), .waiting(let preset), .quarantined(let preset): return preset
        case .refused(let refusal): throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(refusal)"])
        }
    }

    @discardableResult
    static func duplicate(_ library: UserPresetLibrary, _ source: BundledPresetSource, text: String) async throws -> UserPreset {
        switch await library.duplicate(source, contents: Data(text.utf8)) {
        case .added(let preset), .waiting(let preset), .quarantined(let preset): return preset
        case .refused(let refusal): throw NSError(domain: "fixture", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(refusal)"])
        }
    }

    /// Two imports (one with a license line and an author from the file name, one with an emoji
    /// name and a warning) and an edited copy of an Included preset: everything exportable.
    static func exportableLibrary(_ directory: URL, folder: URL, ids: CountingIDs) async throws -> UserPresetLibrary {
        let library = await library(directory, ids: ids)
        try await importFile(library, named: "Example Author - Bright Waves.milk",
                             text: text("bright", extra: ["// License: CC-BY 4.0, Example Author \"quoted\""]), in: folder)
        try await importFile(library, named: "Nebula 🌌 Ünïcode.milk", text: text("nebula", extra: ["notasettingline"]), in: folder)
        let included = text("included-original")
        let copy = try await duplicate(library, source("Alpha", text: included, packID: "included", locked: false), text: included)
        let edited = await ExportFixtures.library(directory, ids: ids, now: later)
        let outcome = await edited.edit(copy.id, name: "Alpha, edited", text: text("included-edited"), expectedSHA256: copy.sha256)
        guard case .saved = outcome else { throw NSError(domain: "fixture", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(outcome)"]) }
        return await ExportFixtures.library(directory, ids: ids)
    }

    static func exportData(_ library: UserPresetLibrary, ids: [String]? = nil, to url: URL,
                           file: StaticString = #filePath, line: UInt = #line) async throws -> (UserPresetExportSummary, Data) {
        let selected: [String]
        if let ids { selected = ids } else { selected = await library.exportPlan().exportable.map(\.id) }
        let result = await library.export(ids: selected, appVersion: "1.1 (2)", exportedAt: now, to: url)
        switch result {
        case .success(let summary): return (summary, try Data(contentsOf: url))
        case .failure(let error):
            XCTFail("export failed: \(error)", file: file, line: line)
            throw error
        }
    }
}
