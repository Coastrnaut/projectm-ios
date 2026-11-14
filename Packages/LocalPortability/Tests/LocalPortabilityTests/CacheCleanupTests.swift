// FILE-010 safe cache cleanup: the allowlist planner and the re-checking executor with an injected file
// system on every platform (the Linux shape: FILE-010-S3, R4, R5, R9), and links to user data on the
// real file system (Darwin: FILE-010-S2).
import Foundation
import XCTest
@testable import LocalPortability

/// An in-memory file system keyed by absolute path; removal deletes a node and everything below it
/// (a link node is removed alone: its target is another key).
private final class FakeFileSystem: CacheCleanupFileSystem, @unchecked Sendable {
    enum Node: Equatable { case file(Int64), directory, link }
    private let lock = NSLock()
    private var nodes: [String: Node]
    private var resolutions: [String: String] = [:]
    private var failing: Set<String> = []
    /// Extra raw entries per folder (hostile names).
    var extraEntries: [String: [StorageEntry]] = [:]

    struct Failure: Error {}

    init(_ nodes: [String: Node]) { self.nodes = nodes }

    func node(_ path: String) -> Node? { lock.withLock { nodes[path] } }
    func resolve(_ path: String, to other: String) { lock.withLock { resolutions[path] = other } }
    func failRemoval(_ path: String) { lock.withLock { _ = failing.insert(path) } }
    func delete(_ path: String) { lock.withLock { nodes[path] = nil } }

    func kind(atPath path: String) -> StorageEntry.Kind? {
        switch node(path) {
        case nil: nil
        case .file: .file
        case .directory: .directory
        case .link: .symbolicLink
        }
    }

    func entries(inDirectory path: String) throws -> [StorageEntry] {
        let prefix = path + "/"
        let snapshot = lock.withLock { nodes }
        var result: [StorageEntry] = []
        for (key, node) in snapshot where key.hasPrefix(prefix) {
            let name = String(key.dropFirst(prefix.count))
            if name.contains("/") { continue }
            switch node {
            case let .file(size): result.append(StorageEntry(name: name, kind: .file, contentBytes: size, spaceUsed: size))
            case .directory: result.append(StorageEntry(name: name, kind: .directory))
            case .link: result.append(StorageEntry(name: name, kind: .symbolicLink))
            }
        }
        result += extraEntries[path] ?? []
        return result.sorted { (a: StorageEntry, b: StorageEntry) -> Bool in a.name < b.name }
    }

    func resolvedPath(_ path: String) -> String { lock.withLock { resolutions[path] ?? path } }

    func removeItem(atPath path: String) throws {
        try lock.withLock {
            if failing.contains(path) { throw Failure() }
            guard nodes[path] != nil else { throw Failure() }
            let prefix = path + "/"
            for key in nodes.keys where key == path || key.hasPrefix(prefix) { nodes[key] = nil }
        }
    }
}

final class CacheCleanupTests: XCTestCase {
    private let container = "/c"
    private let caches = "/c/Library/Caches"
    private let recordings = "/c/tmp/Recordings"
    private let sharing = "/c/tmp/Sharing"
    private let photos = "/c/Library/Application Support/Photos"

    private func request(_ roots: [StorageCategory: [String]], inUse: Set<String> = []) -> CacheCleanupRequest {
        CacheCleanupRequest(container: container, cacheRoots: roots, protectedRoots: [photos], inUse: inUse)
    }

    private func paths(_ plan: CacheCleanupPlan) -> [String] {
        plan.items.map { (item: CacheCleanupItem) -> String in item.path }.sorted()
    }

    // FILE-010-S3: only allowlisted roots inside the container and away from user data are planned.
    func testRootsOutsideTheAllowlistAreRefused() throws {
        let fs = FakeFileSystem([
            caches: .directory, "\(caches)/shader": .file(100),
            "/c/linkroot": .link, "/x/out": .directory, "/x/out/f": .file(1),
            "/c/Library/Application Support": .directory, photos: .directory, "\(photos)/p.heic": .file(5),
            "\(photos)/sub": .directory,
        ])
        let plan = try CacheCleaner(fileSystem: fs).plan(request([
            .photos: [photos],
            .caches: [caches, "/c/linkroot", "/c", "/x/out", "/c/Library/Application Support", "\(photos)/sub", caches, "\(caches)/shader"],
        ]))
        XCTAssertEqual(plan.refused[photos], .notCleanable)
        XCTAssertEqual(plan.refused["/c/linkroot"], .symbolicLink)
        XCTAssertEqual(plan.refused["/c"], .outsideContainer, "the container itself")
        XCTAssertEqual(plan.refused["/x/out"], .outsideContainer)
        XCTAssertEqual(plan.refused["/c/Library/Application Support"], .overlapsProtected, "contains Photos")
        XCTAssertEqual(plan.refused["\(photos)/sub"], .overlapsProtected, "inside Photos")
        XCTAssertEqual(plan.refused["\(caches)/shader"], .duplicate, "inside another root")
        XCTAssertEqual(paths(plan), ["\(caches)/shader"])
        XCTAssertEqual(plan.bytesToFree, 100)
        XCTAssertTrue(plan.isComplete)
    }

