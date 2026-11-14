// ScenePackAcceptanceTests.swift — SCN-014-T08: the roadmap acceptance in the app ("Reimport offline
// reproduces scene without absolute filesystem paths"; SCN-014-S1 to S4) with real stores in a temporary
// sandbox and its own UserDefaults suite. Nothing here uses the network (the app links no networking API
// for this path; `check_network_symbols` covers the binary).
// 1. A scene with a photo, a two-picture slideshow, a logo and text is exported as a pack.
// 2. No string in the pack's manifest or scene, no entry name and no byte run names a disk location.
// 3. The device's media and show stores are wiped, the pack is imported: the scene equals the original apart
//    from its media identifiers, every media reference resolves to a byte-identical picture, a cue is added,
//    and the scene loads with no missing media and the photo visual.
// Also: re-importing adds nothing (identical; one payload per picture); a stored scene with the same ID gives a
// copy; a pack missing a listed picture, a pack with a `../` entry and a file that is not a pack are refused
// with nothing written; the coordinator's export → import path adds the cue and announces it.
import Foundation
import LocalPortability
import ParameterGraph
import SceneArchive
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class ScenePackAcceptanceTests: XCTestCase {
    private struct Sandbox {
        let root: URL
        let defaults: UserDefaults
        let suite: String

        var photosFolder: URL { root.appendingPathComponent("Photos") }
        var videosFolder: URL { root.appendingPathComponent("Videos") }
        var showFolder: URL { root.appendingPathComponent("Show") }
        func photos() -> PhotoStore { PhotoStore(directory: photosFolder, defaults: defaults) }
        func videos() -> VideoStore { VideoStore(directory: videosFolder, defaults: defaults) }

        func archive() throws -> SceneArchiveService {
            SceneArchiveService(photos: photos(), videos: videos(), registry: try SceneArchiveService.appRegistry(),
                                temporaryRoot: root.appendingPathComponent("tmp"))
        }

        func importer() throws -> ScenePackImporter { ScenePackImporter(archive: try archive(), show: ShowStore(directory: showFolder)) }

        @MainActor func show(spoken: @escaping (String) -> Void = { (_: String) in }) -> ShowCoordinator {
            let show = ShowCoordinator(store: ShowStore(directory: showFolder), registry: try? SceneArchiveService.appRegistry())
            show.applyScene = { (_: SceneDocument, _: [SceneIssue]) -> [String] in XCTFail("an import applies nothing"); return [] }
            show.announce = { (_: String) in }
            show.announceLibrary = spoken
            return show
        }

        /// Every file in the media and show folders (name → bytes).
        func snapshot() -> [String: Data] {
            var result: [String: Data] = [:]
            for folder in [photosFolder, videosFolder, showFolder] {
                let names = (FileManager.default.subpaths(atPath: folder.path) ?? []).sorted()
                for name in names {
                    result[folder.lastPathComponent + "/" + name] = try? Data(contentsOf: folder.appendingPathComponent(name))
                }
            }
            return result
        }
    }

    private func makeSandbox() throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScenePackAcceptanceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "ScenePackAcceptanceTests.\(UUID().uuidString)"
        let sandbox = Sandbox(root: root, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), suite: suite)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            UserDefaults().removePersistentDomain(forName: suite)
        }
        return sandbox
    }

    /// Stores a picture as a picked file would be (photo or logo import path).
    private func store(_ data: Data?, in sandbox: Sandbox, logo: Bool = false) throws -> StoredPhoto {
        let url = sandbox.root.appendingPathComponent("picked-\(UUID().uuidString).png")
        try XCTUnwrap(data).write(to: url)
        return logo ? try LogoStore(photos: sandbox.photos()).stage(at: url) : try sandbox.photos().stage(at: url)
    }

    private func sceneJSON(_ value: Any) -> SceneJSON {
        switch value {
        case let dictionary as [String: Any]: return .object(dictionary.mapValues { (v: Any) -> SceneJSON in sceneJSON(v) })
        case let array as [Any]: return .array(array.map { (v: Any) -> SceneJSON in sceneJSON(v) })
        case let string as String: return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            return CFNumberIsFloatType(number) ? .double(number.doubleValue) : .number(SceneNumber(number.intValue))
        default: return .null
        }
    }

    private let sceneID = "6F9619FF-8B86-D011-B42D-00C04FC96514"

    /// Photo layer (photo + two slides), the logo, and a text layer.
    private func scene(photo: String, slides: [String], logo: String) throws -> SceneDocument {
        let text = sceneJSON(try JSONSerialization.jsonObject(with: try TextOverlaySpec(message: "Night Drive").encodedForStorage()))
        var photoAsset = SceneAsset.photo(storeID: photo)
        photoAsset.photoSlideshow = SceneSlideshow(enabled: true, storeIDs: slides, mode: "time", seconds: 5, beats: 4)
        let assets: [String: SceneAsset] = [
            "photo1": photoAsset,
            "caption": SceneAsset(.text(spec: text)),
            SceneLogo.assetKey: .logo(storeID: logo, placement: .default),
        ]
        let layers: [SceneLayer] = [SceneLayer(instance: 1, content: .photo(asset: "photo1")),
                                    SceneLayer(instance: 2, content: .text(asset: "caption"))]
        return SceneDocument(id: sceneID, name: "Night Drive", layers: layers, assets: assets)
    }

    /// The source device: three pictures and a logo stored, the scene saved with one cue.
    private func seededScene(in sandbox: Sandbox) throws -> SceneDocument {
        let photo = try store(UITestPhotoFixture.png(alpha: false), in: sandbox)
        let slide1 = try store(UITestPhotoFixture.png(alpha: false, color: (20, 160, 90)), in: sandbox)
        let slide2 = try store(UITestPhotoFixture.png(alpha: false, color: (200, 40, 40)), in: sandbox)
        let logo = try store(UITestPhotoFixture.png(alpha: true), in: sandbox, logo: true)
        let document = try scene(photo: photo.id.uuidString, slides: [slide1.id.uuidString, slide2.id.uuidString], logo: logo.id.uuidString)
        let registry = try SceneArchiveService.appRegistry()
        XCTAssertEqual(document.validate(registry: registry).filter(\.isError), [])
        XCTAssertTrue(sandbox.show().addScene(document, label: "Night Drive"))
        return document
    }

    /// The stored bytes of each media reference, in `mediaReferences` order.
    private func mediaBytes(_ document: SceneDocument, in sandbox: Sandbox) throws -> [Data] {
        try document.mediaReferences.map { (reference: SceneMediaReference) -> Data in
            let id = try XCTUnwrap(UUID(uuidString: reference.storeID))
            return try Data(contentsOf: try XCTUnwrap(sandbox.photos().existingFile(for: id), "\(reference.role) resolves"))
        }
    }

    /// Every string in a JSON document (keys and values).
    private func strings(_ value: Any) -> [String] {
        if let text = value as? String { return [text] }
        if let list = value as? [Any] { return list.flatMap { (v: Any) -> [String] in strings(v) } }
        if let object = value as? [String: Any] { return object.flatMap { (pair: (key: String, value: Any)) -> [String] in [pair.key] + strings(pair.value) } }
        return []
    }

    private func importPack(_ url: URL, into sandbox: Sandbox, show: ShowCoordinator) async throws -> (ScenePackPreview, ShowSceneImportOutcome) {
        let importer = try sandbox.importer()
        let preview = await importer.preview(at: url)
        let adoption = try await importer.adoptMedia(at: url, preview: preview)
        let outcome = show.installImportedScene(try XCTUnwrap(preview.document), plan: try XCTUnwrap(preview.showPlan))
        if case .installed = outcome {} else { importer.release(adoption) }
        return (preview, outcome)
    }

    // MARK: - Acceptance (S1, S2)

    func testReimportOfflineReproducesTheSceneWithoutAbsolutePaths() async throws {
        let device = try makeSandbox()
        let original = try seededScene(in: device)
        let originalBytes = try mediaBytes(original, in: device)
        XCTAssertEqual(originalBytes.count, 4, "photo, two slides, logo")   // opaque pictures are stored as JPEG (MED-001), the logo as PNG

        // 1. Export; the pack leaves the app's temporary folder ("Save to Files").
        let export = try device.archive().export(original)
        let received = device.root.appendingPathComponent("Received/Night Drive.pmscene")
        try FileManager.default.createDirectory(at: received.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: export.url, to: received)
        try device.archive().cleanUpExport()

        // 2. No absolute path anywhere (S1).
        let bytes = try Data(contentsOf: received)
        let contents = try PortableArchive.read(bytes, schema: SceneArchiveFormat.manifestSchema, limits: PortableArchiveLimits(maxFiles: SceneArchiveLimits.maximumFiles, maxFileBytes: 1 << 28, maxManifestBytes: 65_536))
        XCTAssertEqual(contents.records.map { (r: PortableFileRecord) -> String in r.path }.sorted(),
                       ["assets/logo.png", "assets/photo1-slide-01.jpg", "assets/photo1-slide-02.jpg", "assets/photo1.jpg", "scene.json"])
        let texts = strings(try JSONSerialization.jsonObject(with: contents.manifest))
            + strings(try JSONSerialization.jsonObject(with: try XCTUnwrap(contents.files["scene.json"])))
            + contents.records.map { (r: PortableFileRecord) -> String in r.path }
        XCTAssertFalse(texts.isEmpty)
        for text in texts {
            XCTAssertFalse(text.hasPrefix("/") || text.lowercased().hasPrefix("file:") || text.hasPrefix("~"), text)
            for component in ["Containers", "Application Support", "Library/", "/var/", "/private/", "/Users/", "..", device.root.path] {
                XCTAssertFalse(text.contains(component), "\(text) contains \(component)")
            }
        }
        for marker in [device.root.path, "file://", "/var/mobile", "Containers/Data/Application", "Application Support"] {
            XCTAssertNil(bytes.range(of: Data(marker.utf8)), "the pack's bytes contain \(marker)")
        }

        // 3. Wipe the device's media and show (a fresh install), then import offline.
        for folder in [device.photosFolder, device.videosFolder, device.showFolder] { try? FileManager.default.removeItem(at: folder) }
        var spoken: [String] = []
        let show = device.show { (message: String) in spoken.append(message) }
        XCTAssertFalse(show.hasCues)
        let (preview, outcome) = try await importPack(received, into: device, show: show)
        XCTAssertEqual(preview.status, .new)
        XCTAssertEqual([preview.photoCount, preview.slideCount, preview.logoCount, preview.videoCount], [1, 2, 1, 0])
        XCTAssertEqual(preview.licenses, [])
        XCTAssertEqual(preview.repairEntries, [], "nothing to review: every reference resolves after the import")
        guard case let .installed(list, scenes) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(list.cues.map(\.sceneID), [sceneID], "one cue for the scene")
        XCTAssertEqual(show.list.cues.map(\.label), ["Night Drive"])
        XCTAssertNil(device.photos().current(), "nothing becomes the current photo")

        // The stored scene equals the original apart from its media identifiers.
        let stored = try ShowStore(directory: device.showFolder).scene(sceneID).document
        XCTAssertEqual(scenes, [stored])
        let storedRefs = stored.mediaReferences, originalRefs = original.mediaReferences
        XCTAssertEqual(storedRefs.map(\.role), originalRefs.map(\.role))
        XCTAssertTrue(zip(storedRefs, originalRefs).allSatisfy { (pair: (SceneMediaReference, SceneMediaReference)) -> Bool in
            pair.0.storeID != pair.1.storeID
        }, "new identifiers on this install")
        var back = stored
        for (new, old) in zip(storedRefs, originalRefs) {
            back = back.replacingMediaReference(store: new.store, from: new.storeID, to: old.storeID).document
        }
        XCTAssertEqual(back, original, "equal apart from the media identifiers")
        // Every reference resolves to byte-identical media.
        XCTAssertEqual(try mediaBytes(stored, in: device), originalBytes)
        // The scene loads with every picture present and shows the photo visual (the cue's render path).
        let registry = try SceneArchiveService.appRegistry()
        let availability = try device.archive().availability()
        XCTAssertNoThrow(try stored.liveState(registry: registry, assets: availability))
        XCTAssertFalse(stored.validate(registry: registry, assets: availability).contains { (i: SceneIssue) -> Bool in i.code == .missingAsset })
        let apply = ShowSceneSnapshot.apply(of: stored, warnings: [], registry: registry)
        XCTAssertEqual(apply.visual, .photo)
        XCTAssertEqual(apply.slideshow?.value?.storeIDs.count, 2)
        XCTAssertNotNil(apply.logo)

        // Re-import (S3): identical, nothing added, one payload per picture.
        let payloads = device.photos().folder.payloadNames().sorted()
        XCTAssertEqual(payloads.count, 4)
        let again = await (try device.importer()).preview(at: received)
        XCTAssertEqual(again.status, .identical)
        XCTAssertFalse(again.canImport)
        XCTAssertEqual(device.photos().folder.payloadNames().sorted(), payloads)
        XCTAssertEqual(ShowStore(directory: device.showFolder).load().list.cues.count, 1)
    }

    // MARK: - Conflicts and dedup (S3, R10)

    func testImportingNextToTheOriginalAddsACopyAndNoSecondPicture() async throws {
        let device = try makeSandbox()
        let original = try seededScene(in: device)
        let export = try device.archive().export(original)
        defer { try? device.archive().cleanUpExport() }
        let payloads = device.photos().folder.payloadNames().sorted()
        let show = device.show()
        let (preview, outcome) = try await importPack(export.url, into: device, show: show)
        XCTAssertEqual(preview.status, .copy("Night Drive copy"))
        guard case let .installed(list, scenes) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(list.cues.count, 2)
        XCTAssertNotEqual(scenes.first?.id, sceneID, "a new scene ID")
        XCTAssertEqual(try ShowStore(directory: device.showFolder).scene(sceneID).document, original, "the stored scene is unchanged")
        XCTAssertEqual(device.photos().folder.payloadNames().sorted(), payloads, "FILE-008: each picture stored once")
        // A second import of the same pack is identical to the copy: nothing more.
        let again = await (try device.importer()).preview(at: export.url)
        XCTAssertEqual(again.status, .identical)
    }

    // MARK: - Refusals (S4, R7)

    private func assertRefused(_ url: URL, in sandbox: Sandbox, file: StaticString = #filePath, line: UInt = #line) async throws -> String {
        let before = sandbox.snapshot()
        let preview = await (try sandbox.importer()).preview(at: url)
        guard case let .refused(message) = preview.status else {
            XCTFail("accepted: \(preview.status)", file: file, line: line)
            return ""
        }
        XCTAssertFalse(preview.canImport, file: file, line: line)
        do {
            _ = try await (try sandbox.importer()).adoptMedia(at: url, preview: preview)
            XCTFail("adopted", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SceneArchiveServiceError, .planChanged, file: file, line: line)
        }
        XCTAssertEqual(sandbox.snapshot(), before, "nothing written", file: file, line: line)
        return message
    }

    /// A pack built by hand: `files` with checksums, `slides` records as given.
    private func handBuilt(_ files: [(String, Data)], slides: [SceneArchiveSlideRecord], to url: URL) throws {
        var bytes = Data()
        let writer = PortableArchiveWriter(modified: Date(timeIntervalSince1970: 1_794_571_200)) { (chunk: Data) in bytes.append(chunk) }
        var records: [PortableFileRecord] = []
        for (path, data) in files { records.append(try writer.add(path: path, data: data)) }
        let manifest = SceneArchiveManifest(files: records, assets: [SceneArchiveAssetRecord(key: "photo1", type: "photo", path: "assets/photo1.png")],
                                            slides: slides)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try writer.finish(manifest: try encoder.encode(manifest))
        try bytes.write(to: url)
    }

    func testMissingPicturesTraversalAndNonPacksAreRefusedWithNothingWritten() async throws {
        let device = try makeSandbox()
        let png = try XCTUnwrap(UITestPhotoFixture.png(alpha: false))
        let slideIDs = [UUID().uuidString, UUID().uuidString]
        var photoAsset = SceneAsset.photo(storeID: UUID().uuidString)
        photoAsset.photoSlideshow = SceneSlideshow(enabled: true, storeIDs: slideIDs, mode: "time", seconds: 5, beats: 4)
        let document = SceneDocument(id: sceneID, name: "Crafted", layers: [SceneLayer(instance: 1, content: .photo(asset: "photo1"))],
                                     assets: ["photo1": photoAsset])
        let scene = Data(document.encoded())
        let slide1 = SceneArchiveSlideRecord(key: "photo1", index: 1, path: "assets/photo1-slide-01.png")
        let slide2 = SceneArchiveSlideRecord(key: "photo1", index: 2, path: "assets/photo1-slide-02.png")

        // A pack whose manifest lists slide 2 but does not hold its file.
        let missing = device.root.appendingPathComponent("missing.pmscene")
        try handBuilt([("scene.json", scene), ("assets/photo1.png", png), (slide1.path, png)], slides: [slide1, slide2], to: missing)
        let missingMessage = try await assertRefused(missing, in: device)
        XCTAssertTrue(missingMessage.contains("photo1-slide-02.png"), missingMessage)

        // A crafted entry name leaving the folder (FILE-004 / PRE-014 zip-slip guard).
        let control = device.root.appendingPathComponent("control.pmscene")
        try handBuilt([("scene.json", scene), ("assets/photo1.png", png), (slide1.path, png), ("zz/a.png", png)], slides: [slide1], to: control)
        let traversal = device.root.appendingPathComponent("traversal.pmscene")
        var raw = [UInt8](try Data(contentsOf: control))
        let from = Array("zz/a.png".utf8), to = Array("../a.png".utf8)
        var index = 0
        while index + from.count <= raw.count {
            if Array(raw[index..<(index + from.count)]) == from { raw.replaceSubrange(index..<(index + from.count), with: to) }
            index += 1
        }
        try Data(raw).write(to: traversal)
        let traversalMessage = try await assertRefused(traversal, in: device)
        XCTAssertFalse(traversalMessage.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: device.root.deletingLastPathComponent().appendingPathComponent("a.png").path))

        // A file that is not a pack.
        let text = device.root.appendingPathComponent("notes.pmscene")
        try Data("not a scene pack".utf8).write(to: text)
        _ = try await assertRefused(text, in: device)

        // Export refuses a scene whose permitted media are not all stored (R2).
        XCTAssertThrowsError(try device.archive().export(document)) { (error: any Error) in
            XCTAssertEqual(error as? SceneArchiveServiceError, .archive(.missingMedia(key: "photo1")))
        }
    }

    // MARK: - Coordinator (R6, R9)

    private func waitUntilIdle(_ packs: ScenePackCoordinator) async {
        for _ in 0..<1_000 where packs.isBusy { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func testTheCoordinatorExportsImportsAndAnnouncesTheCue() async throws {
        let device = try makeSandbox()
        _ = try seededScene(in: device)
        var spoken: [String] = []
        let show = device.show { (message: String) in spoken.append(message) }
        let packs = ScenePackCoordinator(show: show, importer: try device.importer())
        packs.keepsExportForImport = true
        packs.export(sceneID: sceneID)
        await waitUntilIdle(packs)
        XCTAssertEqual(packs.status, ScenePackCoordinator.exportedMessage("Night Drive"))
        XCTAssertNil(packs.shareURL, "fixture mode: no share sheet")
        XCTAssertNotNil(packs.lastExportCopy)
        packs.startImport()
        await waitUntilIdle(packs)
        let preview = try XCTUnwrap(packs.preview)
        XCTAssertEqual(preview.status, .copy("Night Drive copy"))
        packs.confirmImport()
        await waitUntilIdle(packs)
        XCTAssertNil(packs.preview)
        XCTAssertEqual(show.list.cues.map(\.label), ["Night Drive", "Night Drive copy"])
        XCTAssertEqual(spoken.last, ScenePackCoordinator.importedMessage("Night Drive copy", cue: 2))
        if let copy = packs.lastExportCopy { try? FileManager.default.removeItem(at: copy) }
    }
}
