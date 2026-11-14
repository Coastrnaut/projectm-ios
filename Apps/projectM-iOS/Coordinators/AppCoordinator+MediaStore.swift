// AppCoordinator+MediaStore.swift — FILE-008-R7, R8 (research FILE-008-D5): the launch pass over the
// content-addressed Photos and Videos folders. Called in `init` right after the FILE-005 restore
// recovery (a restore writes plain `<UUID>.ext` files) and before the photo and video coordinators read
// their stores:
//   1. synchronously, `prepare`: removes temporary import files and legacy names an earlier launch
//      already migrated (directory listing and file numbers only; no content is read);
//   2. on a utility task, `reconcile`: hashes and registers the remaining legacy copies and deletes
//      payloads no reference names. Legacy files keep resolving until the next launch's `prepare`, so
//      nothing the running app holds disappears.
import Foundation
import LocalPortability

extension AppCoordinator {
    /// The default photo and video folders (nil folders are skipped).
    nonisolated static func defaultMediaFolders(defaults: UserDefaults) -> [ContentAddressedMediaFolder] {
        var folders: [ContentAddressedMediaFolder] = []
        if let photos = try? PhotoStore.defaultDirectory() { folders.append(PhotoStore(directory: photos, defaults: defaults).folder) }
        if let videos = try? VideoStore.defaultDirectory() { folders.append(VideoStore(directory: videos, defaults: defaults).folder) }
        return folders
    }

    static func reconcileMediaFolders(defaults: UserDefaults) {
        let folders = defaultMediaFolders(defaults: defaults)
        for folder in folders { folder.prepare() }
        Task.detached(priority: .utility) { () -> Void in
            for folder in folders { _ = try? folder.reconcile() }
        }
    }
}
