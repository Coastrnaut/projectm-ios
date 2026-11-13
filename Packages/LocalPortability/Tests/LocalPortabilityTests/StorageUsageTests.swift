// FILE-009 storage usage: the acceptance ("Totals agree with fixture directory sizes within
// file-system overhead") on a real fixture tree (Darwin file systems report allocation), and the walk's
// rules with an injected tree on every platform (FILE-009-S1-S3).
import Foundation
import XCTest
@testable import LocalPortability

/// An in-memory tree keyed by absolute path.
private struct FakeTree: StorageDirectoryReading {
    enum Node { case file(Int64, Int64), directory, link, unreadable }
    var nodes: [String: Node]
    /// Root paths that resolve elsewhere (a link in the path itself).
    var resolutions: [String: String] = [:]

    struct Unreadable: Error {}

    func kind(atPath path: String) -> StorageEntry.Kind? {
        switch nodes[path] {
        case nil: nil
        case .file: .file
        case .directory, .unreadable: .directory
        case .link: .symbolicLink
        }
    }

    func entries(inDirectory path: String) throws -> [StorageEntry] {
        if case .unreadable = nodes[path] { throw Unreadable() }
        let prefix = path + "/"
        var result: [StorageEntry] = []
        for (key, node) in nodes where key.hasPrefix(prefix) {
            let name = String(key.dropFirst(prefix.count))
            if name.contains("/") { continue }
            switch node {
            case let .file(content, used): result.append(StorageEntry(name: name, kind: .file, contentBytes: content, spaceUsed: used))
            case .directory, .unreadable: result.append(StorageEntry(name: name, kind: .directory))
            case .link: result.append(StorageEntry(name: name, kind: .symbolicLink))
            }
        }
        return result.sorted { (a: StorageEntry, b: StorageEntry) -> Bool in a.name < b.name }
    }

    func resolvedPath(_ path: String) -> String { resolutions[path] ?? path }
}

/// Every folder holds `filesPerFolder` files of 10 bytes and one sub-folder `d`, without end.
private struct EndlessTree: StorageDirectoryReading {
    var filesPerFolder: Int

    func kind(atPath path: String) -> StorageEntry.Kind? { .directory }

    func entries(inDirectory path: String) throws -> [StorageEntry] {
        var result: [StorageEntry] = (0..<filesPerFolder).map { (i: Int) -> StorageEntry in
            StorageEntry(name: "f\(i)", kind: .file, contentBytes: 10, spaceUsed: 4096)
        }
        result.append(StorageEntry(name: "d", kind: .directory))
        return result
    }

    func resolvedPath(_ path: String) -> String { path }
}

#if canImport(Darwin)
/// Records every folder the walk lists (real file system; Darwin only, like the tests that use it).
private final class RecordingReader: StorageDirectoryReading, @unchecked Sendable {
    let base = FileManagerStorageReader()
    private let lock = NSLock()
    private var listedPaths: [String] = []

    var listed: [String] { lock.withLock { listedPaths } }

    func kind(atPath path: String) -> StorageEntry.Kind? { base.kind(atPath: path) }

    func entries(inDirectory path: String) throws -> [StorageEntry] {
        lock.withLock { listedPaths.append(path) }
        return try base.entries(inDirectory: path)
    }

    func resolvedPath(_ path: String) -> String { base.resolvedPath(path) }
}
#endif

final class StorageUsageTests: XCTestCase {
    // MARK: Injected tree (every platform)

    private func sampleTree() -> FakeTree {
        FakeTree(nodes: [
            "/c": .directory,
            "/c/Photos": .directory,
            "/c/Photos/a.png": .file(1_000, 4_096),
            "/c/Photos/sub": .directory,
            "/c/Photos/sub/b.png": .file(5_000, 8_192),
            "/c/Photos/out": .link,
            "/c/tmp": .directory,
            "/c/tmp/Recordings": .directory,
            "/c/tmp/Recordings/r.mov": .file(70_000, 73_728),
            "/c/tmp/stray.txt": .file(3, 4_096),
            "/c/Library": .directory,
            "/c/Library/Caches": .directory,
            "/c/Library/Caches/x": .file(100, 4_096),
            "/c/Library/Preferences": .directory,
            "/c/Library/Preferences/p.plist": .file(900, 4_096),
            "/c/Empty": .directory,
        ])
    }

