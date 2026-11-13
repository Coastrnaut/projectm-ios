// SceneArchiveTamperImportTests.swift — FILE-002-T06: "Tampered fixture fails validation before import
// modifies library" (FILE-002-R5, S2; contracts/archive-checksums.md C3). A valid archive is exported
// from seeded stores, tampered, and imported into other seeded stores; the service's step observer must
// see no step at all (no stage, adopt or make current) and the stores must be byte-for-byte unchanged.
// The untampered archive is the positive control: `.verified` precedes every store step.
import Foundation
import LocalPortability
import SceneArchive
import SceneFormat
import XCTest
@testable import projectM_iOS

/// Records import steps from any thread.
private final class StepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [SceneArchiveImportStep] = []

    func record(_ step: SceneArchiveImportStep) {
        lock.lock()
        recorded.append(step)
        lock.unlock()
    }

    var steps: [SceneArchiveImportStep] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

@MainActor
final class SceneArchiveTamperImportTests: XCTestCase {
    private struct Sandbox {
        let root: URL
        let defaults: UserDefaults
        let suite: String

        var photosFolder: URL { root.appendingPathComponent("Photos") }
        var videosFolder: URL { root.appendingPathComponent("Videos") }

        func photos() -> PhotoStore { PhotoStore(directory: photosFolder, defaults: defaults) }
        func videos() -> VideoStore { VideoStore(directory: videosFolder, defaults: defaults) }

        func service(_ recorder: StepRecorder? = nil) throws -> SceneArchiveService {
            var observer: (@Sendable (SceneArchiveImportStep) -> Void)?
            if let recorder {
                observer = { (step: SceneArchiveImportStep) -> Void in recorder.record(step) }
            }
            return SceneArchiveService(photos: photos(), videos: videos(), registry: try SceneArchiveService.appRegistry(),
                                       temporaryRoot: root.appendingPathComponent("tmp"), observer: observer)
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

        func stagingLeftovers() -> [String] {
            let folder = root.appendingPathComponent("tmp").appendingPathComponent(SceneArchiveService.stagingFolderName)
            return (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        }
    }

    private let date = Date(timeIntervalSince1970: 1_794_571_200)   // 2026-11-13T12:00:00Z
    private let zipLimits = StoredZipLimits(maxEntries: 8, maxEntryBytes: 100_000_000, maxArchiveBytes: 200_000_000)

    private func makeSandbox(_ name: String) throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SceneArchiveTamperImportTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "SceneArchiveTamperImportTests.\(UUID().uuidString)"
        return Sandbox(root: root, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), suite: suite)
    }

    private func seed(_ sandbox: Sandbox) async throws -> (photo: StoredPhoto, video: StoredVideo) {
        let png = sandbox.root.appendingPathComponent("picked.png")
        try XCTUnwrap(UITestPhotoFixture.png(alpha: false)).write(to: png)
        let movie = sandbox.root.appendingPathComponent("picked.mov")
        try await UITestVideoFixture.writeCounter(to: movie)
        return (try sandbox.photos().importImage(at: png), try await sandbox.videos().importVideo(at: movie))
    }