    func testARootThatResolvesIntoUserDataIsRefused() throws {
        let fs = FakeFileSystem([caches: .directory, "\(caches)/x": .file(1)])
        fs.resolve(caches, to: photos)
        let plan = try CacheCleaner(fileSystem: fs).plan(request([.caches: [caches]]))
        XCTAssertEqual(plan.refused[caches], .overlapsProtected)
        XCTAssertTrue(plan.isEmpty)
    }

    func testHostileNamesAreIgnoredAndAMissingRootPlansNothing() throws {
        let fs = FakeFileSystem([caches: .directory, "\(caches)/ok": .file(3)])
        fs.extraEntries[caches] = [StorageEntry(name: "..", kind: .directory), StorageEntry(name: ".", kind: .directory),
                                   StorageEntry(name: "", kind: .file, contentBytes: 9), StorageEntry(name: "a/../../x", kind: .file, contentBytes: 9)]
        let plan = try CacheCleaner(fileSystem: fs).plan(request([.caches: [caches], .recordings: [recordings]]))
        XCTAssertEqual(paths(plan), ["\(caches)/ok"])
        XCTAssertTrue(plan.refused.isEmpty, "a missing root is not refused")
    }

    // REC-010-R7, S5: the recording library is user data: never cleanable, a cache root inside it is refused.
    func testSavedRecordingsAreNeverCleanable() throws {
        let library = "/c/Library/Application Support/RecordingLibrary"
        XCTAssertFalse(StorageCategory.savedRecordings.isCleanable)
        XCTAssertTrue(StorageCategory.recordings.isCleanable)
        let fs = FakeFileSystem([library: .directory, "\(library)/take.mp4": .file(10), recordings: .directory, "\(recordings)/x.mp4": .file(5)])
        let cleaner = CacheCleaner(fileSystem: fs)
        let saved = try cleaner.plan(CacheCleanupRequest(container: container, cacheRoots: [.savedRecordings: [library]],
                                                         protectedRoots: [library], inUse: []))
        XCTAssertEqual(saved.refused[library], .notCleanable)
        XCTAssertTrue(saved.isEmpty)
        let plan = try cleaner.plan(CacheCleanupRequest(container: container, cacheRoots: [.recordings: [recordings, library]],
                                                        protectedRoots: [library], inUse: []))
        XCTAssertEqual(paths(plan), ["\(recordings)/x.mp4"])
        XCTAssertEqual(plan.refused[library], .overlapsProtected)
    }

    // FILE-010-R5: an in-use file is kept, its folder entered, its siblings planned.
    func testInUseFilesAreKeptAndTheirFoldersEntered() throws {
        let fs = FakeFileSystem([
            recordings: .directory, "\(recordings)/offered.mov": .file(10), "\(recordings)/leftover.mov": .file(20),
            sharing: .directory, "\(sharing)/u1": .directory, "\(sharing)/u1/a.png": .file(30), "\(sharing)/u1/b.png": .file(40),
            "\(sharing)/u2": .directory, "\(sharing)/u2/c.png": .file(50),
        ])
        let plan = try CacheCleaner(fileSystem: fs).plan(request(
            [.recordings: [recordings], .sharesAndExports: [sharing]],
            inUse: ["\(recordings)/offered.mov", "\(sharing)/u1/a.png"]))
        XCTAssertEqual(paths(plan), ["\(recordings)/leftover.mov", "\(sharing)/u1/b.png", "\(sharing)/u2"])
        XCTAssertEqual(Set(plan.keptInUse), ["\(recordings)/offered.mov", "\(sharing)/u1/a.png"])
        XCTAssertEqual(plan.usage(.sharesAndExports).contentBytes, 90)
        XCTAssertEqual(plan.usage(.recordings).contentBytes, 20)

        let result = CacheCleaner(fileSystem: fs).execute(plan, inUse: ["\(recordings)/offered.mov", "\(sharing)/u1/a.png"])
        XCTAssertEqual(result.removed.count, 3)
        XCTAssertEqual(result.bytesFreed, 110)
        XCTAssertNotNil(fs.node("\(recordings)/offered.mov"))
        XCTAssertNotNil(fs.node("\(sharing)/u1/a.png"))
        XCTAssertNil(fs.node("\(sharing)/u2/c.png"))
        XCTAssertNotNil(fs.node(recordings), "the root folder itself stays")
    }

