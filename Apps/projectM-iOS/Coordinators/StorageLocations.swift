// StorageLocations.swift — FILE-009-R2: the folders each Storage category measures, named from the
// stores' own definitions (a test checks they agree with every store's default directory).
// Contract: specs/071-file-009-storage-usage-explorer/contracts/storage-usage.md.
// FILE-010: the user-data folders cache cleanup must never touch (`protectedRoots`) and the cleanup
// request for the cleanable categories (contracts/cache-cleanup.md C1).
import Foundation
import LocalPortability
import PresetLibrary

struct StorageLocations: Sendable, Equatable {
    /// The app's data container (Documents, Library, tmp).
    let container: URL
    let roots: [StorageCategory: [URL]]
    /// FILE-010: user-data folders outside the category table too (the show, preferences).
    var extraProtectedRoots: [URL] = []

    /// `Library/Application Support/AudioLibrary` (AUD-001 `AudioLibrary.defaultDirectory()`).
    static let audioLibraryFolderName = "AudioLibrary"
    /// `<tmp>/Recordings` (REC-003 `VideoRecordingCoordinator.defaultDirectory`).
    static let recordingsFolderName = "Recordings"
    /// `<tmp>/Sharing` (REC-012 `ShareFileStore.defaultDirectory`).
    static let sharingFolderName = "Sharing"
    /// `<tmp>/PresetExport` (PRE-014 `UserPresetsCoordinator.defaultExportDirectory`).
    static let presetExportFolderName = "PresetExport"
    /// `Library/Application Support/Show` (SHOW-001 `ShowStore.defaultDirectory()`).
    static let showFolderName = "Show"

    /// The layout under any base folders (tests and the DEBUG fixture redirect them).
    static func make(applicationSupport: URL, temporary: URL, caches: URL, container: URL) -> StorageLocations {
        func support(_ name: String) -> URL { applicationSupport.appendingPathComponent(name, isDirectory: true) }
        func temp(_ name: String) -> URL { temporary.appendingPathComponent(name, isDirectory: true) }
        return StorageLocations(container: container, roots: [
            .photos: [support(PhotoStore.folderName)],
            .videos: [support(VideoStore.folderName)],
            .scenes: [support(SceneAutosaveStore.folderName)],
            .presets: [support(UserPresetStore.directoryName), support(PresetCollectionStore.directoryName)],
            .importedAudio: [support(audioLibraryFolderName)],
            .recordings: [temp(recordingsFolderName)],
            .sharesAndExports: [temp(sharingFolderName), temp(SceneArchiveService.exportFolderName), temp(presetExportFolderName)],
            .caches: [caches],
        ], extraProtectedRoots: [
            support(showFolderName),
            applicationSupport.deletingLastPathComponent().appendingPathComponent("Preferences", isDirectory: true),
        ])
    }

    /// The real container. Creates nothing.
    static func standard() -> StorageLocations {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches", isDirectory: true)
        return make(applicationSupport: support, temporary: fileManager.temporaryDirectory, caches: caches,
                    container: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
    }

    /// `standard()`, or the DEBUG fixture container with `-uitestStorageFixture`.
    static func forCurrentLaunch() -> StorageLocations {
        #if DEBUG
        if UITestStorageFixture.isEnabled { return UITestStorageFixture.locations }
        #endif
        return standard()
    }

    var request: StorageRequest {
        StorageRequest(container: container.path,
                       roots: roots.mapValues { (urls: [URL]) -> [String] in urls.map { (url: URL) -> String in url.path } })
    }

    /// FILE-010-R3: every folder of a category that is not cleanable, plus the show and preferences.
    var protectedRoots: [URL] {
        var urls: [URL] = []
        for category in StorageCategory.allCases where !category.isCleanable {
            urls += roots[category] ?? []
        }
        return urls + extraProtectedRoots
    }

    /// FILE-010: what Clear Caches plans, keeping `inUse` (absolute paths).
    func cleanupRequest(inUse: Set<String>) -> CacheCleanupRequest {
        var cacheRoots: [StorageCategory: [String]] = [:]
        for category in StorageCategory.allCases where category.isCleanable {
            cacheRoots[category] = (roots[category] ?? []).map { (url: URL) -> String in url.path }
        }
        return CacheCleanupRequest(container: container.path, cacheRoots: cacheRoots,
                                   protectedRoots: protectedRoots.map { (url: URL) -> String in url.path }, inUse: inUse)
    }
}
