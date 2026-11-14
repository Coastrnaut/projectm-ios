// LibraryErasePolicy.swift — FILE-011 contract E1 (specs/120-file-011-local-data-erase; research
// FILE-011-D4, D7; ADR-0048): what each erase category removes. The folder names are the stores' own
// (an app test checks they agree); the setting keys come from FILE-005's lists, so a key added to the
// backup is classified here too (a package test checks every key is erased by exactly one category or
// deliberately kept).
import Foundation

/// The six categories the user can choose, in display order (FILE-011-R1).
public enum LibraryEraseCategory: String, Sendable, Hashable, CaseIterable, Codable, Comparable {
    case scenes, presets, collections, media, importedAudio, settings

    public var title: String {
        switch self {
        case .scenes: "Scenes and show"
        case .presets: "My Presets"
        case .collections: "Collections and favorites"
        case .media: "Photos and videos"
        case .importedAudio: "Imported audio"
        case .settings: "Settings"
        }
    }

    /// Lowercase, for sentences ("Erased: scenes and show, my presets.").
    public var phrase: String {
        switch self {
        case .presets: "My Presets"
        default: title.lowercased()
        }
    }

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: LibraryEraseCategory, rhs: LibraryEraseCategory) -> Bool { lhs.order < rhs.order }
}

public enum LibraryErasePolicy {
    /// `Application Support/Videos` (MED-002 `VideoStore.folderName`).
    public static let videosFolderName = "Videos"
    /// `Application Support/AudioLibrary` (AUD-001 `AudioLibrary.defaultDirectory()`).
    public static let audioFolderName = "AudioLibrary"
    /// The erase's own work folder (request, journal, trash, last result).
    public static let workFolderName = "LibraryErase"
    /// Photo payload and legacy extensions (MED-001 `PhotoStore.extensions`); videos (`VideoStore.fileExtension`).
    public static let photoExtensions: [String] = ["png", "jpg"]
    public static let videoExtensions: [String] = ["mov"]

    public static let videoKey = "settings.video.id"
    public static let videoLoopKey = "settings.video.loop"
    public static let videoSpeedKey = "settings.video.speed"   // MED-004
    public static let reduceFlashingKey = "settings.reduceFlashing"
    public static let colorBlindSafePaletteKey = "settings.visual.colorBlindSafePalette"
    public static let oscEnabledKey = "settings.osc.enabled"
    public static let midiEnabledKey = "settings.midi.enabled"
    /// REC-004-R3: "Include microphone audio" (a device switch: not backed up, erased with Settings).
    public static let recordingMicrophoneKey = "settings.recording.includeMicrophone"

    /// Folder names under the library root (FILE-011-R4).
    public static func folders(_ category: LibraryEraseCategory) -> [String] {
        switch category {
        case .scenes: [LibraryFolders.Folder.show.rawValue, LibraryFolders.Folder.currentScene.rawValue]
        case .presets: [LibraryFolders.Folder.presets.rawValue]
        case .collections: [LibraryFolders.Folder.collections.rawValue]
        case .media: [LibraryFolders.Folder.photos.rawValue, videosFolderName]
        case .importedAudio: [audioFolderName]
        case .settings: []
        }
    }

    /// Keys every erase of the category removes (`lastPresetID` is removed by the plan only when it
    /// names a user preset).
    public static func settingKeys(_ category: LibraryEraseCategory) -> [String] {
        switch category {
        case .scenes, .presets, .importedAudio: []
        case .collections: [LibrarySettingsPolicy.favoritesKey]
        case .media: [LibrarySettingsPolicy.photoKey, LibrarySettingsPolicy.slideshowKey, videoKey, videoLoopKey, videoSpeedKey]   // MED-006
        case .settings: settingsCategoryKeys
        }
    }

    /// Every folder some category can remove.
    public static var allFolders: [String] {
        LibraryEraseCategory.allCases.flatMap { (category: LibraryEraseCategory) -> [String] in folders(category) }
    }

    /// Kept by every erase: safety, accessibility and device state (FILE-011-R5).
    public static let neverErasedKeys: [String] = [
        reduceFlashingKey, colorBlindSafePaletteKey,
        "notice.photosensitivityAcknowledged", "permission.explained.camera", "permission.explained.localNetwork",
        "session.recovery.open", "session.recovery.heldVisual", "session.recovery.sessionsSinceReopen", "guide.firstScene",
    ]

    /// Keys whose value is read to plan an erase (the current media and the last preset).
    public static let planningKeys: [String] = [LibrarySettingsPolicy.photoKey, videoKey, LibrarySettingsPolicy.lastPresetKey]

    /// FILE-005's included keys minus those owned by other categories or kept, plus the device switches.
    static let settingsCategoryKeys: [String] = {
        let owned: Set<String> = [LibrarySettingsPolicy.favoritesKey, LibrarySettingsPolicy.lastPresetKey, LibrarySettingsPolicy.photoKey,
                                  LibrarySettingsPolicy.slideshowKey,   // MED-006: erased with the media
                                  reduceFlashingKey, colorBlindSafePaletteKey]
        let included: [String] = LibrarySettingsPolicy.includedKeys.filter { (key: String) -> Bool in !owned.contains(key) }
        return included + [oscEnabledKey, midiEnabledKey, recordingMicrophoneKey]
    }()

    /// Every key some category can remove.
    public static var erasableKeys: [String] {
        var keys: [String] = []
        for category in LibraryEraseCategory.allCases { keys += settingKeys(category) }
        return keys + [LibrarySettingsPolicy.lastPresetKey]
    }

    /// "Scenes and show, My Presets and Photos and videos" (display order).
    public static func list(_ categories: Set<LibraryEraseCategory>) -> String {
        let titles: [String] = categories.sorted().map { (category: LibraryEraseCategory) -> String in category.title }
        guard titles.count > 1, let last = titles.last else { return titles.first ?? "" }
        return titles.dropLast().joined(separator: ", ") + " and " + last
    }
}
