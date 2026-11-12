// PRE-012-T06: the user-preset store: the versioned record, stored copies, rollback and the trial
// records (PRE-012-R4, R17, R25-R27, S6).
import XCTest
@testable import PresetLibrary

final class UserPresetStoreTests: XCTestCase {
    private typealias F = UserPresetFixtures
    private struct WriteFailure: Error {}

    private func record(_ n: Int, state: UserPresetState = .playable, reason: PresetQuarantineReason? = nil,
                        fileName: String = "A - B.milk") -> UserPreset {
        let names = UserPresetName.displayName(fromFileName: fileName)
        let bytes = Array("content \(n)".utf8)
        return UserPreset(id: "user/00000000-0000-0000-0000-\(String(format: "%012d", n))", name: names.name, author: names.author,
                          originalFileName: UserPresetName.cleanedFileName(fileName), sha256: ContentHash.sha256Hex(bytes),
                          blobHash: ContentHash.gitBlobSHA1Hex(bytes), byteCount: bytes.count,
                          importedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(n)), state: state,
                          quarantine: reason ?? (state == .quarantined ? PresetQuarantineReason(.missingHeader) : nil),
                          license: PresetLicenseMetadata(authorFromFileName: !names.author.isEmpty, linesFound: []))
    }

    private func contents(_ n: Int) -> Data { Data("content \(n)".utf8) }

    private func golden() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "user-presets-v1", withExtension: "json", subdirectory: "Golden"))
        return try Data(contentsOf: url)
    }

    private func install(_ data: Data, in directory: URL) throws {
        try data.write(to: directory.appendingPathComponent(UserPresetStore.indexFileName))
    }

    // MARK: - Format

    func testTheGoldenVersion1FixtureDecodesIntact() throws {
        let decoded = try UserPresetsFile.decode(try golden())
        XCTAssertNil(decoded.migratedFrom)
        let presets = decoded.file.presets
        XCTAssertEqual(presets.map(\.state), [.playable, .pending, .quarantined, .quarantined])
        XCTAssertEqual(presets[0].name, "Sunrise 🌅 שלום")
        XCTAssertTrue(presets[0].provenOnScreen)
        XCTAssertEqual(presets[0].warnings, [PresetImportWarning(.missingTexture, detail: "mytexture")])
        XCTAssertEqual(presets[0].license.linesFound, ["// License: CC-BY 4.0"])
        XCTAssertFalse(presets[0].license.rightsVerified)
        XCTAssertEqual(presets[0].importedAt, Date(timeIntervalSince1970: 1_794_477_600))
        XCTAssertEqual(presets[2].quarantine?.kind, .engineRejected)
        XCTAssertEqual(presets[3].quarantine?.code, "aReasonThisVersionDoesNotKnow")
        XCTAssertNil(presets[3].quarantine?.kind)
        XCTAssertEqual(presets[3].quarantine?.message, "This preset could not be used.")
        // Re-encoding and decoding gives the same document.
        XCTAssertEqual(try UserPresetsFile.decode(try decoded.file.encode()).file, decoded.file)
    }

    func testUnknownCodesSurviveALoadAndASave() throws {
        let directory = try F.tempDirectory(self)
        try install(try golden(), in: directory)
        let store = UserPresetStore(directory: directory)
        XCTAssertEqual(store.availability, .available)
        XCTAssertEqual(store.presets.count, 4)
        try store.update(store.presets[1].id) { $0.state = .playable }
        let reread = UserPresetStore(directory: directory)
        XCTAssertEqual(reread.presets[3].quarantine?.code, "aReasonThisVersionDoesNotKnow")
        XCTAssertEqual(reread.presets[3].warnings.first?.code, "aWarningThisVersionDoesNotKnow")
        XCTAssertEqual(reread.presets[1].state, .playable)
    }

    func testANewerVersionIsNeitherReadNorModified() throws {
        let directory = try F.tempDirectory(self)
        let newer = Data(#"{"schemaVersion":2,"presets":[],"somethingNew":true}"#.utf8)
        try install(newer, in: directory)
        let store = UserPresetStore(directory: directory)
        XCTAssertEqual(store.availability, .newerFormat(version: 2))
        XCTAssertEqual(store.presets, [])
        XCTAssertThrowsError(try store.add(record(1), contents: contents(1))) {
            XCTAssertEqual($0 as? UserPresetStore.StoreError, .newerFormat)
        }
        XCTAssertThrowsError(try store.writeRecord(.trial, presetID: "user/x"))
        XCTAssertEqual(F.snapshot(directory), ["/index.json": newer])
    }

    func testAnUnreadableIndexIsSetAsideAndTheStoreStaysUsable() throws {
        let invalid: [Data] = [
            Data("not json".utf8),
            Data(#"{"schemaVersion":1}"#.utf8),
            try brokenGolden { $0[1]["id"] = $0[0]["id"] },                    // duplicate id
            try brokenGolden { $0[1]["sha256"] = $0[0]["sha256"] },            // duplicate content
            try brokenGolden { $0[0]["sha256"] = "XYZ" },                      // not a hash
            try brokenGolden { $0[0]["sha256"] = "../../../../etc/passwd" },   // a path is not a hash
            try brokenGolden { $0[2]["quarantine"] = nil },                    // quarantined without a reason
            try brokenGolden { $0[0]["byteCount"] = 99_999_999 },
            try brokenGolden { $0[0]["id"] = "included/x.milk" },              // not a user id
        ]
        for (index, data) in invalid.enumerated() {
            let directory = try F.tempDirectory(self)
            try install(data, in: directory)
            let store = UserPresetStore(directory: directory)
            XCTAssertEqual(store.availability, .available, "\(index)")
            XCTAssertEqual(store.loadNotice, .unreadableSetAside, "\(index)")
            XCTAssertEqual(store.presets, [], "\(index)")
            XCTAssertEqual(F.snapshot(directory), ["/index.unreadable.json": data], "\(index)")
            try store.add(record(1), contents: contents(1))
            XCTAssertEqual(UserPresetStore(directory: directory).presets.count, 1, "\(index)")
        }
    }

    private func brokenGolden(_ change: (inout [[String: Any]]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try golden()) as? [String: Any])
        var presets = try XCTUnwrap(object["presets"] as? [[String: Any]])
        change(&presets)
        object["presets"] = presets
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testAnOversizeIndexIsUnreadable() {
        let big = Data(repeating: 0x20, count: PresetImportLimits.maxIndexBytes + 1)
        XCTAssertThrowsError(try UserPresetsFile.decode(big)) { XCTAssertEqual($0 as? UserPresetsFile.ReadError, .unreadable) }
    }

    // MARK: - Files (R4)

    func testStoredNamesComeFromTheContentHashWhateverTheFileIsCalled() throws {
        let hostile = ["../../evil.milk", "a/b.milk", "..", "nul\u{0}byte.milk", "🎆 שלום \u{202E}gnp.milk",
                       String(repeating: "n", count: 400) + ".milk", "", "   ", "con:aux\\prn.milk"]
        let directory = try F.tempDirectory(self)
        let store = UserPresetStore(directory: directory)
        for (index, name) in hostile.enumerated() {
            let preset = record(index + 1, fileName: name)
            try store.add(preset, contents: contents(index + 1))
            XCTAssertFalse(preset.originalFileName.contains("/"), name)
            XCTAssertFalse(preset.originalFileName.contains("\\"), name)
            XCTAssertFalse(preset.originalFileName.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x202E }, name)
            XCTAssertLessThanOrEqual(preset.originalFileName.count, 255)
            XCTAssertTrue((1...120).contains(preset.name.count), name)
        }
        let stored = F.snapshot(directory).keys.filter { $0 != "/index.json" }.sorted()
        XCTAssertEqual(stored.count, hostile.count)
        for path in stored {
            XCTAssertTrue(path.hasPrefix("/files/"), path)
            let name = String(path.dropFirst("/files/".count))
            XCTAssertTrue(name.hasSuffix(".milk") && ContentHash.isHex(String(name.dropLast(5)), count: 64), path)
        }
        XCTAssertEqual(UserPresetName.displayName(fromFileName: "Geiss - Dancer.milk").name, "Dancer")
        XCTAssertEqual(UserPresetName.displayName(fromFileName: "Geiss - Dancer.milk").author, "Geiss")
        XCTAssertEqual(UserPresetName.displayName(fromFileName: "NoAuthor.MILK").name, "NoAuthor")
        XCTAssertEqual(UserPresetName.displayName(fromFileName: "NoAuthor.MILK").author, "")
        XCTAssertEqual(UserPresetName.displayName(fromFileName: " - .milk").name, "-")
    }

    func testAFileIsInFilesOrInQuarantineByState() throws {
        let directory = try F.tempDirectory(self)
        let store = UserPresetStore(directory: directory)
        let playable = record(1), bad = record(2, state: .quarantined)
        try store.add(playable, contents: contents(1))
        try store.add(bad, contents: contents(2))
        XCTAssertEqual(Set(F.snapshot(directory).keys), ["/index.json", "/files/\(playable.fileName)", "/quarantine/\(bad.fileName)"])
        XCTAssertEqual(store.contents(of: playable.id), contents(1))
        XCTAssertEqual(store.contents(of: bad.id), contents(2))

        try store.update(playable.id) { $0.state = .quarantined; $0.quarantine = PresetQuarantineReason(.timedOut) }
        XCTAssertEqual(Set(F.snapshot(directory).keys), ["/index.json", "/quarantine/\(playable.fileName)", "/quarantine/\(bad.fileName)"])
        XCTAssertEqual(UserPresetStore(directory: directory).presets.map(\.state), [.quarantined, .quarantined])

        try store.remove(bad.id)
        try store.remove(playable.id)
        XCTAssertEqual(Set(F.snapshot(directory).keys), ["/index.json"])
        XCTAssertThrowsError(try store.remove(bad.id)) { XCTAssertEqual($0 as? UserPresetStore.StoreError, .unknownPreset) }
    }

    // MARK: - Rollback (R25)

    func testAFailedSaveLeavesEverythingAsItWas() throws {
        let directory = try F.tempDirectory(self)
        let failing = LockedFlag()
        let store = UserPresetStore(directory: directory) { data, url in
            if failing.value { throw WriteFailure() }
            try data.write(to: url, options: .atomic)
        }
        try store.add(record(1), contents: contents(1))
        try store.add(record(2, state: .pending), contents: contents(2))
        let before = F.snapshot(directory)
        let memory = store.presets

        failing.value = true
        XCTAssertThrowsError(try store.add(record(3), contents: contents(3))) { XCTAssertEqual($0 as? UserPresetStore.StoreError, .saveFailed) }
        XCTAssertThrowsError(try store.update(record(2).id) { $0.state = .quarantined; $0.quarantine = PresetQuarantineReason(.timedOut) })
        XCTAssertThrowsError(try store.update(record(2).id) { $0.state = .playable })
        XCTAssertThrowsError(try store.remove(record(1).id))
        XCTAssertEqual(F.snapshot(directory), before)
        XCTAssertEqual(store.presets, memory)

        failing.value = false
        try store.remove(record(1).id)
        XCTAssertEqual(store.presets.map(\.id), [record(2).id])
    }

    func testAnUnchangedUpdateWritesNothing() throws {
        let directory = try F.tempDirectory(self)
        let writes = LockedCounter()
        let store = UserPresetStore(directory: directory) { data, url in
            writes.increment()
            try data.write(to: url, options: .atomic)
        }
        try store.add(record(1), contents: contents(1))
        try store.update(record(1).id) { $0.state = .playable }
        XCTAssertEqual(writes.value, 1)
    }

    // MARK: - Trial records (R17, R18)

    func testTrialRecordsAreWrittenReadAndCleared() throws {
        let directory = try F.tempDirectory(self)
        let store = UserPresetStore(directory: directory)
        XCTAssertEqual(store.leftoverRecords().count, 0)
        try store.writeRecord(.trial, presetID: "user/a")
        try store.writeRecord(.proving, presetID: "user/b")
        XCTAssertEqual(Set(F.snapshot(directory).keys), ["/trial.json", "/proving.json"])
        let leftovers = UserPresetStore(directory: directory).leftoverRecords()
        XCTAssertEqual(leftovers.map(\.phase), [.trial, .proving])
        XCTAssertEqual(leftovers.map(\.presetID), ["user/a", "user/b"])
        store.clearRecord(.trial)
        XCTAssertEqual(UserPresetStore(directory: directory).leftoverRecords().map(\.presetID), ["user/b"])
        store.clearRecord(.proving)
        XCTAssertEqual(F.snapshot(directory).count, 0)
    }

    func testAnUnreadableTrialRecordIsRemovedAndIgnored() throws {
        let directory = try F.tempDirectory(self)
        try Data("garbage".utf8).write(to: directory.appendingPathComponent("trial.json"))
        try Data(#"{"schemaVersion":1,"presetID":"user/a","phase":"trial"}"#.utf8).write(to: directory.appendingPathComponent("proving.json"))
        let store = UserPresetStore(directory: directory)
        XCTAssertEqual(store.leftoverRecords().count, 0, "garbage, and a record in the wrong file, name nothing")
        XCTAssertEqual(F.snapshot(directory).count, 0)
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int { lock.withLock { stored } }
    func increment() { lock.withLock { stored += 1 } }
}
