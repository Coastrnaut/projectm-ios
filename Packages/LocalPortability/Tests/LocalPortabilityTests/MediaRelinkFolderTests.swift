// MediaRelinkFolderTests.swift — MED-013-T04 (contract L1, L2; MED-013-S4): the registry's released list,
// relink by checksum (re-intern, adoption, restore from a file, forget) and the bounded folder scan. Each
// test uses its own temporary folder with files of a few bytes.
import Foundation
import XCTest
@testable import LocalPortability

final class MediaRelinkFolderTests: XCTestCase {
    private struct Abort: Error {}

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MRF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var folderURL: URL { root.appendingPathComponent("Photos", isDirectory: true) }

    private func folder(fault: (@Sendable (ContentAddressedMediaFolder.Step, URL) throws -> Void)? = nil) -> ContentAddressedMediaFolder {
        ContentAddressedMediaFolder(directory: folderURL, extensions: ["png", "jpg"], fault: fault)
    }

    private func source(_ bytes: [UInt8], ext: String = "png", in directory: URL? = nil, name: String? = nil) throws -> URL {
        let base = directory ?? root!
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent(name ?? "src-\(UUID().uuidString).\(ext)")
        try Data(bytes).write(to: url)
        return url
    }

    private func sha(_ bytes: [UInt8]) throws -> String {
        try MediaContentHash.digest(ofFileAt: try source(bytes)).sha256
    }

    // MARK: - Released list (MED-013-R3)

    func testReleaseRemembersThePayloadNameAndInternForgetsIt() throws {
        let store = folder()
        let p = UUID()
        let payload = try store.intern(try source([1, 2, 3]), as: p, consumingSource: true)
        try store.release([p])
        XCTAssertNil(store.resolve(p))
        XCTAssertFalse(FileManager.default.fileExists(atPath: payload.path), "the payload went with its last reference")
        XCTAssertEqual(store.knownPayloadName(of: p), payload.lastPathComponent, "the released list keeps the name")
        XCTAssertEqual(store.releasedIDs(), [p])
        XCTAssertTrue(store.references().isEmpty, "a released entry is not a reference")
        _ = try store.intern(try source([9]), as: p, consumingSource: true)
        XCTAssertTrue(store.releasedIDs().isEmpty, "interning the identifier again removes it from the released list")
    }

    func testReleasedListIsBoundedOldestDropped() throws {
        let store = folder()
        var ids: [UUID] = []
        for n in 0..<(ContentAddressedMediaFolder.maxReleasedEntries + 3) {
            let id = UUID()
            ids.append(id)
            _ = try store.intern(try source([UInt8(n & 0xFF), UInt8(n >> 8)]), as: id, consumingSource: true)
        }
        try store.release(Set(ids))
        XCTAssertEqual(store.releasedIDs().count, ContentAddressedMediaFolder.maxReleasedEntries)
        let released = store.releasedIDs()
        XCTAssertEqual(store.registry().references.count, 0)
        XCTAssertEqual(Set(released).count, released.count, "no duplicates")
    }

    func testAnOlderRegistryWithoutTheKeyReadsAndAReaderIgnoringItStillWorks() throws {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let id = UUID()
        let name = String(repeating: "a", count: 64) + ".png"
        let json = #"{"format":"org.projectmios.media-references","references":[{"id":"\#(id.uuidString)","payload":"\#(name)"}],"version":1}"#
        try Data(json.utf8).write(to: folderURL.appendingPathComponent(ContentAddressedMediaFolder.registryName))
        XCTAssertEqual(folder().knownPayloadName(of: id), name)
        XCTAssertTrue(folder().releasedIDs().isEmpty)
    }

    // MARK: - Relink by checksum (MED-013-R4)

    func testReInterningTheSameBytesResolvesADeletedPayloadWithNoOtherChange() throws {
        let store = folder()
        let p = UUID()
        let payload = try store.intern(try source([4, 5, 6]), as: p, consumingSource: true)
        try FileManager.default.removeItem(at: payload)   // the file is lost; the entry stays
        XCTAssertNil(store.resolve(p))
        let q = UUID()
        _ = try store.intern(try source([4, 5, 6]), as: q, consumingSource: true)
        XCTAssertEqual(store.resolve(p), payload, "content addressing alone brings it back")
    }

