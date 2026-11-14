// UITestMissingMediaFixture.swift — DEBUG only: `-uitestMissingMediaSeed` (MED-013-T14; MissingMediaUITests).
// Stores a 64 × 48 photo P, saves scenes "Opening" (photo P) and "Slides" (another photo with P in its
// slideshow) with one cue each, keeps a copy of P's stored bytes in `<tmp>/MissingMediaFixture/Backup`
// (Find Missing Media in Folder… scans it, since the folder picker cannot be automated), deletes P's
// payload file, and records "Opening" as applied with missing media, so the placeholder tile shows.
#if DEBUG
import Foundation
import SceneFormat
import ShowControl
import ShowStorage

@MainActor
enum UITestMissingMediaFixture {
    static let argument = "-uitestMissingMediaSeed"
    static let labels = ["Opening", "Slides"]

    static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-0000000000D\(n)" }
    static func cueID(_ n: Int) -> UUID { UUID(uuidString: "C0E00000-0000-4000-8000-0000000000D\(n)")! }

    static var backupFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MissingMediaFixture/Backup", isDirectory: true)
    }

    static func seedIfRequested(_ coordinator: AppCoordinator) {
        guard ProcessInfo.processInfo.arguments.contains(argument) else { return }
        guard let service: MediaRelinkService = coordinator.missingMedia.service else { return }
        guard let store: ShowStore = coordinator.show.store else { return }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("MissingMediaFixture", isDirectory: true)
        try? FileManager.default.removeItem(at: scratch)
        try? FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        guard let photo = stage(UITestPhotoFixture.png(alpha: false), service: service, scratch: scratch),
              let other = stage(UITestPhotoFixture.png(alpha: false, color: (20, 160, 90)), service: service, scratch: scratch) else { return }
        // The "backup": P's stored bytes under its logical name (as a FILE-006 folder backup holds them).
        try? FileManager.default.copyItem(at: photo.url, to: backupFolder.appendingPathComponent("\(photo.id.uuidString).png"))
        try? FileManager.default.removeItem(at: photo.url)   // P's file is lost; its registry entry stays

        var look = coordinator.showLook
        look.visual = .photo
        look.videoID = nil
        look.logo = nil
        look.photoID = photo.id
        look.slideshow = nil
        let opening = ShowSceneSnapshot.document(look, id: sceneID(1), name: labels[0])
        look.photoID = other.id
        look.slideshow = SceneSlideshow(enabled: true, storeIDs: [other.id.uuidString, photo.id.uuidString], mode: "time", seconds: 5, beats: 4)
        let slides = ShowSceneSnapshot.document(look, id: sceneID(2), name: labels[1])
        try? store.saveScene(opening)
        try? store.saveScene(slides)
        var list = ShowCueList(id: UUID(uuidString: "5E0E0000-0000-4000-8000-0000000000D1")!, name: "UI Test Missing Media")
        for n in 1...2 { _ = try? list.append(sceneID: sceneID(n), label: labels[n - 1], cueID: cueID(n)) }
        list.go(to: cueID(1))
        coordinator.show.replaceForUITests(list)
        coordinator.show.markAppliedForUITests(sceneID(1))
        coordinator.missingMedia.fixtureFolder = backupFolder
        coordinator.noteAppliedSceneMedia(opening, missingMedia: true)
    }

    private static func stage(_ data: Data?, service: MediaRelinkService, scratch: URL) -> StoredPhoto? {
        guard let data else { return nil }
        let url = scratch.appendingPathComponent("seed-\(UUID().uuidString).png")
        guard (try? data.write(to: url)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        return try? service.photos.stage(at: url)
    }
}
#endif
