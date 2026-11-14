// UITestScenePackFixture.swift — DEBUG only: `-uitestScenePackFixture` (SCN-014-T09; ScenePackUITests;
// research SCN-014-D8). Stores a photo, two slide pictures and a logo, saves the scene "Pack Scene" (photo
// visual, a two-picture slideshow, the logo) with one cue, and puts Scene Folders' pack coordinator in
// fixture mode: an export is kept as the "picked" file (no share sheet) and Import Scene… reads it (no
// system picker).
#if DEBUG
import Foundation
import ImageLayer
import SceneFormat
import ShowControl
import ShowStorage

@MainActor
enum UITestScenePackFixture {
    static let argument = "-uitestScenePackFixture"
    static let label = "Pack Scene"
    static let sceneID = "5CE7E000-0000-4000-8000-0000000000E1"
    static let cueID = UUID(uuidString: "C0E00000-0000-4000-8000-0000000000E1")!

    static func seedIfRequested(_ coordinator: AppCoordinator) {
        guard ProcessInfo.processInfo.arguments.contains(argument) else { return }
        let show: ShowCoordinator = coordinator.show
        guard let store: ShowStore = show.store, let packs: ScenePackCoordinator = show.scenePacks else { return }
        guard let directory: URL = try? PhotoStore.defaultDirectory() else { return }
        let photos = PhotoStore(directory: directory, defaults: .standard)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ScenePackFixtureSeed", isDirectory: true)
        try? FileManager.default.removeItem(at: scratch)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        func stage(_ data: Data?, logo: Bool = false) -> StoredPhoto? {
            guard let data else { return nil }
            let url = scratch.appendingPathComponent("seed-\(UUID().uuidString).png")
            guard (try? data.write(to: url)) != nil else { return nil }
            return logo ? try? LogoStore(photos: photos).stage(at: url) : try? photos.stage(at: url)
        }
        guard let photo = stage(UITestPhotoFixture.png(alpha: false)),
              let slide1 = stage(UITestPhotoFixture.png(alpha: false, color: (20, 160, 90))),
              let slide2 = stage(UITestPhotoFixture.png(alpha: false, color: (200, 40, 40))),
              let logo = stage(UITestPhotoFixture.png(alpha: true), logo: true) else { return }
        var look = coordinator.showLook
        look.visual = .photo
        look.videoID = nil
        look.photoID = photo.id
        look.slideshow = SceneSlideshow(enabled: true, storeIDs: [slide1.id.uuidString, slide2.id.uuidString], mode: "time", seconds: 5, beats: 4)
        look.logo = SceneLogo(storeID: logo.id.uuidString, placement: .default)
        try? store.saveScene(ShowSceneSnapshot.document(look, id: sceneID, name: label))
        var list = ShowCueList(id: UUID(uuidString: "5E0E0000-0000-4000-8000-0000000000E1")!, name: "UI Test Scene Pack")
        _ = try? list.append(sceneID: sceneID, label: label, cueID: cueID)
        show.replaceForUITests(list)
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("ScenePackFixture", isDirectory: true))
        packs.keepsExportForImport = true
    }
}
#endif
