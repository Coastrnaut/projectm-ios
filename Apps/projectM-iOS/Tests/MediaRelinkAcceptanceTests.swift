// MediaRelinkAcceptanceTests.swift — MED-013-T12, T13: the roadmap acceptance "Missing asset shows
// placeholder; relink restores all scene references" (MED-013-S1-S4).
// Scenes A (photo P) and B (photo O with P in its slideshow) each have a cue; the settings slideshow also
// names P. P's file is deleted: the cue for A shows the repair report with missing media, opening it as is
// sets the placeholder, and Missing Media lists P "used by 2 scenes and 2 cues". Then, separately:
// relink by checksum (the same picture imported again) and relink by replacement (another picture,
// every reference rewritten, persisted on disk). Also: released identifiers, the folder scan, a failing
// rewrite, and FILE-011's forgetting. Each test has its own folders and UserDefaults suite; the pictures
// are the DEBUG fixture PNGs (64 × 48).
import Foundation
import ImageLayer
import LocalPortability
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import XCTest
@testable import projectM_iOS

@MainActor
final class MediaRelinkAcceptanceTests: XCTestCase {
    private struct World {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        let service: MediaRelinkService
        let p: UUID
        let o: UUID
        let list: ShowCueList
        let pPayload: URL
        var photos: PhotoStore { service.photos }
        var show: ShowStore { service.show }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private let sceneA = "5CE7E000-0000-4000-8000-0000000000A1"
    private let sceneB = "5CE7E000-0000-4000-8000-0000000000B1"
    private let cueA = UUID(uuidString: "C0E00000-0000-4000-8000-0000000000A1")!
    private let cueB = UUID(uuidString: "C0E00000-0000-4000-8000-0000000000B1")!

    private func picked(_ root: URL, color: (UInt8, UInt8, UInt8) = (230, 120, 30)) throws -> URL {
        let url = root.appendingPathComponent("picked-\(UUID().uuidString).png")
        try XCTUnwrap(UITestPhotoFixture.png(alpha: false, color: color)).write(to: url)
        return url
    }

    /// Steps 1-2 of the acceptance: the scenes, the cues and P's file deleted.
    private func makeWorld() throws -> World {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaRelink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "MediaRelinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let service = MediaRelinkService(photos: PhotoStore(directory: root.appendingPathComponent("Photos"), defaults: defaults),
                                         videos: VideoStore(directory: root.appendingPathComponent("Videos"), defaults: defaults),
                                         show: ShowStore(directory: root.appendingPathComponent("Show")))
        let p = try service.photos.stage(at: try picked(root))
        let o = try service.photos.stage(at: try picked(root, color: (20, 160, 90)))
        let a = SceneDocument(id: sceneA, name: "A", layers: [SceneLayer(instance: 1, content: .photo(asset: "photo"))],
                              assets: ["photo": .photo(storeID: p.id.uuidString)])
        var slides = SceneAsset.photo(storeID: o.id.uuidString)
        slides.photoSlideshow = SceneSlideshow(enabled: true, storeIDs: [o.id.uuidString, p.id.uuidString], mode: "time", seconds: 5, beats: 4)
        let b = SceneDocument(id: sceneB, name: "B", layers: [SceneLayer(instance: 1, content: .photo(asset: "photo"))],
                              assets: ["photo": slides])
        try service.show.saveScene(a)
        try service.show.saveScene(b)
        var list = ShowCueList(id: UUID(), name: "Relink show")
        try list.append(sceneID: sceneA, label: "Cue A", cueID: cueA)
        try list.append(sceneID: sceneB, label: "Cue B", cueID: cueB)
        try service.show.save(list)
        defaults.set(SlideshowSettings.off.with(slides: [p.id]).with(enabled: true).encoded, forKey: SlideshowStore.key)
        try FileManager.default.removeItem(at: p.url)   // step 2: P's file is lost
        return World(root: root, defaults: defaults, suite: suite, service: service, p: p.id, o: o.id, list: list, pPayload: p.url)
    }

    private func coordinator(_ world: World) -> MissingMediaCoordinator {
        let model = MissingMediaCoordinator(service: world.service)
        let list = world.list
        model.cues = { () -> ShowCueList in list }
        return model
    }

    /// Every photo identifier named by A and B, read from disk.
    private func namedPhotos(_ world: World) throws -> [String: [String]] {
        let store = ShowStore(directory: world.show.directory)
        var result: [String: [String]] = [:]
        for id in [sceneA, sceneB] {
            result[id] = try store.scene(id).document.mediaReferences.filter { (r: SceneMediaReference) -> Bool in r.store == .photos }.map(\.storeID)
        }
        return result
    }

    // MARK: - Acceptance steps 3-4: placeholder, missing list, relink by checksum

