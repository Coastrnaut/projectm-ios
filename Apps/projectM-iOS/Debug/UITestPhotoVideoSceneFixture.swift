// UITestPhotoVideoSceneFixture.swift — DEBUG only (QA-011 FILE-001-T19; ScenePackPhotoVideoUITests and
// B07FilesDeviceTests.testFILE001_A_ExportSceneArchive). `-uitestPhotoVideoScene` (with `-uitestSeedPhoto` and
// `-uitestSeedVideo`) stores the scene "Photo and Video" in the show: the stored photo under the stored video, with
// the circular spectrum on top, and one cue for it.
//
// Why a seed: the app's own scene captures (Add Current Scene, `ShowSceneSnapshot`; the autosave,
// `SceneAutosaveCapture`) record the hosts' fixed stacks, one visual each: Photo `[photo, spectrum.circular]`, Video
// `[video, spectrum.circular]`. No screen adds a layer, so no scene the app captures holds a photo and a video at
// once (FILE-001-T19 on D2, 2026-11-22: the archive held only the video). SCN-001 documents and the FILE-001 archive
// do carry both (FILE-001-S1's fixture scene); this seed builds that scene from the stored copies with the
// snapshot's own photo and video layers and assets, and saves it through the show's real paths (`addScene`, or
// `saveEditedScene` on a relaunch: a fixed scene ID, so repeated runs on a device keep one current copy).
// `-uitestScenePackKeepExport` also puts Scene Folders' pack coordinator in fixture mode (research SCN-014-D8: the
// export is kept as the "picked" file, no share sheet or Files picker) for the simulator test.
// Not compiled into Release builds.
#if DEBUG
import Foundation
import SceneFormat

@MainActor
enum UITestPhotoVideoSceneFixture {
    static let argument = "-uitestPhotoVideoScene"
    static let keepExportArgument = "-uitestScenePackKeepExport"
    static let name = "Photo and Video"
    static let sceneID = "5CE7E000-0000-4000-8000-0000000000F1"

    /// The scene for `look`'s stored photo and video, bottom first: photo, video, circular spectrum. Nil without
    /// both a stored photo and a stored video.
    static func document(_ look: ShowLook, id: String = sceneID) -> SceneDocument? {
        guard look.photoID != nil, look.videoID != nil else { return nil }
        var photoLook = look, videoLook = look
        photoLook.visual = .photo
        videoLook.visual = .video
        let photo = ShowSceneSnapshot.document(photoLook, id: id, name: name)
        var document = ShowSceneSnapshot.document(videoLook, id: id, name: name)
        guard let photoLayer = photo.layers.first(where: { (l: SceneLayer) -> Bool in l.kind == "photo" }),
              let videoLayer = document.layers.first(where: { (l: SceneLayer) -> Bool in l.kind == "video" }) else { return nil }
        document.layers = [
            SceneLayer(instance: 1, content: photoLayer.content),
            SceneLayer(instance: 2, content: videoLayer.content),
            SceneLayer(instance: 3, content: .circularSpectrum),
        ]
        for (key, asset) in photo.assets where document.assets[key] == nil { document.assets[key] = asset }
        return document
    }

    static func seedIfRequested(_ coordinator: AppCoordinator) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(keepExportArgument) { coordinator.show.scenePacks?.keepsExportForImport = true }
        guard arguments.contains(argument) else { return }
        Task { @MainActor [weak coordinator] in
            // The photo and video seeds import asynchronously: wait (up to 60 s) until both are stored.
            for _ in 0..<240 {
                guard let coordinator else { return }
                if let document = document(coordinator.showLook) {
                    save(document, show: coordinator.show)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            print("UITestPhotoVideoSceneFixture: no stored photo and video after 60 s; nothing seeded")
        }
    }

    private static func save(_ document: SceneDocument, show: ShowCoordinator) {
        if show.list.sceneIDs.contains(document.id) {
            if case let .refused(message) = show.saveEditedScene(document, expectedBytes: nil) {
                print("UITestPhotoVideoSceneFixture: \(message)")
            }
        } else if !show.addScene(document, label: name) {
            print("UITestPhotoVideoSceneFixture: the scene was not added (\(show.editorMessage ?? "no message"))")
        }
    }
}
#endif
