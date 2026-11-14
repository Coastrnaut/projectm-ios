// MediaDeduplicationTests.swift — FILE-008-T09, T11: the roadmap acceptance "Two identical imports
// create one physical payload and two references" for the photo and the video, reference release,
// scene availability and loop restore through older references, and the launch migration of legacy
// copies with a fault at every step (FILE-008-S1-S3). Each test has its own folder and UserDefaults
// suite; the pictures are the DEBUG fixtures (64 × 48 PNG, 2 s 64 × 48 movie).
import Foundation
import LocalPortability
import SceneFormat
import VideoLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class MediaDeduplicationTests: XCTestCase {
    private struct Sandbox {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        var photosFolder: URL { root.appendingPathComponent("Photos", isDirectory: true) }
        var videosFolder: URL { root.appendingPathComponent("Videos", isDirectory: true) }

        func photos(fault: (@Sendable (ContentAddressedMediaFolder.Step, URL) throws -> Void)? = nil) -> PhotoStore {
            PhotoStore(directory: photosFolder, defaults: defaults, fault: fault)
        }

        func videos(fault: (@Sendable (ContentAddressedMediaFolder.Step, URL) throws -> Void)? = nil) -> VideoStore {
            VideoStore(directory: videosFolder, defaults: defaults, fault: fault)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func makeSandbox() throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaDedupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "MediaDedupTests.\(UUID().uuidString)"
        return Sandbox(root: root, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), suite: suite)
    }

    /// A picked PNG (`alpha` gives a different picture).
    private func pickedPhoto(_ sandbox: Sandbox, alpha: Bool = false) throws -> URL {
        let url = sandbox.root.appendingPathComponent("picked-\(UUID().uuidString).png")
        try XCTUnwrap(UITestPhotoFixture.png(alpha: alpha)).write(to: url)
        return url
    }

    private func pickedMovie(_ sandbox: Sandbox, frames: Int = 60) async throws -> URL {
        let url = sandbox.root.appendingPathComponent("picked-\(UUID().uuidString).mov")
        try await UITestVideoFixture.writeCounter(to: url, frames: frames)
        return url
    }

    /// Payload files physically in the folder (the acceptance counts these).
    private func payloadFiles(_ folder: URL, _ ext: Set<String>) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { (name: String) -> Bool in
            let parts = name.split(separator: ".")
            return parts.count == 2 && ext.contains(String(parts[1])) && MediaContentHash.isSHA256Hex(String(parts[0]))
        }.sorted()
    }

    private func allFiles(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    // MARK: - Acceptance (FILE-008-S1)

    func testTwoIdenticalPhotoImportsCreateOnePayloadAndTwoReferences() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let first = try sandbox.photos().importImage(at: try pickedPhoto(sandbox))
        let second = try sandbox.photos().importImage(at: try pickedPhoto(sandbox))
        XCTAssertNotEqual(first.id, second.id, "two references (store identifiers)")
        XCTAssertEqual(payloadFiles(sandbox.photosFolder, ["png", "jpg"]).count, 1, "one physical payload")
        XCTAssertEqual(allFiles(sandbox.photosFolder).count, 2, "the payload and the registry, nothing else")
        XCTAssertEqual(Set(sandbox.photos().knownIDs()), [first.id, second.id])
        XCTAssertEqual(sandbox.photos().current(), second)
        XCTAssertEqual(sandbox.photos().existingFile(for: first.id), second.url, "the first reference resolves to the same payload")
        // FILE-008-R5: a scene or cue naming the first identifier finds its photo.
        let coordinator = PhotoCoordinator(store: sandbox.photos(), announce: { (_: String) in })
        let availability = StoredMediaAvailability(photos: coordinator.knownIDs, videos: [])
        XCTAssertTrue(availability.containsPhoto(storeID: first.id.uuidString))
        XCTAssertTrue(availability.containsPhoto(storeID: second.id.uuidString))
    }

    func testTwoIdenticalVideoImportsCreateOnePayloadAndTwoReferences() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let first = try await sandbox.videos().importVideo(at: try await pickedMovie(sandbox))
        let second = try await sandbox.videos().importVideo(at: try await pickedMovie(sandbox))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(payloadFiles(sandbox.videosFolder, ["mov"]).count, 1, "one physical payload")
        XCTAssertEqual(Set(sandbox.videos().knownIDs()), [first.id, second.id], "two references")
        XCTAssertEqual(first.url, second.url)
        XCTAssertTrue(sandbox.videos().isSameVideo(first.id, as: second.id))
        XCTAssertFalse(allFiles(sandbox.videosFolder).contains { (n: String) -> Bool in n.hasPrefix(ContentAddressedMediaFolder.incomingPrefix) })
    }

    // MARK: - Release (FILE-008-S2)

    func testReleasingOneReferenceKeepsThePayloadAndRemoveDeletesIt() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let first = try sandbox.photos().importImage(at: try pickedPhoto(sandbox))
        let second = try sandbox.photos().importImage(at: try pickedPhoto(sandbox))
        sandbox.photos().discard(first)   // first is no longer current
        XCTAssertEqual(payloadFiles(sandbox.photosFolder, ["png", "jpg"]).count, 1, "the payload stays")
        XCTAssertNil(sandbox.photos().existingFile(for: first.id))
        XCTAssertEqual(sandbox.photos().current(), second)
        sandbox.photos().discard(second)
        XCTAssertNotNil(sandbox.photos().current(), "the current photo is never discarded")
        sandbox.photos().remove()
        XCTAssertEqual(payloadFiles(sandbox.photosFolder, ["png", "jpg"]), [], "the last reference took the payload")
        XCTAssertNil(sandbox.photos().current())
    }

    func testADifferentPhotoReleasesEveryReferenceToTheOldOne() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let first = try sandbox.photos().importImage(at: try pickedPhoto(sandbox))
        let second = try sandbox.photos().importImage(at: try pickedPhoto(sandbox))
        let other = try sandbox.photos().importImage(at: try pickedPhoto(sandbox, alpha: true))
        XCTAssertEqual(payloadFiles(sandbox.photosFolder, ["png", "jpg"]), [other.url.lastPathComponent])
        XCTAssertNil(sandbox.photos().existingFile(for: first.id))
        XCTAssertNil(sandbox.photos().existingFile(for: second.id))
        XCTAssertEqual(sandbox.photos().knownIDs(), [other.id])
    }

    func testRemoveVideoReleasesEveryReferenceAndTheLoop() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        _ = try await sandbox.videos().importVideo(at: try await pickedMovie(sandbox))
        let second = try await sandbox.videos().importVideo(at: try await pickedMovie(sandbox))
        sandbox.videos().setLoopRegion(VideoLoopRegion(inMilliseconds: 100, outMilliseconds: 900), for: second.id)
        sandbox.videos().remove()
        XCTAssertEqual(payloadFiles(sandbox.videosFolder, ["mov"]), [])
        XCTAssertEqual(sandbox.videos().knownIDs(), [])
        XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.loopKey))
    }

    // MARK: - Loop restore through an older reference (FILE-008-R5, MED-003-R8)

    func testACueNamingAnOlderReferenceOfTheCurrentVideoRestoresItsLoop() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let first = try await sandbox.videos().importVideo(at: try await pickedMovie(sandbox))
        _ = try await sandbox.videos().importVideo(at: try await pickedMovie(sandbox))
        let coordinator = VideoCoordinator(store: sandbox.videos(), announce: { (_: String) in })
        let loop = SceneVideoLoopBridge.scene(VideoLoopRegion(inMilliseconds: 200, outMilliseconds: 1_200))
        coordinator.restoreLoop(storeID: first.id.uuidString, loop: loop)
        XCTAssertEqual(coordinator.loopRegion, VideoLoopRegion(inMilliseconds: 200, outMilliseconds: 1_200))
        coordinator.restoreLoop(storeID: UUID().uuidString, loop: nil)
        XCTAssertEqual(coordinator.loopRegion, VideoLoopRegion(inMilliseconds: 200, outMilliseconds: 1_200), "a foreign identifier changes nothing")
    }

    // MARK: - Migration (FILE-008-S3)

    /// Legacy copies as MED-001/002 stored them, with the current keys set.
    private func writeLegacy(_ sandbox: Sandbox) async throws -> (photo: (UUID, Data), video: (UUID, Data)) {
        try FileManager.default.createDirectory(at: sandbox.photosFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sandbox.videosFolder, withIntermediateDirectories: true)
        let photoID = UUID(), videoID = UUID()
        let photoBytes = try XCTUnwrap(UITestPhotoFixture.png(alpha: false))
        try photoBytes.write(to: sandbox.photosFolder.appendingPathComponent("\(photoID.uuidString).png"))
        let movie = try await pickedMovie(sandbox)
        try FileManager.default.copyItem(at: movie, to: sandbox.videosFolder.appendingPathComponent("\(videoID.uuidString).mov"))
        sandbox.defaults.set(photoID.uuidString, forKey: PhotoStore.idKey)
        sandbox.defaults.set(videoID.uuidString, forKey: VideoStore.idKey)
        return ((photoID, photoBytes), (videoID, try Data(contentsOf: movie)))
    }

    private func assertCurrent(_ sandbox: Sandbox, _ legacy: (photo: (UUID, Data), video: (UUID, Data)), _ context: String) {
        let photo = sandbox.photos().current()
        XCTAssertEqual(photo?.id, legacy.photo.0, context)
        XCTAssertEqual(photo.flatMap { (p: StoredPhoto) -> Data? in try? Data(contentsOf: p.url) }, legacy.photo.1, context)
        let video = sandbox.videos().current()
        XCTAssertEqual(video?.id, legacy.video.0, context)
        XCTAssertEqual(video.flatMap { (v: StoredVideo) -> Data? in try? Data(contentsOf: v.url) }, legacy.video.1, context)
    }

    func testLegacyCopiesMigrateAndResolveBeforeDuringAndAfter() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let legacy = try await writeLegacy(sandbox)
        assertCurrent(sandbox, legacy, "before")
        // An interrupted launch pass: abort at the n-th step of the photo and the video folder.
        for step in 0..<6 {
            let photoFault = AbortAt(step), videoFault = AbortAt(step)
            sandbox.photos(fault: { (_: ContentAddressedMediaFolder.Step, _: URL) throws in try photoFault.tick() }).reconcileFolder()
            sandbox.videos(fault: { (_: ContentAddressedMediaFolder.Step, _: URL) throws in try videoFault.tick() }).reconcileFolder()
            assertCurrent(sandbox, legacy, "after a fault at step \(step)")
        }
        // The next launches: prepare, reconcile, then prepare again.
        for store in [sandbox.photos().folder, sandbox.videos().folder] {
            store.prepare()
            _ = try store.reconcile()
        }
        assertCurrent(sandbox, legacy, "after reconcile")
        sandbox.photos().prepareFolder()
        sandbox.videos().prepareFolder()
        assertCurrent(sandbox, legacy, "after the next launch's prepare")
        XCTAssertEqual(allFiles(sandbox.photosFolder).count, 2, "one payload and the registry; the legacy name is gone")
        XCTAssertEqual(allFiles(sandbox.videosFolder).count, 2)
        XCTAssertEqual(payloadFiles(sandbox.videosFolder, ["mov"]).count, 1)
    }
}

/// Throws at the n-th fault-hook call.
private final class AbortAt: @unchecked Sendable {
    private let lock = NSLock()
    private let target: Int
    private var count = 0

    init(_ target: Int) { self.target = target }

    func tick() throws {
        lock.lock()
        defer { lock.unlock() }
        let current = count
        count += 1
        if current == target { throw CancellationError() }
    }
}