    func testAdoptKnownRegistersAReleasedIdentifierWhosePayloadExistsAgain() throws {
        let store = folder()
        let p = UUID(), other = UUID()
        _ = try store.intern(try source([7, 7]), as: p, consumingSource: true)
        try store.release([p])
        XCTAssertTrue(try store.adoptKnown([p]).isEmpty, "nothing to adopt while the payload is gone")
        _ = try store.intern(try source([7, 7]), as: other, consumingSource: true)
        XCTAssertEqual(try store.adoptKnown([p, UUID()]), [p])
        XCTAssertNotNil(store.resolve(p))
        XCTAssertTrue(store.sharesPayload(p, other))
        XCTAssertTrue(store.releasedIDs().isEmpty)
        XCTAssertTrue(try store.adoptKnown([p]).isEmpty, "idempotent")
    }

    func testRestorePayloadCopiesAVerifiedMatchAndNeverTouchesTheSource() throws {
        let store = folder()
        let p = UUID(), unrelated = UUID()
        _ = try store.intern(try source([1, 1, 2]), as: p, consumingSource: true)
        _ = try store.intern(try source([3, 3]), as: unrelated, consumingSource: true)
        try store.release([p])
        let backup = try source([1, 1, 2], ext: "png", in: root.appendingPathComponent("Backup"))
        let wrong = try source([8, 8, 8], ext: "png", in: root.appendingPathComponent("Backup"))
        XCTAssertTrue(try store.restorePayload(from: wrong, missing: [p]).isEmpty, "other bytes are ignored")
        XCTAssertEqual(try store.restorePayload(from: backup, missing: [p]), [p])
        XCTAssertNotNil(store.resolve(p))
        XCTAssertEqual(try Data(contentsOf: backup), Data([1, 1, 2]), "the source is unchanged")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertFalse(store.payloadNames().isEmpty)
        XCTAssertFalse((try FileManager.default.contentsOfDirectory(atPath: folderURL.path)).contains { (n: String) -> Bool in n.hasPrefix(ContentAddressedMediaFolder.incomingPrefix) })
    }

    func testRestorePayloadFailureLeavesNothingBehind() throws {
        let store = folder(fault: { (step: ContentAddressedMediaFolder.Step, _: URL) throws in if step == .placePayload { throw Abort() } })
        let p = UUID()
        _ = try folder().intern(try source([5, 6]), as: p, consumingSource: true)
        try folder().release([p])
        let backup = try source([5, 6])
        XCTAssertThrowsError(try store.restorePayload(from: backup, missing: [p]))
        XCTAssertNil(store.resolve(p))
        XCTAssertTrue(store.payloadNames().isEmpty)
        XCTAssertEqual(store.releasedIDs(), [p], "the hint stays for another try")
    }

    func testForgetDropsReleasedIdentifiers() throws {
        let store = folder()
        let a = UUID(), b = UUID()
        _ = try store.intern(try source([1]), as: a, consumingSource: true)
        _ = try store.intern(try source([2]), as: b, consumingSource: true)
        try store.release([a, b])
        try store.forget([a])
        XCTAssertEqual(store.releasedIDs(), [b])
        XCTAssertNil(store.knownPayloadName(of: a))
    }

    // MARK: - Folder scan (MED-013-R5, S4)

    private var limits: MediaFolderScanLimits { MediaFolderScanLimits(maxFileBytes: 1 << 20) }

