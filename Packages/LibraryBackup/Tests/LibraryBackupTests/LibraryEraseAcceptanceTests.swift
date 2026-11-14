// LibraryEraseAcceptanceTests.swift — FILE-011-T05 (FILE-011-S1; the roadmap acceptance "Erase deletes
// selected data and leaves bundled assets untouched"). A container sandbox holds every record kind, a
// fake app bundle (bundled presets, the full-library archive), a purchase marker, caches and a tmp
// export. Each category is erased alone, then all six: only that category's records (FILE-005's
// `LibraryRecords`), folders (FILE-003's `LibraryTreeSnapshot`) and keys are gone; everything else,
// the bundle included, is byte-for-byte unchanged.
import Foundation
import PresetLibrary
import XCTest
@testable import LibraryBackup

final class LibraryEraseAcceptanceTests: XCTestCase {
    /// The record keys a category owns (records of FILE-005-R9).
    private func owns(_ category: LibraryEraseCategory, _ key: String) -> Bool {
        switch category {
        case .scenes: return key == "show" || key.hasPrefix("scene/") || key == "current-scene"
        case .presets: return key.hasPrefix("preset/") || key == "setting/" + LibrarySettingsPolicy.lastPresetKey
        case .collections: return key == "collections" || key == "setting/" + LibrarySettingsPolicy.favoritesKey
        case .media: return key.hasPrefix("photo/") || key == "setting/" + LibrarySettingsPolicy.photoKey
        case .importedAudio: return false
        case .settings: return key.hasPrefix("setting/") && LibraryErasePolicy.settingKeys(.settings).contains(String(key.dropFirst(8)))
        }
    }

