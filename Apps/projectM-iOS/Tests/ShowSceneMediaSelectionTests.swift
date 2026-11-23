// ShowSceneMediaSelectionTests.swift — SHOW-001 Clarification 2026-11-23 (QA-011 FILE-001-T19 on D3): a cue whose
// scene names a stored but not current photo or video (a scene pack's adopted media, SCN-014-R6) makes them current,
// without releasing the previous ones; an unresolved identifier, the current picture under another reference and a
// slideshow-only photo asset change nothing. Each test has its own folder and UserDefaults suite; the pictures are the
// DEBUG fixtures (64 × 48 PNG, a short 64 × 48 movie). Owner rule 7: about 1-2 s.
import Foundation
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class ShowSceneMediaSelectionTests: XCTestCase {
    private var root: URL!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ShowSceneMediaSelection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "ShowSceneMediaSelection.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }

    private var photoStore: PhotoStore { PhotoStore(directory: root.appendingPathComponent("Photos", isDirectory: true), defaults: defaults) }
    private var videoStore: VideoStore { VideoStore(directory: root.appendingPathComponent("Videos", isDirectory: true), defaults: defaults) }

    private func pickedPhoto(alpha: Bool = false) throws -> URL {
        let url = root.appendingPathComponent("picked-\(UUID().uuidString).png")
        try XCTUnwrap(UITestPhotoFixture.png(alpha: alpha)).write(to: url)
        return url
    }

    /// A stored but not current photo, as a scene pack import leaves it (staged and adopted, never made current).
    private func adoptedPhoto(alpha: Bool) throws -> StoredPhoto {
        try photoStore.stage(at: try pickedPhoto(alpha: alpha))
    }

    func testTheCueSelectsTheScenesStoredPhotoAndKeepsThePreviousOne() throws {
        let previous = try photoStore.importImage(at: try pickedPhoto(alpha: false))
        let imported = try adoptedPhoto(alpha: true)
        let photos = PhotoCoordinator(store: photoStore, announce: { (_: String) -> Void in })
        var shown: [UUID?] = []
        photos.onPhotoChange = { (stored: StoredPhoto?) -> Void in shown.append(stored?.id) }
        XCTAssertEqual(photos.photo?.id, previous.id)

        XCTAssertTrue(photos.selectStored(storeID: imported.id.uuidString))
        XCTAssertEqual(photos.photo?.id, imported.id, "the scene's photo is the stored photo")
        XCTAssertEqual(photoStore.current()?.id, imported.id, "and stays so after a relaunch")
        XCTAssertEqual(shown, [imported.id], "the photo layer is told once")
        XCTAssertNotNil(photoStore.existingFile(for: previous.id), "nothing is released: other cues still find the previous photo")

        XCTAssertFalse(photos.selectStored(storeID: imported.id.uuidString), "already current")
        XCTAssertFalse(photos.selectStored(storeID: UUID().uuidString), "an identifier that does not resolve changes nothing")
        XCTAssertFalse(photos.selectStored(storeID: "not-a-uuid"))
        XCTAssertFalse(photos.selectStored(storeID: nil))
        XCTAssertEqual(photos.photo?.id, imported.id)
        XCTAssertEqual(shown, [imported.id])
    }

    func testAnotherReferenceToTheCurrentPictureChangesNothing() throws {
        let current = try photoStore.importImage(at: try pickedPhoto())
        let sameBytes = try adoptedPhoto(alpha: false)   // FILE-008: a second reference to the same payload
        let photos = PhotoCoordinator(store: photoStore, announce: { (_: String) -> Void in })
        XCTAssertFalse(photos.selectStored(storeID: sameBytes.id.uuidString))
        XCTAssertEqual(photoStore.current()?.id, current.id)
    }

    func testTheCueSelectsTheScenesStoredVideo() async throws {
        let movie = root.appendingPathComponent("picked.mov")
        try await UITestVideoFixture.writeCounter(to: movie, frames: 30)
        let staged = try await videoStore.stage(at: movie)   // adopted by an import, not current
        let videos = VideoCoordinator(store: videoStore, announce: { (_: String) -> Void in })
        XCTAssertNil(videos.video)
        XCTAssertTrue(videos.selectStored(storeID: staged.id.uuidString))
        XCTAssertEqual(videos.video?.id, staged.id, "the Video visual can play the scene's video")
        XCTAssertEqual(videoStore.current()?.id, staged.id)
        XCTAssertFalse(videos.selectStored(storeID: staged.id.uuidString), "already current")
        XCTAssertFalse(videos.selectStored(storeID: UUID().uuidString))
    }

    func testApplyCarriesThePhotoLayersOwnPhotoButNotASlideshowsFirstPicture() throws {
        let registry = try SceneArchiveService.appRegistry()
        let photoID = UUID().uuidString, videoID = UUID().uuidString
        var document = SceneDocument(id: UUID().uuidString, name: "Photo and Video",
                                     layers: [SceneLayer(instance: 1, content: .photo(asset: "photo")),
                                              SceneLayer(instance: 2, content: .video(asset: "video")),
                                              SceneLayer(instance: 3, content: .circularSpectrum)],
                                     parameters: [:],
                                     assets: ["photo": .photo(storeID: photoID), "video": .video(storeID: videoID)])
        var apply = ShowSceneSnapshot.apply(of: document, warnings: [], registry: registry)
        XCTAssertEqual(apply.visual, .photo)
        XCTAssertEqual(apply.photoStoreID, photoID)
        XCTAssertEqual(apply.videoStoreID, videoID)

        // MED-006: a scene without a photo of its own names its first slide in the photo asset.
        var asset = SceneAsset.photo(storeID: photoID)
        asset.photoSlideshow = SceneSlideshow(enabled: true, storeIDs: [photoID, UUID().uuidString], mode: "time", seconds: 5, beats: 4)
        document.assets["photo"] = asset
        apply = ShowSceneSnapshot.apply(of: document, warnings: [], registry: registry)
        XCTAssertNil(apply.photoStoreID, "the current photo is left alone")
    }
}