    func testScanFindsAMatchInASubfolderAndIgnoresEverythingElse() throws {
        let picked = root.appendingPathComponent("Picked", isDirectory: true)
        _ = try source([1, 2, 3, 4], in: picked.appendingPathComponent("photos"), name: "A.png")
        _ = try source([9, 9], in: picked, name: "other.png")
        _ = try source([1, 2, 3, 4], in: picked, name: "notes.txt")   // same bytes, not a media extension
        _ = try source([1, 2, 3, 4], in: picked, name: ".hidden.png")
        let want = try sha([1, 2, 3, 4])
        let result = MediaFolderScan.scan(root: picked, wanted: [want], extensions: ["png", "jpg"], limits: limits)
        XCTAssertEqual(result.matches[want]?.lastPathComponent, "A.png")
        XCTAssertEqual(result.matches.count, 1)
        XCTAssertFalse(result.limitReached)
        XCTAssertLessThanOrEqual(result.hashed, 2, "only media files are hashed")
    }

    func testScanDoesNotFollowSymbolicLinks() throws {
        let picked = root.appendingPathComponent("Picked", isDirectory: true)
        let outside = try source([5, 5, 5], in: root.appendingPathComponent("Outside"), name: "x.png")
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: picked.appendingPathComponent("link.png"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: picked.appendingPathComponent("dir"), withDestinationURL: outside.deletingLastPathComponent())
        let result = MediaFolderScan.scan(root: picked, wanted: [try sha([5, 5, 5])], extensions: ["png"], limits: limits)
        XCTAssertTrue(result.matches.isEmpty)
        XCTAssertEqual(result.hashed, 0)
    }

    func testScanStopsAtEachBoundAndSaysSo() throws {
        let picked = root.appendingPathComponent("Picked", isDirectory: true)
        for n in 0..<6 { _ = try source([UInt8(n)], in: picked, name: "f\(n).png") }
        let deep = picked.appendingPathComponent("z/b/c", isDirectory: true)   // depth 4, walked after f0-f5
        _ = try source([42], in: deep, name: "deep.png")
        let want = try sha([42])
        let entries = MediaFolderScan.scan(root: picked, wanted: [want], extensions: ["png"],
                                           limits: MediaFolderScanLimits(maxEntries: 3, maxFileBytes: 1 << 20))
        XCTAssertTrue(entries.limitReached)
        XCTAssertEqual(entries.visited, 3)
        let files = MediaFolderScan.scan(root: picked, wanted: [want], extensions: ["png"],
                                         limits: MediaFolderScanLimits(maxHashedFiles: 2, maxFileBytes: 1 << 20))
        XCTAssertTrue(files.limitReached)
        XCTAssertEqual(files.hashed, 2)
        let size = MediaFolderScan.scan(root: picked, wanted: [want], extensions: ["png"],
                                        limits: MediaFolderScanLimits(maxFileBytes: 0))
        XCTAssertTrue(size.limitReached)
        XCTAssertEqual(size.hashed, 0)
        let total = MediaFolderScan.scan(root: picked, wanted: [want], extensions: ["png"],
                                         limits: MediaFolderScanLimits(maxFileBytes: 1 << 20, maxTotalBytes: 3))
        XCTAssertTrue(total.limitReached)
        XCTAssertEqual(total.hashed, 3)
        let shallow = MediaFolderScan.scan(root: picked, wanted: [want], extensions: ["png"],
                                           limits: MediaFolderScanLimits(maxDepth: 2, maxFileBytes: 1 << 20))
        XCTAssertTrue(shallow.matches.isEmpty, "depth 4 is beyond a bound of 2")
        XCTAssertTrue(shallow.limitReached)
        let full = MediaFolderScan.scan(root: picked, wanted: [want], extensions: ["png"], limits: limits)
        XCTAssertNotNil(full.matches[want], "within the standard bounds it is found")
        XCTAssertFalse(full.limitReached)
    }

    func testScanStopsOnceEveryWantedHashIsFound() throws {
        let picked = root.appendingPathComponent("Picked", isDirectory: true)
        _ = try source([1], in: picked, name: "a.png")
        for n in 2..<8 { _ = try source([UInt8(n)], in: picked, name: "z\(n).png") }
        let result = MediaFolderScan.scan(root: picked, wanted: [try sha([1])], extensions: ["png"], limits: limits)
        XCTAssertEqual(result.hashed, 1)
    }
}
