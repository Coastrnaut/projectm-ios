// AppCoordinator+CacheCleanup.swift — FILE-010-R5: the files cache cleanup must keep, gathered on the main
// actor when Clear Caches is tapped and again just before clearing (contracts/cache-cleanup.md C2, C3):
// a recording being made or offered (REC-003, REC-012), a share copy on show (REC-012), a preset export
// being written or shared (PRE-014). FILE-001's scene archive export is not wired into the app yet.
import Foundation

extension AppCoordinator {
    func cacheFilesInUse() -> Set<String> {
        var urls: [URL] = videoRecording.filesInUse + userPresets.filesInUse
        if let share = captureShare.request { urls.append(share.url) }
        return Set(urls.map { (url: URL) -> String in url.standardizedFileURL.path })
    }
}
