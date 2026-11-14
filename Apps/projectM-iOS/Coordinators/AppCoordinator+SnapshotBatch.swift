// AppCoordinator+SnapshotBatch.swift — REC-002: the image batch export's link to the app
// (specs/234-rec-002-image-batch-export; R1, R8, R10).
//
// * The export reads the live settings and the snapshot list (never writes them), saves to Photos through REC-011's
//   coordinator and announces on the library lane (ACC-004).
import Foundation

extension AppCoordinator {
    func connectSnapshotBatch() {
        snapshotBatch.connect(settings: settings, snapshots: sceneSnapshots, photos: photosSave,
                              announce: { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .library) })
    }
}
