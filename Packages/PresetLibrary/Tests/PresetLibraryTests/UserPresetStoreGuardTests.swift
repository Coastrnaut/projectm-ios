// PRE-015-T04: every file operation of the user-preset store stays inside its directory
// (PRE-015-R19, S3). An internal observer sees each create, write, move, copy and delete.
import XCTest
@testable import PresetLibrary

final class UserPresetStoreGuardTests: XCTestCase {
    private typealias F = UserPresetFixtures

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(UserPresetStore.FileOperation, URL)] = []
        func add(_ op: UserPresetStore.FileOperation, _ url: URL) { lock.withLock { items.append((op, url)) } }
        var urls: [URL] { lock.withLock { items.map(\.1) } }
        var operations: [UserPresetStore.FileOperation] { lock.withLock { items.map(\.0) } }
    }

    private func record(_ n: Int, state: UserPresetState = .playable) -> UserPreset {
        let bytes = Array("content \(n)".utf8)
        return UserPreset(id: "user/00000000-0000-0000-0000-\(String(format: "%012d", n))", name: "P\(n)", author: "",
                          originalFileName: "P\(n).milk", sha256: ContentHash.sha256Hex(bytes), blobHash: ContentHash.gitBlobSHA1Hex(bytes),
                          byteCount: bytes.count, importedAt: Date(timeIntervalSince1970: 1_800_000_000), state: state,
                          quarantine: state == .quarantined ? PresetQuarantineReason(.missingHeader) : nil,
                          license: PresetLicenseMetadata(authorFromFileName: false, linesFound: []))
    }

    private func assertInside(_ urls: [URL], _ directory: URL, file: StaticString = #filePath, line: UInt = #line) {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertFalse(urls.isEmpty, file: file, line: line)
        for url in urls {
            let path = UserPresetStore.canonicalPath(url)
            XCTAssertTrue(path == root || path.hasPrefix(root + "/"), "\(path) is outside \(root)", file: file, line: line)
        }
    }

    func testEveryOperationOfEveryChangeIsInsideTheDirectory() throws {
        let directory = try F.tempDirectory(self).appendingPathComponent("UserPresets")
        let recorder = Recorder()
        let store = UserPresetStore(directory: directory)
        store.fileOperationObserver = recorder.add
        try store.add(record(1), contents: Data("content 1".utf8))
        try store.add(record(2), contents: Data("content 2".utf8))
        try store.update(record(1).id) { $0.state = .quarantined; $0.quarantine = PresetQuarantineReason(.timedOut) }
        try store.update(record(1).id) { $0.state = .playable; $0.quarantine = nil }
        var replacement = record(3)
        replacement.id = record(2).id
        try store.replaceContents(record(2).id, with: replacement, contents: Data("content 3".utf8))
        try store.writeRecord(.trial, presetID: record(1).id)
        store.clearRecord(.trial)
        try store.writeRecord(.editCheck, presetID: record(1).id, candidateSHA256: String(repeating: "a", count: 64))
        store.clearRecord(.editCheck)
        try store.remove(record(1).id)
        try store.remove(record(2).id)

        let ops = recorder.operations
        XCTAssertTrue(ops.contains(.write) && ops.contains(.move) && ops.contains(.remove) && ops.contains(.createDirectory))
        assertInside(recorder.urls, directory)
    }

    func testTheMigrationsOperationsAreInsideTheDirectory() throws {
        let directory = try F.tempDirectory(self)
        let url = try XCTUnwrap(Bundle.module.url(forResource: "user-presets-v1", withExtension: "json", subdirectory: "Golden"))
        try Data(contentsOf: url).write(to: directory.appendingPathComponent(UserPresetStore.indexFileName))
        let recorder = Recorder()
        let store = UserPresetStore(directory: directory, observer: recorder.add)
        XCTAssertEqual(store.presets.count, 4)
        XCTAssertTrue(recorder.operations.contains(.copy))
        assertInside(recorder.urls, directory)
    }

    func testADirectoryReachedThroughASymbolicLinkWorks() throws {
        let base = try F.tempDirectory(self)
        let real = base.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let store = UserPresetStore(directory: link)
        try store.add(record(1), contents: Data("content 1".utf8))
        XCTAssertEqual(UserPresetStore(directory: link).presets.count, 1)
        try store.remove(record(1).id)
    }

    func testAPathOutsideTheDirectoryIsRefusedAndUntouched() throws {
        let base = try F.tempDirectory(self)
        let directory = base.appendingPathComponent("UserPresets")
        let outside = try F.write("bundled text", named: "Bundled.milk", in: base)
        let store = UserPresetStore(directory: directory)
        let recorder = Recorder()
        store.fileOperationObserver = recorder.add
        for target in [outside, directory.appendingPathComponent("../Bundled.milk"),
                       directory.appendingPathComponent("files/../../Bundled.milk")] {
            XCTAssertThrowsError(try store.removeFile(at: target)) {
                XCTAssertEqual($0 as? UserPresetStore.StoreError, .saveFailed)
            }
            XCTAssertThrowsError(try store.writeFile(Data("x".utf8), to: target))
        }
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "bundled text")
        XCTAssertTrue(recorder.urls.isEmpty, "a refused operation is not performed")
    }
}
