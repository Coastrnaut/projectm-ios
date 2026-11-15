// PRE-017-T06, T10, T11: restore points of edited user presets (specs/250-pre-017-preset-restore-points;
// R1-R7, S1-S3). The acceptance: a revert restores the exact earlier bytes and removes no unrelated file.
import XCTest
@testable import PresetLibrary

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: Double = 1_800_000_000
    func tick() -> Date {
        lock.lock(); defer { lock.unlock() }
        seconds += 60
        return Date(timeIntervalSince1970: seconds)
    }
}

private final class WriteSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var failing = false
    var fails: Bool {
        get { lock.lock(); defer { lock.unlock() }; return failing }
        set { lock.lock(); failing = newValue; lock.unlock() }
    }
}

final class UserPresetHistoryTests: XCTestCase {
    private typealias F = UserPresetFixtures
    private var root: URL!
    private var directory: URL!
    private let clock = TestClock()

    override func setUpWithError() throws {
        root = try F.tempDirectory(self)
        directory = root.appendingPathComponent("UserPresets", isDirectory: true)
    }

    private func text(_ zoom: String) -> String { F.preset(settings: ["fDecay=0.950000", "zoom=" + zoom]) }

    private func record(_ number: Int, _ text: String) -> UserPreset {
        let bytes: [UInt8] = Array(text.utf8)
        return UserPreset(id: "user/00000000-0000-4000-8000-0000000000\(10 + number)", name: "Preset \(number)", author: "",
                          originalFileName: "p\(number).milk", sha256: ContentHash.sha256Hex(bytes), blobHash: ContentHash.gitBlobSHA1Hex(bytes),
                          byteCount: bytes.count, importedAt: Date(timeIntervalSince1970: 1_700_000_000), state: .playable,
                          provenOnScreen: true, license: PresetLicenseMetadata(authorFromFileName: false, linesFound: []))
    }

    /// Stores playable presets as a library saved before PRE-017 would have them (no history).
    @discardableResult
    private func seed(_ texts: [String]) throws -> [UserPreset] {
        let store = UserPresetStore(directory: directory)
        var records: [UserPreset] = []
        for (number, text) in texts.enumerated() {
            let preset = record(number, text)
            try store.add(preset, contents: Data(text.utf8))
            records.append(preset)
        }
        return records
    }

    private func library(write: (@Sendable (Data, URL) throws -> Void)? = nil,
                         limits: UserPresetVersionLimits = .standard) async -> UserPresetLibrary {
        let clock = self.clock
        let library = UserPresetLibrary(directory: directory, now: { clock.tick() }, write: write)
        _ = await library.load()
        await library.setContext(.empty)
        await library.setTrial(FakeTrial())
        await library.setVersionLimits(limits)
        return library
    }

    private func edit(_ library: UserPresetLibrary, _ id: String, to text: String) async throws -> UserPreset {
        let opened = await library.editorText(for: id)
        let current = try XCTUnwrap(opened)
        let outcome = await library.edit(id, name: "ignored", text: text, expectedSHA256: current.sha256)
        guard case .saved(let saved) = outcome else {
            XCTFail("edit not saved: \(outcome)")
            throw CancellationError()
        }
        return saved
    }

    private func sha(_ text: String) -> String { ContentHash.sha256Hex(Array(text.utf8)) }

    // MARK: - S1: revert restores the exact bytes and removes no unrelated file

