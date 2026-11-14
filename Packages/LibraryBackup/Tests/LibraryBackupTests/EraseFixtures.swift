// EraseFixtures.swift — FILE-011: a container sandbox for erase tests. The library root holds every
// record kind (FILE-005's fixture, plus an imported audio asset); beside it sit a fake app bundle with
// bundled presets and the full-library archive, a purchase marker, Metal and other caches, and a tmp
// export — everything an erase must never touch.
import Foundation
import LocalPortability
import PresetLibrary
import XCTest
@testable import LibraryBackup

struct EraseSandbox {
    let container: URL
    let root: URL
    var folders: LibraryFolders { LibraryFolders(root: root) }

    var bundle: URL { container.appendingPathComponent("projectM-iOS.app", isDirectory: true) }
    var purchase: URL { container.appendingPathComponent("StoreKit", isDirectory: true) }
    var caches: URL { container.appendingPathComponent("Library/Caches", isDirectory: true) }
    var temporary: URL { container.appendingPathComponent("tmp", isDirectory: true) }
    var restoreWork: URL { root.appendingPathComponent(LibraryFolders.restoreFolderName, isDirectory: true) }

    /// Never touched by any erase (FILE-011-R5).
    var untouchable: [URL] { [bundle, purchase, caches, temporary, restoreWork] }

    func folder(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }

    /// One snapshot root per erasable folder, in `LibraryErasePolicy.allFolders` order.
    var erasableRoots: [URL] { LibraryErasePolicy.allFolders.map { (name: String) -> URL in folder(name) } }
}

enum EraseFixtures {
    /// FILE-005's settings plus the current photo and the video loop (all erase-relevant keys).
    static let settings: [String: LibrarySettingValue] = BackupFixtures.settings.merging([
        LibrarySettingsPolicy.photoKey: .string(String(BackupFixtures.photoName(1).dropLast(4))),
        LibraryErasePolicy.videoLoopKey: .data(Data("{\"start\":1}".utf8)),
        LibraryErasePolicy.videoSpeedKey: .data(Data("{\"percent\":50}".utf8)),   // MED-004
        LibraryErasePolicy.colorBlindSafePaletteKey: .bool(true),
        "settings.performanceOverlay": .bool(true),
    ]) { (_: LibrarySettingValue, new: LibrarySettingValue) -> LibrarySettingValue in new }

    static func sandbox(_ test: XCTestCase, _ label: String = "erase") throws -> EraseSandbox {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryEraseTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: container) }
        let sandbox = EraseSandbox(container: container, root: container.appendingPathComponent("Library/Application Support", isDirectory: true))
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
        try BackupFixtures.populate(sandbox.folders)
        let assets = sandbox.folder(LibraryErasePolicy.audioFolderName).appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("AUDIO-ASSET".utf8).write(to: assets.appendingPathComponent("1A2B.m4a"))
        try write("MILKDROP_PRESET_VERSION=201\nbundled\n", to: sandbox.bundle.appendingPathComponent("Presets/Included/Alpha.milk"))
        try write("FULL-LIBRARY-ARCHIVE", to: sandbox.bundle.appendingPathComponent("PresetLibrary/library.archive"))
        try write("{\"presets\":12847}", to: sandbox.bundle.appendingPathComponent("PresetLibrary/index.json"))
        try write("PURCHASE-MARKER", to: sandbox.purchase.appendingPathComponent("receipt"))
        try write("METAL-PIPELINE", to: sandbox.caches.appendingPathComponent("com.apple.metal/shaders.bin"))
        try write("THUMB", to: sandbox.caches.appendingPathComponent("Thumbnails/a.png"))
        try write("SHARE", to: sandbox.temporary.appendingPathComponent("Sharing/scene.pmscene"))
        try write("{\"result\":true}", to: sandbox.restoreWork.appendingPathComponent("last-result.json"))
        return sandbox
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A settings store standing in for UserDefaults.
    final class Defaults: @unchecked Sendable {
        var values: [String: LibrarySettingValue]
        init(_ values: [String: LibrarySettingValue] = EraseFixtures.settings) { self.values = values }
        func remove(_ keys: [String]) { for key in keys { values[key] = nil } }
    }

    /// Records a request for `categories` and runs the launch-time erase.
    @discardableResult
    static func erase(_ categories: Set<LibraryEraseCategory>, in sandbox: EraseSandbox, defaults: Defaults,
                      configure: (LibraryEraser) -> Void = { (_: LibraryEraser) in }) throws -> LibraryEraseResultNote? {
        try LibraryEraseRequestStore(root: sandbox.root).save(categories)
        return LibraryEraseLaunch.run(root: sandbox.root, settings: defaults.values, removeSettings: { (keys: [String]) in defaults.remove(keys) },
                                      configure: configure)
    }

    static func records(_ sandbox: EraseSandbox, _ defaults: Defaults) throws -> LibraryRecords {
        try LibraryRecords.read(folders: sandbox.folders, settings: defaults.values)
    }
}
