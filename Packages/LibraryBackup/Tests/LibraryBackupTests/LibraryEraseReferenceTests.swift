// LibraryEraseReferenceTests.swift — FILE-011-T07 (FILE-011-S3, S4, R8; research FILE-011-D1, D3).
// * Erasing scenes releases the photo and video references only the erased scenes named (FILE-008's
//   registry: a payload goes with its last reference) and keeps the current photo and unrelated photos.
// * Erasing photos and videos leaves the scenes naming IDs that no longer resolve ("no longer stored").
// * No write-back: what the running app writes after the request (an autosave tick, a saved scene) is
//   gone after the launch-time erase, and stores loaded afterwards read an empty library.
import Foundation
import LocalPortability
import PresetLibrary
import SceneFormat
import ShowControl
import ShowStorage
import XCTest
@testable import LibraryBackup

final class LibraryEraseReferenceTests: XCTestCase {
    private let current = UUID(uuidString: "0A000000-0000-4000-8000-000000000001")!   // the current photo, also in a scene
    private let sharing = UUID(uuidString: "0A000000-0000-4000-8000-000000000002")!   // scene only, same bytes as `current`
    private let alone = UUID(uuidString: "0A000000-0000-4000-8000-000000000003")!     // scene only, own bytes
    private let unrelated = UUID(uuidString: "0A000000-0000-4000-8000-000000000004")! // in no scene
    private let clip = UUID(uuidString: "0B000000-0000-4000-8000-000000000001")!      // a video only the current scene names

    private struct Library {
        let root: URL
        let photos: ContentAddressedMediaFolder
        let videos: ContentAddressedMediaFolder
        var show: ShowStore { ShowStore(directory: LibraryFolders(root: root).url(.show)) }
    }

    private func scene(_ n: Int, photos: [UUID], video: UUID? = nil) -> SceneDocument {
        var assets: [String: SceneAsset] = [:]
        var layers: [SceneLayer] = []
        for (index, id) in photos.enumerated() {
            assets["p\(index)"] = .photo(storeID: id.uuidString)
            layers.append(SceneLayer(instance: UInt64(index + 1), content: .photo(asset: "p\(index)")))
        }
        if let video {
            assets["v"] = .video(storeID: video.uuidString)
            layers.append(SceneLayer(instance: 9, content: .video(asset: "v")))
        }
        return SceneDocument(id: BackupFixtures.sceneID(n), name: "Scene \(n)", layers: layers, assets: assets)
    }

    private func intern(_ bytes: Data, as id: UUID, ext: String, into folder: ContentAddressedMediaFolder, scratch: URL) throws {
        let source = scratch.appendingPathComponent(id.uuidString + "." + ext)
        try bytes.write(to: source)
        _ = try folder.intern(source, as: id, consumingSource: true)
    }

    private func library(_ label: String) throws -> Library {
        let sandbox = BackupFixtures.sandbox(self, label)
        let root = sandbox.root
        let photos = ContentAddressedMediaFolder(directory: sandbox.url(.photos), extensions: LibraryErasePolicy.photoExtensions)
        let videos = ContentAddressedMediaFolder(directory: root.appendingPathComponent(LibraryErasePolicy.videosFolderName, isDirectory: true),
                                                 extensions: LibraryErasePolicy.videoExtensions)
        let scratch = root.appendingPathComponent("scratch", isDirectory: true)
        for url in [photos.directory, videos.directory, scratch] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        try intern(BackupFixtures.png(1), as: current, ext: "png", into: photos, scratch: scratch)
        try intern(BackupFixtures.png(1), as: sharing, ext: "png", into: photos, scratch: scratch)
        try intern(BackupFixtures.png(2), as: alone, ext: "png", into: photos, scratch: scratch)
        try intern(BackupFixtures.png(3), as: unrelated, ext: "png", into: photos, scratch: scratch)
        try intern(Data("MOVIE".utf8), as: clip, ext: "mov", into: videos, scratch: scratch)
        try FileManager.default.removeItem(at: scratch)
        let lib = Library(root: root, photos: photos, videos: videos)
        var list = ShowCueList(id: BackupFixtures.uuid(900), name: "Media show")
        try lib.show.saveScene(scene(1, photos: [current, sharing]))
        try list.append(sceneID: BackupFixtures.sceneID(1), label: "One", cueID: BackupFixtures.uuid(1))
        try lib.show.save(list)
        let folders = LibraryFolders(root: root)
        try FileManager.default.createDirectory(at: folders.url(.currentScene), withIntermediateDirectories: true)
        try Data(scene(2, photos: [alone], video: clip).encoded()).write(to: folders.currentSceneFile)
        return lib
    }

    private var settings: [String: LibrarySettingValue] { [LibrarySettingsPolicy.photoKey: .string(current.uuidString)] }