    func testEachFileIsCountedInExactlyItsCategoryAndTheTotalIsTheSum() throws {
        let request = StorageRequest(container: "/c", roots: [
            .photos: ["/c/Photos"], .recordings: ["/c/tmp/Recordings"], .caches: ["/c/Library/Caches"],
            .videos: ["/c/Library/Application Support/Videos"],  // missing: zero
        ])
        let report = try StorageUsageCalculator(reader: sampleTree()).measure(request)
        XCTAssertEqual(report.usage(.photos), StorageUsage(contentBytes: 6_000, spaceUsed: 12_288, fileCount: 2))
        XCTAssertEqual(report.usage(.recordings), StorageUsage(contentBytes: 70_000, spaceUsed: 73_728, fileCount: 1))
        XCTAssertEqual(report.usage(.caches), StorageUsage(contentBytes: 100, spaceUsed: 4_096, fileCount: 1))
        XCTAssertEqual(report.usage(.videos), StorageUsage())
        // Other app data: the container without the category folders (stray.txt and p.plist).
        XCTAssertEqual(report.usage(.otherAppData), StorageUsage(contentBytes: 903, spaceUsed: 8_192, fileCount: 2))
        XCTAssertEqual(report.total, StorageUsage(contentBytes: 77_003, spaceUsed: 98_304, fileCount: 6))
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.skippedRoots, [])
    }

    func testRootsThatAreLinksOrOutsideTheContainerAreSkipped() throws {
        var tree = sampleTree()
        tree.nodes["/c/LinkedScenes"] = .link
        tree.nodes["/elsewhere"] = .directory
        tree.nodes["/elsewhere/big"] = .file(9_000_000, 9_000_000)
        tree.nodes["/c/Sneaky"] = .directory
        tree.resolutions["/c/Sneaky"] = "/elsewhere"       // a link inside the root's own path
        tree.resolutions["/c/../elsewhere"] = "/elsewhere"
        let request = StorageRequest(container: "/c", roots: [
            .scenes: ["/c/LinkedScenes"], .caches: ["/elsewhere"], .presets: ["/c/Sneaky", "/c/../elsewhere"],
            .videos: ["/c"],  // the container itself is not a category folder
        ])
        let report = try StorageUsageCalculator(reader: tree).measure(request)
        XCTAssertEqual(report.skippedRoots, ["/c", "/c/LinkedScenes", "/c/Sneaky", "/c/../elsewhere", "/elsewhere"].sorted { (a: String, b: String) -> Bool in
            StorageUsageTests.order(a) < StorageUsageTests.order(b)
        })
        for category in [StorageCategory.scenes, .caches, .presets, .videos] {
            XCTAssertEqual(report.usage(category), StorageUsage(), "\(category)")
        }
        XCTAssertLessThan(report.total.contentBytes, 9_000_000, "nothing outside the container is counted")
    }

    /// The order `measure` vets roots in: category order, then the order given.
    private static func order(_ root: String) -> Int {
        ["/c", "/c/LinkedScenes", "/c/Sneaky", "/c/../elsewhere", "/elsewhere"].firstIndex(of: root) ?? 99
    }

    func testDepthLimitStopsTheWalkAndMarksTheReportIncomplete() throws {
        let tree = FakeTree(nodes: [
            "/c": .directory, "/c/P": .directory,
            "/c/P/f": .file(1, 1),
            "/c/P/a": .directory, "/c/P/a/f": .file(10, 10),
            "/c/P/a/b": .directory, "/c/P/a/b/f": .file(100, 100),
            "/c/P/a/b/c": .directory, "/c/P/a/b/c/f": .file(1_000, 1_000),
        ])
        let request = StorageRequest(container: "/c", roots: [.photos: ["/c/P"]])
        let limited = try StorageUsageCalculator(reader: tree, limits: StorageWalkLimits(maxDepth: 2, maxEntriesPerWalk: 100)).measure(request)
        XCTAssertEqual(limited.usage(.photos).contentBytes, 111, "folders a (depth 1) and b (depth 2) are entered, c is not")
        XCTAssertFalse(limited.isComplete)
        let full = try StorageUsageCalculator(reader: tree, limits: StorageWalkLimits(maxDepth: 3, maxEntriesPerWalk: 100)).measure(request)
        XCTAssertEqual(full.usage(.photos).contentBytes, 1_111)
        XCTAssertTrue(full.isComplete)
    }

    func testEntryLimitStopsExactlyAtTheLimit() throws {
        let request = StorageRequest(container: "/c", roots: [.photos: ["/c/P"]])
        let limits = StorageWalkLimits(maxDepth: 1_000_000, maxEntriesPerWalk: 1_000)
        let report = try StorageUsageCalculator(reader: EndlessTree(filesPerFolder: 9), limits: limits).measure(request)
        // Ten items per folder (nine files, then "d"): the first 1,000 items hold 900 files.
        XCTAssertEqual(report.usage(.photos).fileCount, 900)
        XCTAssertEqual(report.usage(.photos).contentBytes, 9_000)
        XCTAssertFalse(report.isComplete)
    }

    func testUnreadableFolderIsSkippedAndMarksTheReportIncomplete() throws {
        var tree = sampleTree()
        tree.nodes["/c/Photos/sub"] = .unreadable
        let report = try StorageUsageCalculator(reader: tree).measure(StorageRequest(container: "/c", roots: [.photos: ["/c/Photos"]]))
        XCTAssertEqual(report.usage(.photos).contentBytes, 1_000)
        XCTAssertFalse(report.isComplete)
    }

    func testHostileNamesNeverSteerTheWalk() throws {
        struct Hostile: StorageDirectoryReading {
            func kind(atPath path: String) -> StorageEntry.Kind? { .directory }
            func entries(inDirectory path: String) throws -> [StorageEntry] {
                guard path == "/c/P" else { return [StorageEntry(name: "x", kind: .file, contentBytes: 1_000_000)] }
                return [StorageEntry(name: "..", kind: .directory), StorageEntry(name: ".", kind: .directory),
                        StorageEntry(name: "a/../../..", kind: .directory), StorageEntry(name: "", kind: .directory),
                        StorageEntry(name: "ok", kind: .file, contentBytes: 5)]
            }
            func resolvedPath(_ path: String) -> String { path }
        }
        let report = try StorageUsageCalculator(reader: Hostile()).measure(StorageRequest(container: "/c", roots: [.photos: ["/c/P"]]))
        XCTAssertEqual(report.usage(.photos), StorageUsage(contentBytes: 5, spaceUsed: 5, fileCount: 1))
    }

    func testCancellationStopsAnEndlessWalk() async {
        let calculator = StorageUsageCalculator(reader: EndlessTree(filesPerFolder: 50),
                                                limits: StorageWalkLimits(maxDepth: Int.max, maxEntriesPerWalk: Int.max))
        let request = StorageRequest(container: "/c", roots: [.photos: ["/c/P"]])
        let task = Task.detached(priority: .utility) { () throws -> StorageReport in try calculator.measure(request) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("an endless walk only ends by cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testCategoryTitlesAndOrder() {
        XCTAssertEqual(StorageCategory.allCases.map { (c: StorageCategory) -> String in c.title },
                       ["Photos", "Videos", "Scenes", "Presets", "Imported audio", "Recordings", "Shares and exports",
                        "Caches", "Other app data"])
    }

    // MARK: Real file system (the acceptance)

    #if canImport(Darwin)
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("StorageUsageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func write(_ count: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: count).write(to: url)
    }

    /// Per regular file: space used ≤ content bytes + one 4 KiB block (research R1).
    static let overheadPerFile: Int64 = 4_096

    func testFixtureTreeTotalsAgreeWithTheBytesWrittenWithinFileSystemOverhead() throws {
        let container = root.appendingPathComponent("container", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try write(1_000_000, to: outside.appendingPathComponent("big.bin"))

        // Photos: 240 small files spread over nested folders, 1 to 4,000 bytes each.
        let photos = container.appendingPathComponent("Library/Application Support/Photos", isDirectory: true)
        var expectedPhotos: Int64 = 0
        for i in 0..<240 {
            let size = 1 + (i * 397) % 4_000
            let folder = photos.appendingPathComponent("n\(i % 4)/m\(i % 3)", isDirectory: true)
            try write(size, to: folder.appendingPathComponent("f\(i).bin"))
            expectedPhotos += Int64(size)
        }
        // Links to a folder and a file outside: never followed.
        try FileManager.default.createSymbolicLink(at: photos.appendingPathComponent("toOutside"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: photos.appendingPathComponent("toBig"),
                                                   withDestinationURL: outside.appendingPathComponent("big.bin"))

        // Videos: a sparse file of 10,000,001 bytes: one byte written, then extended by truncation (APFS
        // allocates no blocks for the hole; seeking past the end and writing fills the gap instead).
        let videos = container.appendingPathComponent("Library/Application Support/Videos", isDirectory: true)
        try FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        let sparse = videos.appendingPathComponent("sparse.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: sparse.path, contents: Data([1])))
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 10_000_001)
        try handle.close()

        // Scenes: an empty folder only. Other: one settings file. A category root that is a link.
        try FileManager.default.createDirectory(at: container.appendingPathComponent("Library/Application Support/Scenes/empty"),
                                                withIntermediateDirectories: true)
        try write(1_000, to: container.appendingPathComponent("Library/Preferences/settings.plist"))
        let linkedRoot = container.appendingPathComponent("tmp/Recordings")
        try FileManager.default.createDirectory(at: linkedRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: outside)

        let reader = RecordingReader()
        let request = StorageRequest(container: container.path, roots: [
            .photos: [photos.path], .videos: [videos.path],
            .scenes: [container.appendingPathComponent("Library/Application Support/Scenes").path],
            .recordings: [linkedRoot.path], .caches: [outside.path],
        ])
        let report = try StorageUsageCalculator(reader: reader).measure(request)

        // Exact content bytes.
        XCTAssertEqual(report.usage(.photos).contentBytes, expectedPhotos)
        XCTAssertEqual(report.usage(.photos).fileCount, 240)
        XCTAssertEqual(report.usage(.videos).contentBytes, 10_000_001)
        XCTAssertEqual(report.usage(.scenes), StorageUsage())
        XCTAssertEqual(report.usage(.otherAppData).contentBytes, 1_000)
        XCTAssertEqual(report.usage(.recordings), StorageUsage(), "a root that is a link is not walked")
        XCTAssertEqual(report.usage(.caches), StorageUsage(), "a root outside the container is not walked")
        XCTAssertEqual(Set(report.skippedRoots), [linkedRoot.path, outside.path])
        XCTAssertEqual(report.total.contentBytes, expectedPhotos + 10_000_001 + 1_000)
        XCTAssertTrue(report.isComplete)

        // Space used within the overhead bound, per file and in total; the sparse file uses less than its length.
        let resolvedPhotos = reader.resolvedPath(photos.path)
        for folder in reader.listed where folder.hasPrefix(resolvedPhotos) {
            for entry in try reader.base.entries(inDirectory: folder) where entry.kind == .file {
                XCTAssertLessThanOrEqual(entry.spaceUsed, entry.contentBytes + Self.overheadPerFile, entry.name)
            }
        }
        XCTAssertLessThanOrEqual(report.usage(.photos).spaceUsed, expectedPhotos + 240 * Self.overheadPerFile)
        XCTAssertGreaterThan(report.usage(.photos).spaceUsed, 0)
        XCTAssertLessThan(report.usage(.videos).spaceUsed, 10_000_001, "sparse: the hole takes no blocks")
        XCTAssertLessThanOrEqual(report.total.spaceUsed, report.total.contentBytes + Int64(report.total.fileCount) * Self.overheadPerFile)

        // The folder behind the links is never listed.
        let resolvedOutside = reader.resolvedPath(outside.path)
        XCTAssertFalse(reader.listed.contains { (path: String) -> Bool in path.hasPrefix(resolvedOutside) }, "\(reader.listed)")
    }

    func testRealReaderReportsKindsWithoutFollowingLinks() throws {
        let file = root.appendingPathComponent("a.bin")
        try write(10, to: file)
        let link = root.appendingPathComponent("l")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        let reader = FileManagerStorageReader()
        XCTAssertEqual(reader.kind(atPath: file.path), .file)
        XCTAssertEqual(reader.kind(atPath: root.path), .directory)
        XCTAssertEqual(reader.kind(atPath: link.path), .symbolicLink)
        XCTAssertNil(reader.kind(atPath: root.appendingPathComponent("missing").path))
        let entries = try reader.entries(inDirectory: root.path)
        XCTAssertEqual(entries.first { (e: StorageEntry) -> Bool in e.name == "a.bin" }?.contentBytes, 10)
        XCTAssertEqual(entries.first { (e: StorageEntry) -> Bool in e.name == "l" }?.kind, .symbolicLink)
    }
    #endif
}
