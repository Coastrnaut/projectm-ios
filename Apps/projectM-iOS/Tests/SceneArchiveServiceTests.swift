// SceneArchiveServiceTests.swift — FILE-001-T12, T14: the scene archive service with real stores
// (FILE-001-R4, R5, R10 to R12, R15; S1, S2, S3). "Clean install" = new, empty stores in another
// temporary folder with their own UserDefaults suite; nothing uses the network. The photo is the
// DEBUG fixture PNG and the video the DEBUG fixture writer's 2 s movie, each imported through the
// stores first, as a user's would be.
import AVFoundation
import Foundation
import GeneratorGraph
import ImageIO
import LocalPortability
import ParameterGraph
import SceneArchive
import SceneFormat
import TextLayer
import VideoLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class SceneArchiveServiceTests: XCTestCase {
    private struct Sandbox {
        let root: URL
        let defaults: UserDefaults
        let suite: String

        var photosFolder: URL { root.appendingPathComponent("Photos") }
        var videosFolder: URL { root.appendingPathComponent("Videos") }
        var temporary: URL { root.appendingPathComponent("tmp") }

        func photos() -> PhotoStore { PhotoStore(directory: photosFolder, defaults: defaults) }
        func videos(limits: VideoImportLimits = .standard) -> VideoStore { VideoStore(directory: videosFolder, defaults: defaults, limits: limits) }

        func service(videoLimits: VideoImportLimits = .standard) throws -> SceneArchiveService {
            SceneArchiveService(photos: photos(), videos: videos(limits: videoLimits), registry: try SceneArchiveService.appRegistry(),
                                temporaryRoot: temporary)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }

        /// Every file (name and bytes) in both stores and both identifiers.
        func snapshot() -> [String: Data] {
            var result: [String: Data] = [:]
            for folder in [photosFolder, videosFolder] {
                for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
                    result[folder.lastPathComponent + "/" + name] = try? Data(contentsOf: folder.appendingPathComponent(name))
                }
            }
            result["id.photo"] = Data((defaults.string(forKey: PhotoStore.idKey) ?? "").utf8)
            result["id.video"] = Data((defaults.string(forKey: VideoStore.idKey) ?? "").utf8)
            return result
        }

        /// Files left in the import staging folder.
        func stagingLeftovers() -> [String] {
            (try? FileManager.default.contentsOfDirectory(atPath: temporary.appendingPathComponent(SceneArchiveService.stagingFolderName).path)) ?? []
        }
    }

    private func makeSandbox(_ name: String) throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SceneArchiveServiceTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "SceneArchiveServiceTests.\(UUID().uuidString)"
        return Sandbox(root: root, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), suite: suite)
    }

    /// Imports the fixture photo and movie into a sandbox's stores, as picked files.
    private func seed(_ sandbox: Sandbox) async throws -> (photo: StoredPhoto, video: StoredVideo) {
        let png = sandbox.root.appendingPathComponent("picked.png")
        try XCTUnwrap(UITestPhotoFixture.png(alpha: false)).write(to: png)
        let movie = sandbox.root.appendingPathComponent("picked.mov")
        try await UITestVideoFixture.writeCounter(to: movie)
        let photo = try sandbox.photos().importImage(at: png)
        let video = try await sandbox.videos().importVideo(at: movie)
        return (photo, video)
    }

    /// Foundation JSON → SceneJSON (for the embedded text and graph documents).
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

    private func json(_ data: Data) throws -> SceneJSON { sceneJSON(try JSONSerialization.jsonObject(with: data)) }

    /// Camera, photo, video, text and generator graph layers (FILE-001-S1 fixture).
    private func scene(photoID: String, videoID: String) throws -> SceneDocument {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let graph = try encoder.encode(GeneratorGraphExamples.emberDrift)
        let assets: [String: SceneAsset] = [
            "photo1": .photo(storeID: photoID),
            "video1": .video(storeID: videoID),
            "caption": SceneAsset(.text(spec: try json(try TextOverlaySpec(message: "Night Drive").encodedForStorage()))),
            "graph1": SceneAsset(.generatorGraph(document: try json(graph))),
        ]
        let layers: [SceneLayer] = [
            SceneLayer(instance: 1, content: .camera),
            SceneLayer(instance: 2, content: .photo(asset: "photo1"), composite: SceneComposite(opacity: 0.5)),
            SceneLayer(instance: 3, content: .video(asset: "video1")),
            SceneLayer(instance: 4, content: .text(asset: "caption")),
            SceneLayer(instance: 5, content: .generatorGraph(asset: "graph1")),
        ]
        return SceneDocument(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Night Drive", layers: layers, assets: assets)
    }

    private let date = Date(timeIntervalSince1970: 1_794_571_200)   // 2026-11-13T12:00:00Z

    // MARK: - Clean-install round trip (T12; S1)

    func testRoundTripIntoEmptyStoresResolvesEveryAssetOffline() async throws {
        let source = try makeSandbox("source"), target = try makeSandbox("target")
        defer { source.cleanUp(); target.cleanUp() }
        let seeded = try await seed(source)
        let original = try scene(photoID: seeded.photo.id.uuidString, videoID: seeded.video.id.uuidString)
        let registry = try SceneArchiveService.appRegistry()
        XCTAssertTrue(original.validate(registry: registry).filter(\.isError).isEmpty, "\(original.validate(registry: registry))")

        let export = try source.service().export(original, modified: date)
        XCTAssertEqual(export.fileName, SceneArchiveService.exportFileName(for: date))
        XCTAssertTrue(export.fileName.hasPrefix("projectM-iOS Scene 2026-11-1") && export.fileName.hasSuffix(".pmscene"))
        // The archive leaves the source: copy it to the target sandbox ("AirDrop") and remove the export.
        let received = target.root.appendingPathComponent("received.pmscene")
        try FileManager.default.copyItem(at: export.url, to: received)
        try source.service().cleanUpExport()
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.url.path), "the temporary export is removed")

        XCTAssertNil(target.photos().current())
        XCTAssertNil(target.videos().current())
        let result = try await target.service().importArchive(at: received)

        let photo = try XCTUnwrap(result.photo), video = try XCTUnwrap(result.video)
        XCTAssertEqual(target.photos().current(), photo)
        XCTAssertEqual(target.videos().current(), video)
        XCTAssertFalse(result.replacedPhoto)
        XCTAssertFalse(result.replacedVideo)
        XCTAssertNotEqual(photo.id, seeded.photo.id, "a new store identifier on this device")
        XCTAssertEqual(result.document, original.remappingStoreIDs(["photo1": photo.id.uuidString, "video1": video.id.uuidString]),
                       "equal to the original except the remapped store IDs")
        let issues = result.document.validate(registry: registry, assets: try target.service().availability())
        XCTAssertTrue(issues.allSatisfy { (i: SceneIssue) -> Bool in !i.isError && i.code != .missingAsset }, "\(issues)")
        XCTAssertNoThrow(try result.document.liveState(registry: registry, assets: try target.service().availability()))

        // The media decode.
        let source0 = try XCTUnwrap(CGImageSourceCreateWithURL(photo.url as CFURL, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source0, 0, nil))
        let tracks = try await AVURLAsset(url: video.url).loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        // One copy each, nothing staged left behind.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.photosFolder.path), [photo.url.lastPathComponent])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.videosFolder.path), [video.url.lastPathComponent])
        XCTAssertEqual(target.stagingLeftovers(), [])
    }

    func testExportRefusesAPhotoThatIsNotOnTheDevice() async throws {
        let source = try makeSandbox("missing")
        defer { source.cleanUp() }
        let seeded = try await seed(source)
        let document = try scene(photoID: UUID().uuidString, videoID: seeded.video.id.uuidString)
        XCTAssertThrowsError(try source.service().export(document, modified: date)) { (error: Error) in
            XCTAssertEqual(error as? SceneArchiveServiceError, .archive(.missingMedia(key: "photo1")))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: try source.service().exportFolder.path), "no export file is left")
    }

    // MARK: - All or nothing (T14; S2, S3)

    func testAHostileArchiveLeavesTheStoresUnchanged() async throws {
        let target = try makeSandbox("hostile")
        defer { target.cleanUp() }
        _ = try await seed(target)
        let before = target.snapshot()
        let original = try scene(photoID: UUID().uuidString, videoID: UUID().uuidString)
        // A Mach-O program in place of the video, listed with correct checksums.
        let png = try XCTUnwrap(UITestPhotoFixture.png(alpha: false))
        let machO = Data([0xCF, 0xFA, 0xED, 0xFE] + [UInt8](repeating: 0, count: 60))
        var bytes = Data()
        let writer = PortableArchiveWriter(modified: date) { (chunk: Data) in bytes.append(chunk) }
        let files = [try writer.add(path: "scene.json", data: Data(original.encoded())),
                     try writer.add(path: "assets/photo1.png", data: png),
                     try writer.add(path: "assets/video1.mov", data: machO)]
        let manifest = SceneArchiveManifest(files: files, assets: [
            SceneArchiveAssetRecord(key: "photo1", type: "photo", path: "assets/photo1.png"),
            SceneArchiveAssetRecord(key: "video1", type: "video", path: "assets/video1.mov"),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try writer.finish(manifest: try encoder.encode(manifest))
        let file = target.root.appendingPathComponent("hostile.pmscene")
        try bytes.write(to: file)

        let service = try target.service()
        do {
            _ = try await service.importArchive(at: file)
            XCTFail("imported")
        } catch {
            XCTAssertEqual(error, .archive(.executableContent(path: "assets/video1.mov", kind: .machO)))
        }
        XCTAssertEqual(target.snapshot(), before, "files and identifiers byte-for-byte unchanged")
        XCTAssertEqual(target.stagingLeftovers(), [])
    }

    func testAFailureOnTheLastAssetLeavesTheStoresUnchanged() async throws {
        let source = try makeSandbox("source"), target = try makeSandbox("target")
        defer { source.cleanUp(); target.cleanUp() }
        let seeded = try await seed(source)
        _ = try await seed(target)
        let before = target.snapshot()
        let export = try source.service().export(try scene(photoID: seeded.photo.id.uuidString, videoID: seeded.video.id.uuidString), modified: date)
        defer { try? source.service().cleanUpExport() }
        // The photo ("photo1") is staged first; the video ("video1", last) exceeds this store's limit.
        let tiny = VideoImportLimits(maxFileBytes: 16, maxLongestSide: 4_096, maxFrameRate: 60.5)
        let service = try target.service(videoLimits: tiny)
        do {
            _ = try await service.importArchive(at: export.url)
            XCTFail("imported")
        } catch {
            XCTAssertEqual(error, .media(path: "assets/video1.mov", message: VideoImportError.tooLarge.message))
        }
        XCTAssertEqual(target.snapshot(), before, "the staged photo never reached the store")
        XCTAssertEqual(target.stagingLeftovers(), [])
    }

    func testASuccessfulImportReplacesTheStoredPhotoAndVideo() async throws {
        let source = try makeSandbox("source"), target = try makeSandbox("target")
        defer { source.cleanUp(); target.cleanUp() }
        let seeded = try await seed(source)
        let previous = try await seed(target)
        let export = try source.service().export(try scene(photoID: seeded.photo.id.uuidString, videoID: seeded.video.id.uuidString), modified: date)
        defer { try? source.service().cleanUpExport() }
        let result = try await target.service().importArchive(at: export.url)
        XCTAssertTrue(result.replacedPhoto)
        XCTAssertTrue(result.replacedVideo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: previous.photo.url.path), "the previous copies are deleted after the switch")
        XCTAssertFalse(FileManager.default.fileExists(atPath: previous.video.url.path))
        XCTAssertEqual(target.photos().current(), result.photo)
        XCTAssertEqual(target.videos().current(), result.video)
    }
}