    func testAWholeFolderInUseKeepsEverythingInIt() throws {
        let fs = FakeFileSystem([recordings: .directory, "\(recordings)/a.mov": .file(1), "\(recordings)/b.mov": .file(2)])
        let plan = try CacheCleaner(fileSystem: fs).plan(request([.recordings: [recordings]], inUse: [recordings]))
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.keptInUse.count, 2)
    }

    // FILE-010-R4, R9: each item is checked again just before removal.
    func testExecuteChecksEachItemAgainAndContinuesAfterAFailure() throws {
        let fs = FakeFileSystem([
            caches: .directory, "\(caches)/gone": .file(1), "\(caches)/fails": .file(2), "\(caches)/now-used": .file(4),
            "\(caches)/d": .directory, "\(caches)/d/moved": .file(8), "\(caches)/ok": .file(16),
        ])
        let cleaner = CacheCleaner(fileSystem: fs)
        let plan = try cleaner.plan(request([.caches: [caches]]))
        XCTAssertEqual(plan.bytesToFree, 31)
        fs.delete("\(caches)/gone")
        fs.failRemoval("\(caches)/fails")
        fs.resolve("\(caches)/d", to: photos)   // the folder became a link after planning
        // Planned as a whole folder; check its parent rule with an item below it too.
        let nested = CacheCleanupPlan(items: [CacheCleanupItem(path: "\(caches)/d/moved", root: caches, category: .caches, kind: .file,
                                                               usage: StorageUsage(contentBytes: 8, spaceUsed: 8, fileCount: 1))],
                                      refused: [:], keptInUse: [], isComplete: true)
        let nestedResult = cleaner.execute(nested)
        XCTAssertEqual(nestedResult.failed, ["\(caches)/d/moved"], "never removed through a folder that became a link")

        let result = cleaner.execute(plan, inUse: ["\(caches)/now-used"])
        XCTAssertEqual(result.vanished, ["\(caches)/gone"])
        XCTAssertEqual(result.failed, ["\(caches)/fails"])
        XCTAssertEqual(result.keptInUse, ["\(caches)/now-used"])
        XCTAssertEqual(Set(result.removed), ["\(caches)/d", "\(caches)/ok"])
        XCTAssertEqual(result.bytesFreed, 24)
        XCTAssertNotNil(fs.node("\(caches)/now-used"))
    }

    func testAnItemOutsideItsRootIsNeverRemoved() {
        let fs = FakeFileSystem([caches: .directory, photos: .directory, "\(photos)/p.heic": .file(5)])
        let forged = CacheCleanupPlan(items: [CacheCleanupItem(path: "\(photos)/p.heic", root: caches, category: .caches, kind: .file,
                                                               usage: StorageUsage())],
                                      refused: [:], keptInUse: [], isComplete: true)
        let result = CacheCleaner(fileSystem: fs).execute(forged)
        XCTAssertEqual(result.failed, ["\(photos)/p.heic"])
        XCTAssertNotNil(fs.node("\(photos)/p.heic"))
    }

    func testLinksArePlannedAsLinksAndRemovedAlone() throws {
        let fs = FakeFileSystem([caches: .directory, "\(caches)/to-photos": .link, photos: .directory, "\(photos)/p.heic": .file(5)])
        let cleaner = CacheCleaner(fileSystem: fs)
        let plan = try cleaner.plan(request([.caches: [caches]]))
        XCTAssertEqual(plan.items.map { (item: CacheCleanupItem) -> StorageEntry.Kind in item.kind }, [.symbolicLink])
        XCTAssertEqual(plan.bytesToFree, 0)
        let result = cleaner.execute(plan)
        XCTAssertEqual(result.removed, ["\(caches)/to-photos"])
        XCTAssertEqual(fs.node("\(photos)/p.heic"), .file(5))
    }

    func testFolderSizesUseTheWalkLimits() throws {
        var nodes: [String: FakeFileSystem.Node] = [caches: .directory, "\(caches)/big": .directory, "\(caches)/big/n": .directory]
        for i in 0..<10 { nodes["\(caches)/big/f\(i)"] = .file(10) }
        nodes["\(caches)/big/n/g"] = .file(5)
        let fs = FakeFileSystem(nodes)
        let full = try CacheCleaner(fileSystem: fs).plan(request([.caches: [caches]]))
        XCTAssertEqual(full.usage(.caches), StorageUsage(contentBytes: 105, spaceUsed: 105, fileCount: 11))
        XCTAssertTrue(full.isComplete)
        let limited = try CacheCleaner(fileSystem: fs, limits: StorageWalkLimits(maxDepth: 32, maxEntriesPerWalk: 4)).plan(request([.caches: [caches]]))
        XCTAssertFalse(limited.isComplete)
        XCTAssertEqual(limited.items.count, 1, "the folder is still removed whole")
    }

    func testCleanableCategories() {
        XCTAssertEqual(StorageCategory.cleanable, [.recordings, .sharesAndExports, .caches])
        XCTAssertFalse(StorageCategory.scenes.isCleanable)
        XCTAssertFalse(StorageCategory.otherAppData.isCleanable)
    }

    #if canImport(Darwin)
    // FILE-010-S2 on the real file system: links to user data go, their targets stay byte-identical.
    func testLinksToUserDataAreRemovedAndTheirTargetsUntouched() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("FILE010-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        let support = base.appendingPathComponent("Library/Application Support", isDirectory: true)
        let photoFolder = support.appendingPathComponent("Photos", isDirectory: true)
        let videoFolder = support.appendingPathComponent("Videos", isDirectory: true)
        let cacheFolder = base.appendingPathComponent("Library/Caches", isDirectory: true)
        let share = base.appendingPathComponent("tmp/Sharing", isDirectory: true)
        for folder in [photoFolder, videoFolder, cacheFolder.appendingPathComponent("sub/deeper", isDirectory: true), share] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let photo = Data((0..<3_000).map { (i: Int) -> UInt8 in UInt8(i % 251) })
        let video = Data(repeating: 0x42, count: 7_000)
        try photo.write(to: photoFolder.appendingPathComponent("photo.heic"))
        try video.write(to: videoFolder.appendingPathComponent("video.mov"))
        try Data(repeating: 1, count: 1_000).write(to: cacheFolder.appendingPathComponent("shader.bin"))
        try Data(repeating: 2, count: 2_000).write(to: cacheFolder.appendingPathComponent("sub/deeper/piece.bin"))
        try Data(repeating: 3, count: 500).write(to: share.appendingPathComponent("copy.png"))
        try fm.createSymbolicLink(at: cacheFolder.appendingPathComponent("photo-link"), withDestinationURL: photoFolder.appendingPathComponent("photo.heic"))
        try fm.createSymbolicLink(at: cacheFolder.appendingPathComponent("sub/deeper/videos-link"), withDestinationURL: videoFolder)
        try fm.createSymbolicLink(at: share.appendingPathComponent("support-link"), withDestinationURL: support)

        let cleaner = CacheCleaner()
        let request = CacheCleanupRequest(container: base.path,
                                          cacheRoots: [.caches: [cacheFolder.path], .sharesAndExports: [share.path]],
                                          protectedRoots: [photoFolder.path, videoFolder.path])
        let plan = try cleaner.plan(request)
        XCTAssertTrue(plan.refused.isEmpty)
        XCTAssertEqual(plan.usage(.caches).contentBytes, 3_000, "links count zero; the folder behind a link is never walked")
        XCTAssertEqual(plan.usage(.sharesAndExports).contentBytes, 500)
        XCTAssertGreaterThanOrEqual(plan.bytesToFree, 3_500)

        let result = cleaner.execute(plan)
        XCTAssertTrue(result.failed.isEmpty, "\(result.failed)")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: cacheFolder.path), [])
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: share.path), [])
        XCTAssertEqual(try Data(contentsOf: photoFolder.appendingPathComponent("photo.heic")), photo)
        XCTAssertEqual(try Data(contentsOf: videoFolder.appendingPathComponent("video.mov")), video)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: videoFolder.path), ["video.mov"])
    }
    #endif
}