    func testRevertRestoresTheEarlierBytesAndChangesOnlyTheVersionBookkeeping() async throws {
        let (a, b, c, q0, q1) = (text("1.100000"), text("1.200000"), text("1.300000"), text("0.900000"), text("0.800000"))
        let presets = try seed([a, q0])
        let p = presets[0].id, q = presets[1].id
        // Neighbours a revert must never touch: per-preset data beside the presets, thumbnails, the other preset's version.
        let collections = root.appendingPathComponent("PresetCollections", isDirectory: true)
        try FileManager.default.createDirectory(at: collections, withIntermediateDirectories: true)
        for name in ["collections.json", "tags.json", "notes.json", "overrides.json", "smart-collections.json"] {
            try Data("{\"\(name)\":\"\(p)\"}".utf8).write(to: collections.appendingPathComponent(name))
        }
        let thumbnails = root.appendingPathComponent("Thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: thumbnails.appendingPathComponent(sha(a) + ".png"))

        let library = await library()
        _ = try await edit(library, q, to: q1)
        _ = try await edit(library, p, to: b)
        let current = try await edit(library, p, to: c)
        let versions = await library.versions(of: p)
        XCTAssertEqual(versions.versions.map(\.sha256), [sha(b), sha(a)], "newest first")
        XCTAssertEqual(versions.versions.map(\.name), ["ignored", "Preset 0"], "the name each text had then")
        let before = F.snapshot(root)

        let outcome = await library.revert(p, to: sha(a), expectedSHA256: current.sha256)
        guard case .saved(let reverted) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(reverted.sha256, sha(a))
        XCTAssertEqual(reverted.name, current.name, "the name is kept")
        let data = await library.data(for: p)
        XCTAssertEqual(data, Data(a.utf8), "byte for byte")
        let after = F.snapshot(root)

        let bookkeeping: Set<String> = ["/UserPresets/index.json", "/UserPresets/history.json"]
        XCTAssertEqual(Set(before.keys).subtracting(after.keys), ["/UserPresets/files/\(sha(c)).milk"])
        XCTAssertEqual(Set(after.keys).subtracting(before.keys), ["/UserPresets/files/\(sha(a)).milk", "/UserPresets/versions/\(sha(c)).milk"])
        for (path, bytes) in before where after[path] != nil && !bookkeeping.contains(path) {
            XCTAssertEqual(after[path], bytes, "unchanged: \(path)")
        }
        XCTAssertNotNil(after["/UserPresets/versions/\(sha(q0)).milk"], "the other preset's version")

        // The revert is itself undoable: the replaced text is the newest version.
        let list = await library.versions(of: p)
        XCTAssertEqual(list.versions.map(\.sha256), [sha(c), sha(b), sha(a)])
        let undo = await library.revert(p, to: sha(c), expectedSHA256: sha(a))
        guard case .saved(let back) = undo else { return XCTFail("\(undo)") }
        XCTAssertEqual(back.sha256, sha(c))
    }

    func testAStaleOrDamagedRevertChangesNothing() async throws {
        let (a, b) = (text("1.100000"), text("1.200000"))
        let p = try seed([a])[0].id
        let library = await library()
        let current = try await edit(library, p, to: b)
        let before = F.snapshot(root)
        let stale = await library.revert(p, to: sha(a), expectedSHA256: sha(a))
        XCTAssertEqual(stale, .refused(.changedMeanwhile))

        try Data("damaged".utf8).write(to: directory.appendingPathComponent("versions/\(sha(a)).milk"))
        let damaged = F.snapshot(root)
        let outcome = await library.revert(p, to: sha(a), expectedSHA256: current.sha256)
        XCTAssertEqual(outcome, .refused(.versionUnavailable))
        XCTAssertEqual(outcome.message, "Not saved. This version could not be read.")
        let preview = await library.versionText(of: p, sha256: sha(a))
        XCTAssertNil(preview)
        XCTAssertEqual(F.snapshot(root), damaged)
        XCTAssertEqual(before.count, damaged.count)
    }

    // MARK: - S2: bounds and reference counting

    func testThePerPresetBoundDropsTheOldestButNeverAStillNamedText() async throws {
        let (a, b, c, d, x, y) = (text("1.1"), text("1.2"), text("1.3"), text("1.4"), text("0.7"), text("0.6"))
        let presets = try seed([a, x])
        let p = presets[0].id, q = presets[1].id
        let library = await library(limits: UserPresetVersionLimits(perPreset: 2, total: 500, totalBytes: 50_000_000))
        _ = try await edit(library, p, to: b)          // P: [a]
        _ = try await edit(library, q, to: a)          // Q: [x]; Q's text is a
        _ = try await edit(library, q, to: y)          // Q: [x, a]
        _ = try await edit(library, p, to: c)          // P: [a, b]
        _ = try await edit(library, p, to: d)          // P: [b, c] — a dropped from P, still named by Q
        let pVersions = await library.versions(of: p).versions.map(\.sha256)
        XCTAssertEqual(pVersions, [sha(c), sha(b)])
        let versions = directory.appendingPathComponent("versions", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: versions.appendingPathComponent(sha(a) + ".milk").path))

        // Removing Q drops its versions; a, named by nothing now, goes; P's versions stay.
        let removed = await library.remove(q)
        XCTAssertTrue(removed)
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: versions.path))
        XCTAssertEqual(names, [sha(b) + ".milk", sha(c) + ".milk"])
    }

    func testTotalBoundsDropTheGloballyOldestAndARepeatedTextAppearsOnce() {
        func version(_ hash: Character, _ minute: Double, bytes: Int = 100) -> UserPresetVersion {
            UserPresetVersion(sha256: String(repeating: hash, count: 64), blobHash: String(repeating: "0", count: 40), byteCount: bytes,
                              replacedAt: Date(timeIntervalSince1970: minute * 60), name: "n")
        }
        let limits = UserPresetVersionLimits(perPreset: 10, total: 3, totalBytes: 250)
        var file = UserPresetHistoryFile()
        file = file.adding(version("a", 1), to: "user/p", limits: limits)
        file = file.adding(version("b", 2), to: "user/q", limits: limits)
        file = file.adding(version("c", 3), to: "user/p", limits: limits)   // 300 bytes > 250: a (oldest) goes
        XCTAssertEqual(file.versions(of: "user/p").map(\.sha256.first), ["c"])
        XCTAssertEqual(file.versions(of: "user/q").map(\.sha256.first), ["b"])
        file = file.adding(version("b", 4, bytes: 100), to: "user/p", limits: UserPresetVersionLimits(perPreset: 10, total: 3, totalBytes: 1_000))
        XCTAssertEqual(file.namedHashes.count, 2, "one text named by two presets counts once")
        file = file.adding(version("d", 5), to: "user/q", limits: limits)    // 4 versions > 3: q's b (minute 2) goes
        XCTAssertEqual(file.versions(of: "user/q").map(\.sha256.first), ["d"])
        file = file.adding(version("c", 6), to: "user/p", limits: UserPresetVersionLimits(perPreset: 10, total: 3, totalBytes: 1_000))   // repeated: moves to the newest place
        XCTAssertEqual(file.versions(of: "user/p").map(\.sha256.first), ["b", "c"])
    }

    // MARK: - S3: migration, newer and unreadable lists, failed saves, leftovers

    func testOlderPresetsNewerAndUnreadableLists() async throws {
        let (a, b, c) = (text("1.1"), text("1.2"), text("1.3"))
        let p = try seed([a])[0].id
        // No history yet (saved before PRE-017): nothing listed, the first edit starts it.
        var library = await library()
        let empty = await library.versions(of: p)
        XCTAssertEqual(empty, .empty)
        _ = try await edit(library, p, to: b)
        let started = await library.versions(of: p).versions.map(\.sha256)
        XCTAssertEqual(started, [sha(a)])

        // A newer list is never written; edits still save, without a version.
        let historyURL = directory.appendingPathComponent("history.json")
        let newer = Data(#"{"schemaVersion":2,"presets":[],"future":true}"#.utf8)
        try newer.write(to: historyURL)
        library = await self.library()
        let unavailable = await library.versions(of: p)
        XCTAssertEqual(unavailable.availability, .newerFormat)
        _ = try await edit(library, p, to: c)
        XCTAssertEqual(try Data(contentsOf: historyURL), newer)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("versions/\(sha(a)).milk").path),
                      "nothing is collected while the list is from a newer version")

        // An unreadable list is set aside; versions start again.
        try Data("not json".utf8).write(to: historyURL)
        library = await self.library()
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("history.unreadable.json")), Data("not json".utf8))
        _ = try await edit(library, p, to: b)
        let restarted = await library.versions(of: p).versions.map(\.sha256)
        XCTAssertEqual(restarted, [sha(c)])
    }

    func testAFailedRecordSaveRestoresEveryFile() async throws {
        let (a, b, c) = (text("1.1"), text("1.2"), text("1.3"))
        let p = try seed([a])[0].id
        let failing = WriteSwitch()
        let library = await library(write: { (data: Data, url: URL) throws in
            if failing.fails { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        })
        let saved = try await edit(library, p, to: b)
        let before = F.snapshot(root)
        failing.fails = true
        let outcome = await library.edit(p, name: saved.name, text: c, expectedSHA256: saved.sha256)
        XCTAssertEqual(outcome, .refused(.saveFailed))
        XCTAssertEqual(F.snapshot(root), before)
        let list = await library.versions(of: p).versions.map(\.sha256)
        XCTAssertEqual(list, [sha(a)])
    }

    func testLoadCollectsUnnamedVersionTextsOnlyAndDropsEntriesOfRemovedPresets() async throws {
        let (a, b) = (text("1.1"), text("1.2"))
        let p = try seed([a])[0].id
        var library = await library()
        _ = try await edit(library, p, to: b)
        let versions = directory.appendingPathComponent("versions", isDirectory: true)
        let leftover = versions.appendingPathComponent(String(repeating: "e", count: 64) + ".milk")
        try Data("x".utf8).write(to: leftover)
        let foreign = versions.appendingPathComponent("readme.txt")
        try Data("keep".utf8).write(to: foreign)
        // An entry for a preset the record no longer has (its removal's list save was interrupted).
        var file = try UserPresetHistoryFile.decode(Data(contentsOf: directory.appendingPathComponent("history.json")))
        file.presets.append(.init(presetID: "user/gone", versions: file.presets[0].versions))
        try file.encode().write(to: directory.appendingPathComponent("history.json"))

        library = await self.library()
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path), "only <sha256>.milk names are collected")
        let reloaded = try UserPresetHistoryFile.decode(Data(contentsOf: directory.appendingPathComponent("history.json")))
        XCTAssertEqual(reloaded.presets.map(\.presetID), [p])
        let kept = await library.versions(of: p).versions.map(\.sha256)
        XCTAssertEqual(kept, [sha(a)])
    }
}