    func testMissingPhotoShowsThePlaceholderAndAChecksumRelinkRestoresEveryReference() throws {
        let world = try makeWorld()
        defer { world.cleanUp() }
        let model = coordinator(world)

        // Step 3a: the cue shows the repair report (missing media); opening it as is sets the placeholder.
        let registry = try SceneArchiveService.appRegistry()
        let show = ShowCoordinator(store: world.show, registry: registry)
        show.availability = { () -> StoredMediaAvailability in
            StoredMediaAvailability(photos: Set(world.photos.knownIDs().map(\.uuidString)), videos: [])
        }
        var request: SceneRepairRequest?
        show.requestRepair = { (r: SceneRepairRequest) in request = r }
        show.applyScene = { (document: SceneDocument, warnings: [SceneIssue]) -> [String] in
            model.sceneApplied(document, missingMedia: warnings.contains { (i: SceneIssue) -> Bool in i.code == .missingAsset })
            return []
        }
        show.go(to: cueA)
        let report = try XCTUnwrap(request?.report, "the repair report comes first")
        XCTAssertTrue(report.groups.contains(.missingMedia))
        XCTAssertTrue(try XCTUnwrap(request).canOpenAsIs)
        try XCTUnwrap(request).open(try XCTUnwrap(request?.document))
        let placeholder = try XCTUnwrap(model.placeholder, "the placeholder is shown")
        XCTAssertEqual(placeholder.sceneName, "A")
        XCTAssertEqual(placeholder.missing.map(\.storeID), [world.p.uuidString])
        XCTAssertEqual(try namedPhotos(world)[sceneA], [world.p.uuidString], "applying never drops the reference")

        // Step 3b: Missing Media lists P with 2 scenes and 2 cues.
        model.refresh()
        XCTAssertEqual(model.items.count, 1)
        let item = try XCTUnwrap(model.items.first)
        XCTAssertEqual(item.storeID, world.p)
        XCTAssertEqual(item.sceneIDs, [sceneA, sceneB])
        XCTAssertEqual(item.cueCount, 2)
        XCTAssertTrue(item.checksumKnown)
        XCTAssertEqual(item.usageText, "Used by 2 scenes and 2 cues")
        XCTAssertNotNil(model.placeholder, "still missing")

        // Step 4: the same picture imported again (as the Photo setting's import does).
        var announced: [String] = []
        model.announce = { (text: String) in announced.append(text) }
        _ = try world.photos.importImage(at: try picked(world.root))
        model.mediaImported()
        XCTAssertNotNil(world.photos.existingFile(for: world.p), "P resolves again")
        XCTAssertEqual(world.photos.existingFile(for: world.p), world.pPayload)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.placeholder, "the placeholder clears")
        XCTAssertEqual(try namedPhotos(world)[sceneA], [world.p.uuidString], "no scene edit was needed")
        XCTAssertEqual(try namedPhotos(world)[sceneB], [world.o.uuidString, world.o.uuidString, world.p.uuidString])
        XCTAssertEqual(announced, ["Relinked 1 missing item by checksum."])
        let availability = StoredMediaAvailability(photos: Set(world.photos.knownIDs().map(\.uuidString)), videos: [])
        for id in [sceneA, sceneB] {
            let document = try world.show.scene(id).document
            XCTAssertFalse(document.validate(registry: registry, assets: availability).contains { (i: SceneIssue) -> Bool in i.code == .missingAsset },
                           "every reference in \(id) resolves")
        }
    }

    func testAReleasedIdentifierIsAdoptedWhenTheSameBytesAreImportedAgain() throws {
        let world = try makeWorld()
        defer { world.cleanUp() }
        try world.photos.folder.release([world.p])   // e.g. a new current photo released it (FILE-008)
        let model = coordinator(world)
        model.refresh()
        XCTAssertEqual(model.items.first?.checksumKnown, true, "the registry kept its payload name")
        _ = try world.photos.stage(at: try picked(world.root))
        model.refresh()
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNotNil(world.photos.existingFile(for: world.p))
    }

    // MARK: - Acceptance steps 5-6: relink by replacement, persisted

    func testReplacementRewritesEveryReferenceAtomicallyAndPersists() async throws {
        let world = try makeWorld()
        defer { world.cleanUp() }
        let model = coordinator(world)
        model.refresh()
        let item = try XCTUnwrap(model.items.first)
        var announced: [String] = []
        model.announce = { (text: String) in announced.append(text) }
        await model.replace(item, with: try picked(world.root, color: (10, 10, 200)))

        let named = try namedPhotos(world)
        let newID = try XCTUnwrap(named[sceneA]?.first)
        XCTAssertNotEqual(newID, world.p.uuidString)
        XCTAssertEqual(named[sceneB], [world.o.uuidString, world.o.uuidString, newID], "B's slideshow names the new picture")
        XCTAssertNotNil(world.photos.existingFile(for: try XCTUnwrap(UUID(uuidString: newID))))
        XCTAssertEqual(SlideshowSettings.decode(world.defaults.data(forKey: SlideshowStore.key)).slides.map(\.uuidString), [newID],
                       "the settings slideshow follows")
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.resultText,
                       "Relinked: 2 scenes and 2 cues now use the new photo (2 references). It differs from the original.")
        XCTAssertEqual(announced, [try XCTUnwrap(model.resultText)])
        XCTAssertNil(world.photos.folder.knownPayloadName(of: world.p), "the old identifier is forgotten")

        // Step 6: reload from disk (a new store and a new coordinator).
        let reloaded = MediaRelinkService(photos: PhotoStore(directory: world.photos.directory, defaults: world.defaults),
                                          videos: world.service.videos, show: ShowStore(directory: world.show.directory))
        XCTAssertTrue(reloaded.missingItems(cues: world.list).isEmpty)
        XCTAssertEqual(reloaded.show.mediaUsage().scenes[ShowMediaKey(store: .photos, storeID: newID)], [sceneA, sceneB])
        XCTAssertNil(reloaded.show.mediaUsage().scenes[ShowMediaKey(store: .photos, storeID: world.p.uuidString)])
    }

    func testAFailingRewriteChangesNothingAndDiscardsTheStagedCopy() async throws {
        let world = try makeWorld()
        defer { world.cleanUp() }
        let item = try XCTUnwrap(world.service.missingItems(cues: world.list).first)
        let scenes = world.show.scenesFolder
        let before = try FileManager.default.contentsOfDirectory(atPath: scenes.path).sorted()
        let bytes = try before.map { (name: String) -> Data in try Data(contentsOf: scenes.appendingPathComponent(name)) }
        let payloadsBefore = world.photos.folder.payloadNames()
        let slideshowBefore = world.defaults.data(forKey: SlideshowStore.key)
        // A scenes folder that cannot be written makes the stage step fail.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: scenes.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scenes.path) }
        let replacement = try picked(world.root, color: (10, 10, 200))
        do throws(MediaRelinkError) {
            _ = try await world.service.replace(item, with: replacement, cues: world.list)
            XCTFail("the rewrite must fail")
        } catch {
            XCTAssertEqual(error, .rewriteFailed)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scenes.path)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scenes.path).sorted(), before)
        XCTAssertEqual(try before.map { (name: String) -> Data in try Data(contentsOf: scenes.appendingPathComponent(name)) }, bytes)
        XCTAssertEqual(world.photos.folder.payloadNames(), payloadsBefore, "the staged copy was discarded")
        XCTAssertEqual(world.defaults.data(forKey: SlideshowStore.key), slideshowBefore)
        XCTAssertEqual(world.service.missingItems(cues: world.list).map(\.storeID), [world.p])
    }

    // MARK: - Folder scan and erase (MED-013-T13)

    func testFindInFolderRestoresAMatchAndIgnoresOtherFiles() async throws {
        let world = try makeWorld()
        defer { world.cleanUp() }
        // A backup folder: P's stored bytes (re-created from the same picture), plus unrelated files.
        let backup = world.root.appendingPathComponent("Backup/photos", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        let copy = try world.service.photos.stage(at: try picked(world.root))   // same sanitized bytes as P
        try FileManager.default.copyItem(at: copy.url, to: backup.appendingPathComponent("\(world.p.uuidString).png"))
        try world.photos.folder.release([copy.id])
        try FileManager.default.removeItem(at: copy.url)   // P is missing again
        XCTAssertNil(world.photos.existingFile(for: world.p))
        try Data([1, 2, 3]).write(to: backup.appendingPathComponent("other.png"))
        try Data("notes".utf8).write(to: backup.appendingPathComponent("notes.txt"))
        let model = coordinator(world)
        model.refresh()
        XCTAssertTrue(model.canFindInFolder)
        await model.findInFolder(backup.deletingLastPathComponent())
        XCTAssertEqual(model.resultText, "Relinked 1 missing item by checksum.")
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNotNil(world.photos.existingFile(for: world.p))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backup.path).sorted(),
                       ["\(world.p.uuidString).png", "notes.txt", "other.png"], "the folder is only read")

        // A folder without a match.
        try world.photos.folder.release([world.p])
        let empty = world.root.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        model.refresh()
        await model.findInFolder(empty)
        XCTAssertEqual(model.resultText, "No matching files were found.")
    }

    func testAfterAnEraseForgetsTheIdentifierOnlyReplacementIsLeft() throws {
        let world = try makeWorld()
        defer { world.cleanUp() }
        try world.photos.folder.release([world.p])
        try world.photos.folder.forget([world.p])   // as FILE-011's scenes-only erase does (LibraryEraser)
        let model = coordinator(world)
        model.refresh()
        let item = try XCTUnwrap(model.items.first)
        XCTAssertFalse(item.checksumKnown)
        XCTAssertEqual(item.usageText, "Used by 2 scenes and 2 cues, checksum unknown")
        XCTAssertFalse(model.canFindInFolder, "nothing a folder could match")
        _ = try world.photos.stage(at: try picked(world.root))
        model.refresh()
        XCTAssertEqual(model.items.map(\.storeID), [world.p], "the same picture cannot be recognised without its checksum")
    }
}
