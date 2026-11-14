// LibraryEraseInventory.swift — FILE-011 contract E2 (FILE-011-R9; research FILE-011-D6): how many
// records each erase category holds and the space its folders take. Counts come from the stores' own
// readers; sizes from FILE-009's `StorageUsageCalculator` (regular files, no links, no dates). Reads
// only; call it off the main thread.
import Foundation
import LocalPortability
import PresetLibrary
import SceneFormat
import ShowStorage

public struct LibraryEraseInventory: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public var count: Int
        /// Nil for settings (they live in the preferences file, not in a folder).
        public var bytes: Int64?

        public init(count: Int, bytes: Int64?) {
            self.count = count
            self.bytes = bytes
        }
    }

    public let items: [LibraryEraseCategory: Item]

    public init(items: [LibraryEraseCategory: Item]) {
        self.items = items
    }

    public func item(_ category: LibraryEraseCategory) -> Item { items[category] ?? Item(count: 0, bytes: category == .settings ? nil : 0) }

    /// `settings`: the app's current values of `LibraryErasePolicy.erasableKeys` (others are ignored).
    public static func measure(root: URL, settings: [String: LibrarySettingValue],
                               calculator: StorageUsageCalculator = StorageUsageCalculator()) -> LibraryEraseInventory {
        var items: [LibraryEraseCategory: Item] = [:]
        for category in LibraryEraseCategory.allCases {
            let bytes: Int64? = category == .settings ? nil : size(of: category, root: root, calculator: calculator)
            items[category] = Item(count: count(category, root: root, settings: settings), bytes: bytes)
        }
        return LibraryEraseInventory(items: items)
    }

    static func count(_ category: LibraryEraseCategory, root: URL, settings: [String: LibrarySettingValue]) -> Int {
        let folders = LibraryFolders(root: root)
        switch category {
        case .scenes:
            let stored: Int = ShowStore(directory: folders.url(.show)).storedSceneIDs().count
            return stored + (FileManager.default.fileExists(atPath: folders.currentSceneFile.path) ? 1 : 0)
        case .presets:
            guard let data = try? Data(contentsOf: folders.presetIndexFile), let file = try? UserPresetsFile.decode(data).file else { return 0 }
            return file.presets.count
        case .collections:
            var total = 0
            if let data = try? Data(contentsOf: folders.collectionsFile), let file = try? PresetCollectionsFile.decode(data).file {
                total += file.collections.count
            }
            if let data = try? Data(contentsOf: folders.tagsFile), let tags = try? PresetTagsFile.decode(data).map {
                total += tags.tags.count   // PRE-003: tagged presets
            }
            if case let .strings(ids)? = settings[LibrarySettingsPolicy.favoritesKey] { total += ids.count }
            if case let .strings(ids)? = settings[LibrarySettingsPolicy.recentPresetsKey] { total += ids.count }   // PRE-006-R7
            return total
        case .media:
            let photos = ContentAddressedMediaFolder(directory: folders.url(.photos), extensions: LibraryErasePolicy.photoExtensions)
            let videos = ContentAddressedMediaFolder(directory: root.appendingPathComponent(LibraryErasePolicy.videosFolderName, isDirectory: true),
                                                     extensions: LibraryErasePolicy.videoExtensions)
            return photos.references().count + videos.references().count
        case .importedAudio:
            let assets = root.appendingPathComponent(LibraryErasePolicy.audioFolderName, isDirectory: true)
                .appendingPathComponent("assets", isDirectory: true)
            let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: assets.path)) ?? []
            return names.filter { (name: String) -> Bool in !name.hasPrefix(".") }.count
        case .settings:
            return LibraryErasePolicy.settingKeys(.settings).filter { (key: String) -> Bool in settings[key] != nil }.count
        }
    }

    static func size(of category: LibraryEraseCategory, root: URL, calculator: StorageUsageCalculator) -> Int64 {
        let paths: [String] = LibraryErasePolicy.folders(category).map { (name: String) -> String in
            root.appendingPathComponent(name, isDirectory: true).path
        }
        let request = StorageRequest(container: root.path, roots: [.photos: paths])
        guard let report = try? calculator.measure(request) else { return 0 }
        return report.usage(.photos).spaceUsed
    }
}