    func testErasingScenesReleasesSceneOnlyMediaAndKeepsTheCurrentPhoto() throws {
        let lib = try library("scenes")
        XCTAssertEqual(lib.photos.payloadNames().count, 3, "current and sharing share one payload")
        let plan = LibraryErasePlanner.plan([.scenes], root: lib.root, settings: settings)
        XCTAssertEqual(plan.releasedPhotos, [sharing.uuidString, alone.uuidString].sorted())
        XCTAssertEqual(plan.releasedVideos, [clip.uuidString])
        let defaults = EraseFixtures.Defaults(settings)
        try LibraryEraseRequestStore(root: lib.root).save([.scenes])
        let note = LibraryEraseLaunch.run(root: lib.root, settings: defaults.values) { (keys: [String]) in defaults.remove(keys) }
        XCTAssertEqual(note?.erased, true)
        XCTAssertNotNil(lib.photos.resolve(current), "the current photo stays")
        XCTAssertNotNil(lib.photos.resolve(unrelated), "a photo no scene named stays")
        XCTAssertNil(lib.photos.resolve(sharing), "a scene-only reference is released")
        XCTAssertNil(lib.photos.resolve(alone))
        XCTAssertNil(lib.videos.resolve(clip))
        XCTAssertEqual(lib.photos.payloadNames().count, 2, "the shared payload stays for the current photo; the lone one is deleted")
        XCTAssertEqual(lib.videos.payloadNames(), [], "the video's last reference went, and its payload with it")
        XCTAssertEqual(defaults.values, settings, "erasing scenes removes no setting")
    }

    func testErasingMediaLeavesScenesNamingMediaThatIsNoLongerStored() throws {
        let lib = try library("media")
        let named = lib.show.referencedMediaIDs()
        let sceneBytes = try Data(contentsOf: lib.show.sceneFile(BackupFixtures.sceneID(1)))
        let defaults = EraseFixtures.Defaults(settings)
        try LibraryEraseRequestStore(root: lib.root).save([.media])
        let note = LibraryEraseLaunch.run(root: lib.root, settings: defaults.values) { (keys: [String]) in defaults.remove(keys) }
        XCTAssertEqual(note, LibraryEraseResultNote(erased: true, message: "Erased: photos and videos."))
        XCTAssertEqual(lib.show.referencedMediaIDs(), named, "the scenes still name their media")
        XCTAssertEqual(try Data(contentsOf: lib.show.sceneFile(BackupFixtures.sceneID(1))), sceneBytes, "scenes are unchanged")
        for id in [current, sharing, alone, unrelated] { XCTAssertNil(lib.photos.resolve(id), "\(id) no longer resolves") }
        XCTAssertNil(lib.videos.resolve(clip))
        XCTAssertNil(defaults.values[LibrarySettingsPolicy.photoKey], "the current photo choice is cleared")
    }

    func testErasingScenesAndMediaTogetherReleasesNothingSeparately() throws {
        let lib = try library("both")
        let plan = LibraryErasePlanner.plan([.scenes, .media], root: lib.root, settings: settings)
        XCTAssertEqual(plan.releasedPhotos, [], "the folders go as a whole")
        XCTAssertEqual(plan.folders, ["Show", "Scenes", "Photos", "Videos"])
    }

    func testNothingTheRunningAppWritesAfterTheRequestSurvivesTheLaunchErase() throws {
        let sandbox = try EraseFixtures.sandbox(self, "writeback")
        let defaults = EraseFixtures.Defaults()
        let folders = sandbox.folders
        try LibraryEraseRequestStore(root: sandbox.root).save([.scenes, .collections])
        // The app keeps running until it is closed: an autosave tick, a saved scene, a changed collection.
        try BackupFixtures.sceneBytes(42, variant: 2).write(to: folders.currentSceneFile)
        try ShowStore(directory: folders.url(.show)).saveScene(BackupFixtures.scene(43))
        try PresetCollectionsFile(collections: [PresetCollection(id: BackupFixtures.uuid(60).uuidString, name: "Late", presetIDs: [])]).encode()
            .write(to: folders.collectionsFile)
        defaults.values[LibrarySettingsPolicy.favoritesKey] = .strings(["included/Late.milk"])
        // Next launch, before any store loads.
        let note = LibraryEraseLaunch.run(root: sandbox.root, settings: defaults.values) { (keys: [String]) in defaults.remove(keys) }
        XCTAssertEqual(note?.erased, true)
        let contents = try LibraryContentsReader.read(folders: folders, settings: defaults.values)
        XCTAssertNil(contents.currentScene, "the autosave tick is gone")
        XCTAssertEqual(contents.scenes, [:])
        XCTAssertNil(contents.show)
        XCTAssertNil(contents.collections)
        XCTAssertNil(defaults.values[LibrarySettingsPolicy.favoritesKey])
        XCTAssertEqual(ShowStore(directory: folders.url(.show)).storedSceneIDs(), [], "a store loaded now reads an empty show")
        XCTAssertEqual(contents.presets.count, 3, "My Presets were not chosen")
    }
}