    private func check(_ chosen: Set<LibraryEraseCategory>, file: StaticString = #filePath, line: UInt = #line) throws {
        let sandbox = try EraseFixtures.sandbox(self, chosen.map(\.rawValue).sorted().joined(separator: "-"))
        let defaults = EraseFixtures.Defaults()
        let before = try EraseFixtures.records(sandbox, defaults)
        let beforeKeys = defaults.values
        let untouchedBefore = LibraryTreeSnapshot.take(sandbox.untouchable)
        let foldersBefore: [String: LibraryTreeSnapshot] = snapshots(sandbox)

        let note = try EraseFixtures.erase(chosen, in: sandbox, defaults: defaults)
        XCTAssertEqual(note?.erased, true, note?.message ?? "no note", file: file, line: line)

        let after = try EraseFixtures.records(sandbox, defaults)
        for (key, digest) in before.digests {
            let erased = chosen.contains { (category: LibraryEraseCategory) -> Bool in owns(category, key) }
            if erased {
                XCTAssertNil(after.digests[key], "\(key) is erased", file: file, line: line)
            } else {
                XCTAssertEqual(after.digests[key], digest, "\(key) is unchanged", file: file, line: line)
            }
        }
        XCTAssertEqual(Set(after.digests.keys).subtracting(before.digests.keys), [], "nothing new appears", file: file, line: line)
        let erasedFolders: Set<String> = Set(chosen.flatMap { (category: LibraryEraseCategory) -> [String] in LibraryErasePolicy.folders(category) })
        for (name, snapshot) in snapshots(sandbox) {
            if erasedFolders.contains(name) {
                XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.folder(name).path), "\(name) is gone", file: file, line: line)
            } else {
                XCTAssertEqual(snapshot.differences(from: foldersBefore[name] ?? snapshot), [], "\(name) is byte-for-byte unchanged", file: file, line: line)
            }
        }
        XCTAssertEqual(LibraryTreeSnapshot.take(sandbox.untouchable).differences(from: untouchedBefore), [],
                       "the bundle, purchase, caches, tmp and restore folder are byte-for-byte unchanged", file: file, line: line)
        var expectedKeys: Set<String> = []
        for category in chosen { expectedKeys.formUnion(LibraryErasePolicy.settingKeys(category)) }
        if chosen.contains(.presets) { expectedKeys.insert(LibrarySettingsPolicy.lastPresetKey) }
        let removed: Set<String> = Set(beforeKeys.keys).subtracting(defaults.values.keys)
        XCTAssertEqual(removed, expectedKeys.intersection(beforeKeys.keys), "exactly the category's keys are removed", file: file, line: line)
        for key in LibraryErasePolicy.neverErasedKeys where beforeKeys[key] != nil {
            XCTAssertEqual(defaults.values[key], beforeKeys[key], "\(key) is kept", file: file, line: line)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.root.appendingPathComponent("LibraryErase/trash").path), file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.root.appendingPathComponent("LibraryErase/request.json").path), file: file, line: line)
    }

    private func snapshots(_ sandbox: EraseSandbox) -> [String: LibraryTreeSnapshot] {
        var map: [String: LibraryTreeSnapshot] = [:]
        for name in LibraryErasePolicy.allFolders { map[name] = LibraryTreeSnapshot.take([sandbox.folder(name)]) }
        return map
    }

    func testEachCategoryAloneErasesOnlyItsData() throws {
        for category in LibraryEraseCategory.allCases {
            try check([category])
        }
    }

    func testEverythingLeavesAFreshLibraryAndTheBundleUntouched() throws {
        try check(Set(LibraryEraseCategory.allCases))
        let sandbox = try EraseFixtures.sandbox(self, "fresh")
        let defaults = EraseFixtures.Defaults()
        try EraseFixtures.erase(Set(LibraryEraseCategory.allCases), in: sandbox, defaults: defaults)
        let records = try EraseFixtures.records(sandbox, defaults)
        XCTAssertEqual(Set(records.digests.keys), ["setting/" + LibraryErasePolicy.colorBlindSafePaletteKey, "setting/" + LibraryErasePolicy.reduceFlashingKey],
                       "only the kept safety and accessibility settings remain")
        let inventory = LibraryEraseInventory.measure(root: sandbox.root, settings: defaults.values)
        for category in LibraryEraseCategory.allCases {
            XCTAssertEqual(inventory.item(category).count, 0, "\(category) is empty")
        }
        XCTAssertEqual(defaults.values["notice.photosensitivityAcknowledged"], .bool(true))
    }

    func testThePolicyClassifiesEveryKeyOnceAndNamesOnlyLibraryFolders() {
        var seen: [String: Int] = [:]
        for category in LibraryEraseCategory.allCases {
            for key in LibraryErasePolicy.settingKeys(category) { seen[key, default: 0] += 1 }
        }
        XCTAssertEqual(seen.filter { (entry: (key: String, value: Int)) -> Bool in entry.value > 1 }.keys.sorted(), [], "no key in two categories")
        let erasable: Set<String> = Set(LibraryErasePolicy.erasableKeys)
        XCTAssertEqual(erasable.intersection(LibraryErasePolicy.neverErasedKeys), [], "kept keys are never erased")
        let backupKeys: Set<String> = Set(LibrarySettingsPolicy.includedKeys + LibrarySettingsPolicy.excludedKeys)
        XCTAssertEqual(backupKeys.subtracting(erasable).subtracting(LibraryErasePolicy.neverErasedKeys), [],
                       "every key FILE-005 knows is erased by a category or deliberately kept")
        XCTAssertEqual(Set(LibraryErasePolicy.allFolders).count, LibraryErasePolicy.allFolders.count)
        XCTAssertFalse(LibraryErasePolicy.allFolders.contains(LibraryFolders.restoreFolderName))
        XCTAssertEqual(LibraryErasePolicy.list([.media, .scenes]), "Scenes and show and Photos and videos")
        XCTAssertEqual(LibraryEraseText.erased([.media, .scenes]), "Erased: scenes and show, photos and videos.")
    }

    func testTheInventoryCountsAndSizesEachCategory() throws {
        let sandbox = try EraseFixtures.sandbox(self, "inventory")
        let inventory = LibraryEraseInventory.measure(root: sandbox.root, settings: EraseFixtures.settings)
        XCTAssertEqual(inventory.item(.scenes).count, 4, "three stored scenes and the current scene")
        XCTAssertEqual(inventory.item(.presets).count, 5, "every record of the index")
        XCTAssertEqual(inventory.item(.collections).count, 4, "two collections and two favorites")
        XCTAssertEqual(inventory.item(.media).count, 2, "one photo and one video")
        XCTAssertEqual(inventory.item(.importedAudio).count, 1)
        XCTAssertGreaterThan(inventory.item(.settings).count, 5)
        XCTAssertNil(inventory.item(.settings).bytes)
        for category in LibraryEraseCategory.allCases where category != .settings {
            XCTAssertGreaterThan(inventory.item(category).bytes ?? 0, 0, "\(category) has a size")
        }
    }
}