    /// A camera, photo and video scene exported from seeded source stores: the valid fixture.
    private func validArchive(from source: Sandbox) async throws -> Data {
        let seeded = try await seed(source)
        let scene = SceneDocument(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Tamper", layers: [
            SceneLayer(instance: 1, content: .camera),
            SceneLayer(instance: 2, content: .photo(asset: "photo1")),
            SceneLayer(instance: 3, content: .video(asset: "video1")),
        ], assets: ["photo1": .photo(storeID: seeded.photo.id.uuidString), "video1": .video(storeID: seeded.video.id.uuidString)])
        let service = try source.service()
        let export = try service.export(scene, modified: date)
        defer { service.cleanUpExport() }
        return try Data(contentsOf: export.url)
    }

    private func entries(_ archive: Data) throws -> [StoredZipEntry] { try StoredZipReader.read(archive, limits: zipLimits) }

    /// Rewrites entries (every CRC-32 correct), changing one entry's bytes and/or the manifest's records.
    private func rezip(_ archive: Data, path: String? = nil, bytes: (Data) -> Data = { (d: Data) -> Data in d },
                       rename: [String: String] = [:], record: ((inout [[String: Any]]) -> Void)? = nil) throws -> Data {
        var out = Data()
        let zip = StoredZipWriter(modified: date) { (chunk: Data) in out.append(chunk) }
        for entry in try entries(archive) {
            var data = entry.data
            if entry.path == path { data = bytes(data) }
            if entry.path == PortableArchive.manifestPath, let record {
                var manifest = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                var files = try XCTUnwrap(manifest["files"] as? [[String: Any]])
                record(&files)
                manifest["files"] = files
                data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .withoutEscapingSlashes])
            }
            try zip.add(path: rename[entry.path] ?? entry.path, data: data)
        }
        try zip.finish()
        return out
    }

    private static func flipMiddle(_ data: Data) -> Data {
        var copy = data
        copy[copy.startIndex + copy.count / 2] ^= 0x01
        return copy
    }

    private static func set(_ files: inout [[String: Any]], _ path: String, _ key: String, _ value: Any) {
        for index in files.indices where files[index]["path"] as? String == path { files[index][key] = value }
    }

    /// The offset of entry `index`'s stored bytes (little-endian ZIP headers).
    private static func dataStart(_ d: Data, entry index: Int) -> Int {
        func u16(_ at: Int) -> Int { Int(d[d.startIndex + at]) | Int(d[d.startIndex + at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        let end = d.count - 22
        var at = u32(end + 16)
        for _ in 0..<index { at += 46 + u16(at + 28) + u16(at + 30) + u16(at + 32) }
        let local = u32(at + 42)
        return local + 30 + u16(local + 26) + u16(local + 28)
    }

    func testTamperedArchivesRunNoStoreStepAndLeaveTheLibraryUnchanged() async throws {
        let source = try makeSandbox("source"), target = try makeSandbox("target")
        defer { source.cleanUp(); target.cleanUp() }
        let good = try await validArchive(from: source)
        _ = try await seed(target)
        let before = target.snapshot()
        let names = try entries(good).map(\.path)
        XCTAssertEqual(names, ["scene.json", "assets/photo1.jpg", "assets/video1.mov", "manifest.json"])

        var videoInPlace = good
        videoInPlace[videoInPlace.startIndex + Self.dataStart(good, entry: 2) + 100] ^= 0x01
        let cases: [(name: String, archive: Data, expected: SceneArchiveServiceError)] = [
            ("video byte changed, CRC stale", videoInPlace, .archive(.archive(.zip(.checksumMismatch("assets/video1.mov"))))),
            ("video byte changed, CRC repaired", try rezip(good, path: "assets/video1.mov", bytes: Self.flipMiddle),
             .archive(.archive(.checksumMismatch("assets/video1.mov")))),
            ("photo size field changed", try rezip(good, record: { (f: inout [[String: Any]]) in Self.set(&f, "assets/photo1.jpg", "byteCount", 1) }),
             .archive(.archive(.lengthMismatch("assets/photo1.jpg")))),
            ("scene checksum changed", try rezip(good, record: { (f: inout [[String: Any]]) in
                Self.set(&f, "scene.json", "sha256", String(repeating: "a", count: 64))
            }), .archive(.archive(.checksumMismatch("scene.json")))),
            ("video renamed", try rezip(good, rename: ["assets/video1.mov": "assets/video2.mov"]),
             .archive(.archive(.missingFile("assets/video1.mov")))),
            ("malformed video digest", try rezip(good, record: { (f: inout [[String: Any]]) in Self.set(&f, "assets/video1.mov", "sha256", "abc") }),
             .archive(.archive(.invalidRecord("assets/video1.mov")))),
        ]
        for (index, testCase) in cases.enumerated() {
            let file = target.root.appendingPathComponent("tampered-\(index).pmscene")
            try testCase.archive.write(to: file)
            let recorder = StepRecorder()
            let service = try target.service(recorder)
            do {
                _ = try await service.importArchive(at: file)
                XCTFail("\(testCase.name): imported")
            } catch {
                XCTAssertEqual(error, testCase.expected, testCase.name)
                XCTAssertTrue(error.message.contains("assets/") || error.message.contains("scene.json"), "\(testCase.name): \(error.message)")
            }
            XCTAssertEqual(recorder.steps, [], "\(testCase.name): no verify, stage, adopt or make-current step ran")
            XCTAssertEqual(target.snapshot(), before, "\(testCase.name): files and identifiers byte-for-byte unchanged")
            XCTAssertEqual(target.stagingLeftovers(), [], testCase.name)
        }
    }

    func testAValidImportIsVerifiedBeforeAnyStoreStep() async throws {
        let source = try makeSandbox("source"), target = try makeSandbox("target")
        defer { source.cleanUp(); target.cleanUp() }
        let good = try await validArchive(from: source)
        let file = target.root.appendingPathComponent("valid.pmscene")
        try good.write(to: file)
        let recorder = StepRecorder()
        let result = try await target.service(recorder).importArchive(at: file)
        XCTAssertNotNil(result.photo)
        XCTAssertNotNil(result.video)
        XCTAssertEqual(recorder.steps, [.verified, .staged("assets/photo1.jpg"), .staged("assets/video1.mov"),
                                        .adopted(.photo), .adopted(.video), .madeCurrent(.photo), .madeCurrent(.video)])
    }
}
