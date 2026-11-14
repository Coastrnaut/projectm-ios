// SceneArchiveImportPlanTests.swift — FILE-003-T16: the scene archive dry run (FILE-003-R12, S7;
// contract C5). The plan describes the import (media, replaced photo, SCN-012 entries after the
// import, empty licences, size, steps) or its typed refusal, and leaves both stores' folders and
// their UserDefaults keys byte-for-byte unchanged; the plan-checked import runs exactly the plan's
// steps and refuses a changed store. Photo-only scenes keep each test about a second.
import Foundation
import LocalPortability
import PresetLibrary
import SceneArchive
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class SceneArchiveImportPlanTests: XCTestCase {
    private struct Sandbox {
        let root: URL
        let defaults: UserDefaults
        let suite: String

        var photosFolder: URL { root.appendingPathComponent("Photos") }
        var videosFolder: URL { root.appendingPathComponent("Videos") }
        var temporary: URL { root.appendingPathComponent("tmp") }

        func photos() -> PhotoStore { PhotoStore(directory: photosFolder, defaults: defaults) }
        func videos() -> VideoStore { VideoStore(directory: videosFolder, defaults: defaults) }

        func service(limits: SceneArchiveLimits = .standard,
                     observer: (@Sendable (SceneArchiveImportStep) -> Void)? = nil) throws -> SceneArchiveService {
            SceneArchiveService(photos: photos(), videos: videos(), registry: try SceneArchiveService.appRegistry(),
                                temporaryRoot: temporary, limits: limits, observer: observer)
        }

        /// The library the scene import owns: both store folders (byte-for-byte) and both keys.
        struct State: Equatable {
            let tree: LibraryTreeSnapshot
            let photoID: String?
            let videoID: String?
        }

        func state() -> State {
            State(tree: LibraryTreeSnapshot.take([photosFolder, videosFolder]),
                  photoID: defaults.string(forKey: PhotoStore.idKey), videoID: defaults.string(forKey: VideoStore.idKey))
        }

        func stagingLeftovers() -> [String] {
            (try? FileManager.default.contentsOfDirectory(atPath: temporary.appendingPathComponent(SceneArchiveService.stagingFolderName).path)) ?? []
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private final class Steps: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [SceneArchiveImportStep] = []
        func append(_ step: SceneArchiveImportStep) { lock.withLock { list.append(step) } }
        var all: [SceneArchiveImportStep] { lock.withLock { list } }
    }

    private func makeSandbox(_ name: String) throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SceneArchiveImportPlanTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "SceneArchiveImportPlanTests.\(UUID().uuidString)"
        let sandbox = Sandbox(root: root, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), suite: suite)
        addTeardownBlock { sandbox.cleanUp() }
        return sandbox
    }

    @discardableResult
    private func seedPhoto(_ sandbox: Sandbox, alpha: Bool = false) throws -> StoredPhoto {
        let png = sandbox.root.appendingPathComponent("picked-\(alpha).png")
        try XCTUnwrap(UITestPhotoFixture.png(alpha: alpha)).write(to: png)
        return try sandbox.photos().importImage(at: png)
    }

    private func photoScene(_ photoID: String) -> SceneDocument {
        SceneDocument(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Harbor",
                      layers: [SceneLayer(instance: 1, content: .camera), SceneLayer(instance: 2, content: .photo(asset: "photo1"))],
                      assets: ["photo1": .photo(storeID: photoID)])
    }

    /// A photo scene exported from its own sandbox, copied out to a picked file.
    private func photoArchive() throws -> URL { try photoArchiveWithFile().url }

    /// The picked archive and the stored photo file it carries (the store keeps its own encoding).
    private func photoArchiveWithFile() throws -> (url: URL, photoFile: URL) {
        let source = try makeSandbox("source")
        let photo = try seedPhoto(source)
        let photoFile = try XCTUnwrap(source.photos().existingFile(for: photo.id))
        let export = try source.service().export(photoScene(photo.id.uuidString), modified: Date(timeIntervalSince1970: 1_794_571_200))
        let picked = source.root.deletingLastPathComponent().appendingPathComponent("picked-\(UUID().uuidString).pmscene")
        try FileManager.default.copyItem(at: export.url, to: picked)
        addTeardownBlock { try? FileManager.default.removeItem(at: picked) }
        return (picked, photoFile)
    }

    // MARK: - Plan, Cancel, install

    func testPlanDescribesTheImportAndLeavesTheStoresUnchanged() async throws {
        let (picked, photoFile) = try photoArchiveWithFile()
        let path = "assets/photo1." + photoFile.pathExtension
        let target = try makeSandbox("target")
        try seedPhoto(target, alpha: true)   // the photo the import would replace
        let before = target.state()

        let plan = try await target.service().planImport(at: picked)
        XCTAssertNil(plan.refusal)
        XCTAssertEqual(plan.archiveSHA256, PortableSHA256.hex(try Data(contentsOf: picked)))
        XCTAssertEqual(plan.sceneName, "Harbor")
        XCTAssertEqual(plan.media.map(\.type), [.photo])
        XCTAssertEqual(plan.media.map(\.path), [path])
        XCTAssertEqual(plan.totalBytes, try Data(contentsOf: photoFile).count)
        XCTAssertTrue(plan.replacesPhoto)
        XCTAssertFalse(plan.replacesVideo)
        XCTAssertEqual(plan.licenses, [], "scenes carry no licence data")
        XCTAssertEqual(plan.repairEntries, [], "every reference resolves after the import")
        XCTAssertEqual(plan.steps, [.verified, .staged(path), .adopted(.photo), .madeCurrent(.photo)])

        // Cancel: the plan is dropped. The stores, the keys and the staging folder are unchanged.
        XCTAssertEqual(target.state(), before)
        XCTAssertEqual(target.stagingLeftovers(), [])
    }

    func testThePlanCheckedImportRunsExactlyThePlannedSteps() async throws {
        let picked = try photoArchive()
        let target = try makeSandbox("install")
        let plan = try await target.service().planImport(at: picked)
        XCTAssertFalse(plan.replacesPhoto, "empty stores: nothing replaced")
        let steps = Steps()
        let result = try await target.service(observer: { (step: SceneArchiveImportStep) in steps.append(step) })
            .importArchive(at: picked, plan: plan)
        XCTAssertEqual(steps.all, plan.steps)
        XCTAssertEqual(result.document.name, "Harbor")
        XCTAssertEqual(result.repairReport.entries, plan.repairEntries)
        XCTAssertNotNil(target.photos().current())
    }

    func testAStoreChangedAfterThePlanIsRefusedWithNothingImported() async throws {
        let picked = try photoArchive()
        let target = try makeSandbox("changed")
        let plan = try await target.service().planImport(at: picked)
        try seedPhoto(target, alpha: true)   // meanwhile a photo is picked
        let before = target.state()
        let service = try target.service()
        do throws(SceneArchiveServiceError) {
            _ = try await service.importArchive(at: picked, plan: plan)
            XCTFail("a changed store must be refused")
        } catch {
            XCTAssertEqual(error, .planChanged)
        }
        XCTAssertEqual(target.state(), before)
        XCTAssertEqual(target.stagingLeftovers(), [])
    }

    // MARK: - Refusals (tampered, newer scene version, oversize)

    func testRefusedArchivesArePlannedAsRefusalsWithoutTouchingTheStores() async throws {
        let picked = try photoArchive()
        let target = try makeSandbox("refusals")
        try seedPhoto(target)
        let before = target.state()
        let service = try target.service()

        // Tampered: one byte of the photo's data flipped (FILE-002's checksum refusal).
        var bytes = [UInt8](try Data(contentsOf: picked))
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF], png: [UInt8] = [0x89, 0x50, 0x4E]
        let start = try XCTUnwrap((0..<(bytes.count - 3)).first { (i: Int) -> Bool in
            let window = Array(bytes[i..<(i + 3)])
            return window == jpeg || window == png
        })
        bytes[start + 40] ^= 0xFF
        let tampered = target.root.appendingPathComponent("tampered.pmscene")
        try Data(bytes).write(to: tampered)
        let tamperedPlan = await service.planImport(at: tampered)
        guard case .archive = tamperedPlan.refusal else { return XCTFail("tampered: \(String(describing: tamperedPlan.refusal))") }
        XCTAssertEqual(tamperedPlan.steps, [])

        // A newer scene version (SCN-013 refuses it).
        let newer = target.root.appendingPathComponent("newer.pmscene")
        try newerVersionArchive().write(to: newer)
        let newerPlan = await service.planImport(at: newer)
        XCTAssertEqual(newerPlan.refusal, .archive(.sceneRefused(.newerVersion(Int64(SceneDocument.currentVersion + 1)))))

        // Oversize: larger than the archive limit.
        let small = SceneArchiveLimits(maxArchiveBytes: 1_000, maxManifestBytes: 65_536, maxPhotoBytes: 1_000, maxVideoBytes: 1_000)
        let oversizePlan = try await target.service(limits: small).planImport(at: picked)
        XCTAssertEqual(oversizePlan.refusal, .archive(.archiveTooLarge(limit: 1_000)))

        // A refused plan is refused again by the plan-checked import.
        do throws(SceneArchiveServiceError) {
            _ = try await service.importArchive(at: newer, plan: newerPlan)
            XCTFail("a refused plan must not import")
        } catch {
            XCTAssertEqual(error, newerPlan.refusal)
        }
        XCTAssertEqual(target.state(), before)
        XCTAssertEqual(target.stagingLeftovers(), [])
    }

    /// A camera-only scene whose `version` is one above the newest this app reads.
    private func newerVersionArchive() throws -> Data {
        let plain = SceneDocument(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Future", layers: [SceneLayer(instance: 1, content: .camera)])
        let current = "\"version\":\(SceneDocument.currentVersion)"
        let text = String(decoding: plain.encoded(), as: UTF8.self)
        XCTAssertTrue(text.contains(current))
        let scene = Data(text.replacingOccurrences(of: current, with: "\"version\":\(SceneDocument.currentVersion + 1)").utf8)
        var out = Data()
        let zip = StoredZipWriter(modified: Date(timeIntervalSince1970: 1_794_571_200)) { (chunk: Data) in out.append(chunk) }
        try zip.add(path: SceneArchiveFormat.scenePath, data: scene)
        let manifest: [String: Any] = [
            "format": SceneArchiveFormat.formatName, "formatVersion": SceneArchiveFormat.currentVersion,
            "files": [["path": SceneArchiveFormat.scenePath, "sha256": PortableSHA256.hex(scene), "byteCount": scene.count]],
            "scene": SceneArchiveFormat.scenePath, "assets": [[String: Any]](),
        ]
        try zip.add(path: "manifest.json", data: try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]))
        try zip.finish()
        return out
    }
}
