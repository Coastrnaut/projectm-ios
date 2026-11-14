// ContentAddressedMediaFolderTests.swift — FILE-008-T03 (FILE-008-S1-S3; contract M1-M11). Each test
// uses its own temporary folder; files are a few bytes, so every test runs in milliseconds.
import Foundation
import XCTest
@testable import LocalPortability

final class ContentAddressedMediaFolderTests: XCTestCase {
    private struct Abort: Error {}

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CAMF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var folderURL: URL { root.appendingPathComponent("Photos", isDirectory: true) }

    private func folder(fault: (@Sendable (ContentAddressedMediaFolder.Step, URL) throws -> Void)? = nil) -> ContentAddressedMediaFolder {
        ContentAddressedMediaFolder(directory: folderURL, extensions: ["png", "jpg"], fault: fault)
    }

    /// A source file outside the folder.
    private func source(_ bytes: [UInt8], ext: String = "png") throws -> URL {
        let url = root.appendingPathComponent("src-\(UUID().uuidString).\(ext)")
        try Data(bytes).write(to: url)
        return url
    }

    private func names() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folderURL.path)) ?? []).sorted()
    }

    private func payloadCount() -> Int { folder().payloadNames().count }

    // MARK: - Acceptance (S1, S2)

    func testTwoIdenticalInternsGiveOnePayloadAndTwoReferences() throws {
        let store = folder()
        let a = UUID(), b = UUID()
        let first = try store.intern(try source([1, 2, 3]), as: a, consumingSource: true)
        let second = try store.intern(try source([1, 2, 3]), as: b, consumingSource: true)
        XCTAssertEqual(first, second)
        XCTAssertEqual(payloadCount(), 1, "one physical payload")
        XCTAssertEqual(Set(store.references()), [a, b], "two references")
        XCTAssertEqual(store.resolve(a), first)
        XCTAssertEqual(store.resolve(b), first)
        XCTAssertTrue(store.sharesPayload(a, b))
        XCTAssertEqual(names(), [first.lastPathComponent, ContentAddressedMediaFolder.registryName])
        XCTAssertEqual(first.lastPathComponent, PortableSHA256.hex([1, 2, 3]) + ".png", "named by the SHA-256 of its bytes")
    }

    func testReleasingOneReferenceKeepsThePayloadAndBothDeleteIt() throws {
        let store = folder()
        let a = UUID(), b = UUID()
        try store.intern(try source([9, 9]), as: a, consumingSource: true)
        try store.intern(try source([9, 9]), as: b, consumingSource: true)
        try store.release([a])
        XCTAssertEqual(payloadCount(), 1)
        XCTAssertNil(store.resolve(a))
        XCTAssertNotNil(store.resolve(b))
        try store.release([b])
        XCTAssertEqual(payloadCount(), 0)
        XCTAssertEqual(store.references(), [])
    }

    func testDifferentContentGivesTwoPayloadsAndReleaseSharingLeavesTheOther() throws {
        let store = folder()
        let a = UUID(), b = UUID(), c = UUID()
        try store.intern(try source([1]), as: a, consumingSource: true)
        try store.intern(try source([1]), as: b, consumingSource: true)
        try store.intern(try source([2]), as: c, consumingSource: true)
        XCTAssertEqual(payloadCount(), 2)
        try store.releaseSharing(payloadOf: a)
        XCTAssertEqual(store.references(), [c])
        XCTAssertEqual(payloadCount(), 1)
    }

    func testCopyingInternKeepsTheSourceAndSameSizeDifferentBytesAreDistinct() throws {
        let store = folder()
        let src = try source([5, 6])
        try store.intern(src, as: UUID(), consumingSource: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
        try store.intern(try source([6, 5]), as: UUID(), consumingSource: true)
        XCTAssertEqual(payloadCount(), 2, "equal size alone is not identity")
    }

    func testTrimKeepsAtMostTheLimitAndNeverTheKeptOne() throws {
        let store = folder()
        let ids = (0..<5).map { (_: Int) -> UUID in UUID() }
        for id in ids { try store.intern(try source([7]), as: id, consumingSource: true) }
        try store.trim(payloadOf: ids[4], keeping: [ids[0]], limit: 3)
        XCTAssertEqual(store.references(), [ids[0], ids[3], ids[4]], "the oldest non-kept ones go")
        XCTAssertEqual(payloadCount(), 1)
    }

    func testUnsupportedExtensionIsRefused() throws {
        XCTAssertThrowsError(try folder().intern(try source([1], ext: "gif"), as: UUID(), consumingSource: true))
        XCTAssertEqual(payloadCount(), 0)
    }

    func testConcurrentInternsOfOneContentGiveOnePayload() throws {
        let store = folder()
        let sources = try (0..<8).map { (_: Int) -> URL in try source([4, 4, 4]) }
        DispatchQueue.concurrentPerform(iterations: sources.count) { (i: Int) in
            _ = try? store.intern(sources[i], as: UUID(), consumingSource: true)
        }
        XCTAssertEqual(payloadCount(), 1)
        XCTAssertEqual(store.references().count, 8)
    }

    // MARK: - Usage (M9) and logical files (M10)

    func testUsageCountsLogicalAndPhysicalBytes() throws {
        let store = folder()
        try store.intern(try source([1, 2, 3, 4]), as: UUID(), consumingSource: true)
        try store.intern(try source([1, 2, 3, 4]), as: UUID(), consumingSource: true)
        try store.intern(try source([8, 8]), as: UUID(), consumingSource: true)
        XCTAssertEqual(store.usage(), MediaFolderUsage(references: 3, payloads: 2, logicalBytes: 10, physicalBytes: 6))
        XCTAssertEqual(store.usage().savedBytes, 4)
    }

    func testLogicalFilesNameEveryReferenceByItsIdentifier() throws {
        let store = folder()
        let a = UUID(), b = UUID()
        try store.intern(try source([3, 3], ext: "jpg"), as: a, consumingSource: true)
        try store.intern(try source([3, 3], ext: "jpg"), as: b, consumingSource: true)
        let files = store.logicalFiles()
        XCTAssertEqual(Set(files.keys), ["\(a.uuidString).jpg", "\(b.uuidString).jpg"])
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(files["\(a.uuidString).jpg"])), Data([3, 3]))
    }

    // MARK: - Migration (M7, M8; S3)

    /// Two legacy copies of one picture and one of another, as MED-001 and a FILE-005 restore leave them.
    private func writeLegacy() throws -> [UUID: Data] {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let contents: [Data] = [Data([1, 1, 1]), Data([1, 1, 1]), Data([2, 2])]
        var written: [UUID: Data] = [:]
        for bytes in contents {
            let id = UUID()
            try bytes.write(to: folderURL.appendingPathComponent("\(id.uuidString).png"))
            written[id] = bytes
        }
        return written
    }

    private func assertResolves(_ expected: [UUID: Data], _ store: ContentAddressedMediaFolder, _ context: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        for (id, bytes) in expected {
            guard let url = store.resolve(id) else {
                XCTFail("\(id) does not resolve (\(context))", file: file, line: line)
                continue
            }
            XCTAssertEqual(try? Data(contentsOf: url), bytes, context, file: file, line: line)
        }
    }

    func testMigrationRegistersLegacyFilesAndTheNextPrepareRemovesTheirNames() throws {
        let legacy = try writeLegacy()
        let store = folder()
        let report = try store.reconcile()
        XCTAssertEqual(report.migrated, 3)
        assertResolves(legacy, store, "after reconcile")
        XCTAssertEqual(payloadCount(), 2)
        store.prepare()   // the next launch
        assertResolves(legacy, store, "after prepare")
        XCTAssertEqual(names().filter { (n: String) -> Bool in store.legacyID(n) != nil }, [], "legacy names removed")
        XCTAssertEqual(store.usage().payloads, 2)
        XCTAssertEqual(store.usage().references, 3)
        XCTAssertEqual(try store.reconcile(), ContentAddressedMediaFolder.ReconcileReport(), "idempotent")
    }

    func testMigrationSurvivesAFaultAtEveryStep() throws {
        // Abort at the n-th step (whatever it is), then run the launch sequence again; repeat for every n.
        var step = 0
        while step < 40 {
            try? FileManager.default.removeItem(at: folderURL)
            let legacy = try writeLegacy()
            let counter = StepCounter(abortAt: step)
            let faulty = folder(fault: { (_: ContentAddressedMediaFolder.Step, _: URL) throws in try counter.tick() })
            faulty.prepare()
            _ = try? faulty.reconcile()
            faulty.prepare()
            assertResolves(legacy, folder(), "right after a fault at step \(step)")
            let clean = folder()
            clean.prepare()
            _ = try clean.reconcile()
            clean.prepare()
            assertResolves(legacy, clean, "after recovery from step \(step)")
            XCTAssertEqual(payloadCount(), 2, "step \(step)")
            XCTAssertEqual(names().count, 3, "two payloads and the registry, nothing stray (step \(step))")
            if !counter.fired { break }
            step += 1
        }
        XCTAssertGreaterThan(step, 3, "several steps were injected")
    }

    func testInternFaultsLeaveNoReferenceAndLaunchCleansUp() throws {
        for target in ContentAddressedMediaFolder.Step.allCases {
            try? FileManager.default.removeItem(at: folderURL)
            let keep = UUID()
            try folder().intern(try source([1, 2]), as: keep, consumingSource: true)
            let faulty = folder(fault: { (step: ContentAddressedMediaFolder.Step, _: URL) throws in if step == target { throw Abort() } })
            let id = UUID()
            let temp = faulty.incomingURL(for: id, extension: "png")
            try Data([3, 4]).write(to: temp)
            _ = try? faulty.intern(temp, as: id, consumingSource: true)
            let clean = folder()
            clean.prepare()
            _ = try clean.reconcile()
            XCTAssertNotNil(clean.resolve(keep), "\(target)")
            if clean.resolve(id) == nil {
                XCTAssertEqual(payloadCount(), 1, "an aborted import leaves no payload (\(target))")
            }
            XCTAssertFalse(names().contains { (n: String) -> Bool in n.hasPrefix(ContentAddressedMediaFolder.incomingPrefix) })
        }
    }

    func testALegacyFileWinsOverItsRegistryEntry() throws {
        let store = folder()
        let id = UUID()
        try store.intern(try source([1, 1]), as: id, consumingSource: true)
        // A restore wrote a newer copy under the same identifier.
        try Data([2, 2, 2]).write(to: folderURL.appendingPathComponent("\(id.uuidString).png"))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(store.resolve(id))), Data([2, 2, 2]))
        try store.reconcile()
        store.prepare()
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(store.resolve(id))), Data([2, 2, 2]))
        XCTAssertEqual(payloadCount(), 1, "the older payload had no reference left")
    }

    // MARK: - Hostile registry

    func testDamagedOrForeignRegistryReadsAsNoReferences() throws {
        let store = folder()
        let id = UUID()
        try store.intern(try source([1]), as: id, consumingSource: true)
        let registry = folderURL.appendingPathComponent(ContentAddressedMediaFolder.registryName)
        try Data("{not json".utf8).write(to: registry)
        XCTAssertNil(store.resolve(id))
        let escaping = #"{"format":"org.projectmios.media-references","version":1,"references":[{"id":"\#(id.uuidString)","payload":"../x.png"},{"id":"nope","payload":"\#(String(repeating: "a", count: 64)).png"}]}"#
        try Data(escaping.utf8).write(to: registry)
        XCTAssertEqual(store.references(), [], "a path outside the folder or a bad identifier is never used")
        try store.reconcile()
        XCTAssertEqual(payloadCount(), 0, "unreferenced payloads are collected")
    }

    // MARK: - Hash

    func testStreamingHashMatchesTheOneShotHash() throws {
        var bytes: [UInt8] = []
        for i in 0..<(MediaContentHash.chunkSize + 77) { bytes.append(UInt8(truncatingIfNeeded: i &* 31)) }
        let url = try source(bytes)
        let digest = try MediaContentHash.digest(ofFileAt: url)
        XCTAssertEqual(digest.sha256, PortableSHA256.hex(bytes))
        XCTAssertEqual(digest.byteCount, Int64(bytes.count))
    }
}

/// Counts fault-hook calls and aborts at one of them.
private final class StepCounter: @unchecked Sendable {
    private let lock = NSLock()
    private let abortAt: Int
    private var count = 0
    private(set) var fired = false

    init(abortAt: Int) { self.abortAt = abortAt }

    func tick() throws {
        lock.lock()
        defer { lock.unlock() }
        let current = count
        count += 1
        if current == abortAt {
            fired = true
            throw CancellationError()
        }
    }
}
