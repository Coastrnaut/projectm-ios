// PRE-012-T10, T17, T22: importing, quarantine and the trial state machine with a scripted trial
// (PRE-012-R2-R6, R13-R20, R24, R26, R27; S1, S4).
import XCTest
@testable import PresetLibrary

final class UserPresetLibraryTests: XCTestCase {
    private typealias F = UserPresetFixtures
    private var folder: URL!     // where "the user's files" are
    private var directory: URL!  // the library

    override func setUpWithError() throws {
        folder = try F.tempDirectory(self)
        directory = try F.tempDirectory(self).appendingPathComponent("UserPresets")
    }

    private func library(_ trial: FakeTrial? = FakeTrial(), context: PresetImportContext = .empty,
                         write: (@Sendable (Data, URL) throws -> Void)? = nil) async -> UserPresetLibrary {
        let library = UserPresetLibrary(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) }, write: write)
        _ = await library.load()
        await library.setContext(context)
        await library.setTrial(trial)
        return library
    }

    private func preset(_ outcome: PresetImportOutcome, file: StaticString = #filePath, line: UInt = #line) throws -> UserPreset {
        switch outcome {
        case .added(let preset), .waiting(let preset), .quarantined(let preset): return preset
        case .refused(let refusal):
            XCTFail("refused: \(refusal)", file: file, line: line)
            throw CancellationError()
        }
    }

    // MARK: - US1: a valid file

    func testAValidFileIsCopiedTriedAndPlayable() async throws {
        let trial = FakeTrial()
        let library = await library(trial)
        let source = try F.write(F.valid, named: "Example Author - Sunrise.milk", in: folder)
        let outcome = await library.importFile(at: source)
        guard case .added(let added) = outcome else { return XCTFail("\(outcome)") }

        XCTAssertEqual(added.name, "Sunrise")
        XCTAssertEqual(added.author, "Example Author")
        XCTAssertEqual(added.originalFileName, "Example Author - Sunrise.milk")
        XCTAssertEqual(added.state, .playable)
        XCTAssertFalse(added.provenOnScreen)
        XCTAssertEqual(added.byteCount, F.validBytes.count)
        XCTAssertEqual(added.sha256, ContentHash.sha256Hex(F.validBytes))
        XCTAssertEqual(added.blobHash, ContentHash.gitBlobSHA1Hex(F.validBytes))
        XCTAssertEqual(added.importedAt, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(added.id.hasPrefix("user/"))
        XCTAssertEqual(added.license, PresetLicenseMetadata(origin: .userImport, rightsVerified: false, authorFromFileName: true, linesFound: []))
        XCTAssertEqual(outcome.message(fileName: "x"), "Added “Sunrise” to My Presets.")
        XCTAssertFalse(outcome.needsAlert)

        XCTAssertEqual(trial.calls, [Data(F.validBytes)], "the trial saw exactly the stored bytes")
        let playable = await library.data(for: added.id)
        XCTAssertEqual(playable, Data(F.validBytes))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("trial.json").path))

        // R2: the original is not needed again; a new launch still has the preset.
        try FileManager.default.removeItem(at: source)
        let relaunched = await self.library()
        let snapshot = await relaunched.snapshot
        XCTAssertEqual(snapshot.playable, [added])
        let again = await relaunched.data(for: added.id)
        XCTAssertEqual(again, Data(F.validBytes))
    }

    func testWarningsAndLicenseLinesAreRecorded() async throws {
        let library = await library(context: PresetImportContext(builtIn: [:], blockedHashes: [], knownTextures: ["worms"]))
        let comp = ["shader_body", "{", "ret = tex2D(sampler_main, uv).xyz + tex2D(sampler_mytexture, uv).xyz + tex2D(sampler_worms, uv).xyz;", "}"]
        let text = F.preset(comp: comp, extra: ["// License: CC-BY 4.0, Example Author"])
        let outcome = await library.importFile(at: try F.write(text, named: "NoAuthor.milk", in: folder))
        let added = try preset(outcome)
        XCTAssertEqual(added.state, .playable)
        XCTAssertEqual(added.warnings, [PresetImportWarning(.missingTexture, detail: "mytexture")])
        XCTAssertEqual(added.license.linesFound, ["// License: CC-BY 4.0, Example Author"])
        XCTAssertFalse(added.license.authorFromFileName)
        XCTAssertEqual(added.author, "")
        XCTAssertTrue(outcome.needsAlert)
        XCTAssertEqual(outcome.message(fileName: "x"), "Added “NoAuthor” to My Presets with 1 warning. See its information for details.")
    }

    // MARK: - Refusals: nothing is stored (R3, R5, R6, R27)

    func testRefusalsStoreNothing() async throws {
        let builtInBytes = Array(F.preset(settings: ["zoom=1.5"]).utf8)
        let blockedBytes = Array(F.preset(settings: ["zoom=1.6"]).utf8)
        let context = PresetImportContext(
            builtIn: [ContentHash.gitBlobSHA1Hex(builtInBytes): .init(name: "Spiral 1", pack: "Cream of the Crop")],
            blockedHashes: [ContentHash.gitBlobSHA1Hex(blockedBytes)], knownTextures: [])
        let library = await library(context: context)
        _ = try preset(await library.importFile(at: try F.write(F.valid, named: "A - First.milk", in: folder)))
        let before = F.snapshot(directory)

        let subfolder = folder.appendingPathComponent("folder.milk")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        let link = folder.appendingPathComponent("link.milk")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder.appendingPathComponent("A - First.milk"))
        let cases: [(URL, PresetImportRefusal)] = [
            (subfolder, .notAFile),
            (link, .notAFile),
            (try F.write(F.valid + "x", named: "notes.txt", in: folder), .wrongType),
            (try F.write("", named: "empty.milk", in: folder), .empty),
            (try F.write(Data(repeating: 0x20, count: PresetImportLimits.maxFileBytes + 1), named: "big.milk", in: folder), .tooLarge),
            (folder.appendingPathComponent("missing.milk"), .unreadable),
            (try F.write(F.valid, named: "Other name.milk", in: folder), .duplicateOfImported(name: "First")),
            (try F.write(Data(builtInBytes), named: "copy.milk", in: folder), .duplicateOfBuiltIn(name: "Spiral 1", pack: "Cream of the Crop")),
            (try F.write(Data(blockedBytes), named: "taken down.milk", in: folder), .blocked),
        ]
        for (url, expected) in cases {
            let outcome = await library.importFile(at: url)
            XCTAssertEqual(outcome, .refused(expected), url.lastPathComponent)
            XCTAssertFalse(expected.message.isEmpty)
            XCTAssertEqual(F.snapshot(directory), before, url.lastPathComponent)
        }
        XCTAssertTrue(PresetImportRefusal.tooLarge.message.contains("524,288"))
        XCTAssertEqual(PresetImportOutcome.refused(.wrongType).message(fileName: "notes.txt"),
                       "“notes.txt” was not imported. Only Milkdrop preset files (.milk) can be imported.")
        let snapshot = await library.snapshot
        XCTAssertEqual(snapshot.playable.count, 1)
        XCTAssertEqual(snapshot.quarantined.count, 0)
    }

    func testAFileAtTheSizeLimitIsRead() async throws {
        let library = await library()
        var text = F.valid
        text += String(repeating: "// pad\n", count: (PresetImportLimits.maxFileBytes - text.utf8.count) / 7)
        text += String(repeating: " ", count: PresetImportLimits.maxFileBytes - text.utf8.count)
        XCTAssertEqual(text.utf8.count, PresetImportLimits.maxFileBytes)
        let outcome = await library.importFile(at: try F.write(text, named: "limit.milk", in: folder))
        // More than 20,000 lines: read in full, then quarantined by the static check, not refused.
        XCTAssertEqual(try preset(outcome).quarantine?.kind, .tooManyLines)
    }

    func testTheLibraryIsFullAtItsLimit() async throws {
        let library = await library()
        for index in 0..<PresetImportLimits.maxUserPresets {
            let outcome = await library.importFile(at: try F.write(F.preset(settings: ["zoom=1.\(index)"]), named: "p.milk", in: folder))
            guard case .added = outcome else { return XCTFail("\(index): \(outcome)") }
        }
        let before = F.snapshot(directory)
        let outcome = await library.importFile(at: try F.write(F.preset(settings: ["zoom=2"]), named: "p.milk", in: folder))
        XCTAssertEqual(outcome, .refused(.libraryFull))
        XCTAssertEqual(F.snapshot(directory), before)
    }

    func testANewerRecordRefusesImports() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":9,"presets":[]}"#.utf8).write(to: directory.appendingPathComponent("index.json"))
        let library = await library()
        let before = F.snapshot(directory)
        let outcome = await library.importFile(at: try F.write(F.valid, named: "a.milk", in: folder))
        XCTAssertEqual(outcome, .refused(.libraryUnavailable))
        let snapshot = await library.snapshot
        XCTAssertEqual(snapshot.availability, .newerFormat(version: 9))
        XCTAssertEqual(F.snapshot(directory), before)
    }

    func testAFailedSaveRefusesAndChangesNothing() async throws {
        let failing = LockedFlag()
        let library = await library(write: { data, url in
            if failing.value { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        _ = try preset(await library.importFile(at: try F.write(F.valid, named: "a.milk", in: folder)))
        let before = F.snapshot(directory)
        failing.value = true
        let outcome = await library.importFile(at: try F.write(F.preset(settings: ["zoom=2"]), named: "b.milk", in: folder))
        XCTAssertEqual(outcome, .refused(.saveFailed))
        let bad = await library.importFile(at: try F.write("garbage but text\n", named: "c.milk", in: folder))
        XCTAssertEqual(bad, .refused(.saveFailed))
        XCTAssertEqual(F.snapshot(directory), before)
    }

    // MARK: - US2: quarantine (R13, R15, R16, R20, R24, R27)

    func testAStaticallyInvalidFileIsQuarantinedWithoutATrial() async throws {
        let trial = FakeTrial()
        let library = await library(trial)
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
        let outcome = await library.importFile(at: try F.write(jpeg, named: "photo.milk", in: folder))
        guard case .quarantined(let bad) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(bad.state, .quarantined)
        XCTAssertEqual(bad.quarantine?.kind, .binaryContent)
        XCTAssertEqual(trial.calls, [], "an invalid file never reaches an engine")
        let data = await library.data(for: bad.id)
        XCTAssertNil(data, "R20")
        XCTAssertEqual(Set(F.snapshot(directory).keys), ["/index.json", "/quarantine/\(bad.fileName)"])
        XCTAssertEqual(outcome.message(fileName: "photo.milk"),
                       "“photo.milk” was put in Quarantine. This file is not text. A Milkdrop preset is a plain text file.")
        let snapshot = await library.snapshot
        XCTAssertEqual(snapshot.playable, [])
        XCTAssertEqual(snapshot.quarantined, [bad])
    }

    func testEngineFailureAndTimeoutQuarantine() async throws {
        let trial = FakeTrial([.failed("Could not compile per-frame code: syntax error"), .timedOut])
        let library = await library(trial)
        let first = try preset(await library.importFile(at: try F.write(F.preset(settings: ["zoom=1.1"]), named: "one.milk", in: folder)))
        XCTAssertEqual(first.quarantine, PresetQuarantineReason(.engineRejected, detail: "Could not compile per-frame code: syntax error"))
        XCTAssertEqual(first.quarantine?.message, "The visualizer could not load this preset. (Could not compile per-frame code: syntax error)")
        let second = try preset(await library.importFile(at: try F.write(F.preset(settings: ["zoom=1.2"]), named: "two.milk", in: folder)))
        XCTAssertEqual(second.quarantine?.kind, .timedOut)
        for id in [first.id, second.id] {
            let data = await library.data(for: id)
            XCTAssertNil(data)
        }
        XCTAssertEqual(Set(F.snapshot(directory).keys), ["/index.json", "/quarantine/\(first.fileName)", "/quarantine/\(second.fileName)"])
        XCTAssertEqual(trial.calls.count, 2)
    }

    func testAnUnavailableTrialLeavesThePresetWaitingAndUnplayable() async throws {
        let trial = FakeTrial([.unavailable("no renderer"), .unavailable("still none")])
        let library = await library(trial)
        let outcome = await library.importFile(at: try F.write(F.valid, named: "wait.milk", in: folder))
        guard case .waiting(let waiting) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(waiting.state, .pending)
        var data = await library.data(for: waiting.id)
        XCTAssertNil(data, "not playable before a trial passed (R14)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("trial.json").path))

        await library.runPendingTrials()      // still unavailable
        var snapshot = await library.snapshot
        XCTAssertEqual(snapshot.pending.map(\.id), [waiting.id])
        await library.runPendingTrials()      // now passes
        snapshot = await library.snapshot
        XCTAssertEqual(snapshot.pending, [])
        XCTAssertEqual(snapshot.playable.map(\.id), [waiting.id])
        data = await library.data(for: waiting.id)
        XCTAssertEqual(data, Data(F.validBytes))

        // With no trial at all, imports wait.
        let none = await self.library(nil)
        let second = await none.importFile(at: try F.write(F.preset(settings: ["zoom=3"]), named: "later.milk", in: folder))
        guard case .waiting = second else { return XCTFail("\(second)") }
    }

    func testPendingTrialsStopAtTheFirstUnavailable() async throws {
        let none = await library(nil)
        for index in 0..<3 {
            _ = await none.importFile(at: try F.write(F.preset(settings: ["zoom=1.\(index)"]), named: "p\(index).milk", in: folder))
        }
        let trial = FakeTrial([.passed, .unavailable("busy")])
        await none.setTrial(trial)
        await none.runPendingTrials()
        XCTAssertEqual(trial.calls.count, 2)
        let snapshot = await none.snapshot
        XCTAssertEqual(snapshot.playable.map(\.name), ["p0"])
        XCTAssertEqual(snapshot.pending.map(\.name), ["p1", "p2"])
    }

    func testQuarantinedContentIsRefusedUntilItIsDeleted() async throws {
        let library = await library(FakeTrial([.failed("bad")]))
        let source = try F.write(F.valid, named: "retry.milk", in: folder)
        let bad = try preset(await library.importFile(at: source))
        let again = await library.importFile(at: source)
        XCTAssertEqual(again, .refused(.duplicateOfQuarantined(name: "retry.milk", reason: "The visualizer could not load this preset. (bad)")))

        let removed = await library.remove(bad.id)
        XCTAssertTrue(removed)
        XCTAssertEqual(Set(F.snapshot(directory).keys), ["/index.json"])
        let third = await library.importFile(at: source)     // the fake now passes
        guard case .added = third else { return XCTFail("\(third)") }
        let unknown = await library.remove("user/nothing")
        XCTAssertFalse(unknown)
    }

    func testQuarantineIsFullAtItsLimit() async throws {
        let library = await library()
        for index in 0..<PresetImportLimits.maxQuarantined {
            let outcome = await library.importFile(at: try F.write("no header \(index)\n", named: "q.milk", in: folder))
            guard case .quarantined = outcome else { return XCTFail("\(index): \(outcome)") }
        }
        let before = F.snapshot(directory)
        let outcome = await library.importFile(at: try F.write("no header again\n", named: "q.milk", in: folder))
        XCTAssertEqual(outcome, .refused(.quarantineFull))
        XCTAssertEqual(F.snapshot(directory), before)
    }

    func testEveryReasonAndRefusalHasWordsAndLimitsAreNamed() {
        for kind in PresetQuarantineReason.Kind.allCases {
            XCTAssertGreaterThan(PresetQuarantineReason(kind, detail: "per_frame_").message.count, 20, "\(kind)")
        }
        XCTAssertTrue(PresetQuarantineReason(.lineTooLong).message.contains("8,192"))
        XCTAssertTrue(PresetQuarantineReason(.tooManyLines).message.contains("20,000"))
        XCTAssertTrue(PresetQuarantineReason(.blockTooLarge, detail: "warp_").message.contains("131,072"))
        XCTAssertTrue(PresetQuarantineReason(.blockTooLarge, detail: "warp_").message.contains("warp shader"))
        XCTAssertTrue(PresetQuarantineReason(.statementTooLong, detail: "per_pixel_").message.contains("8,192"))
        XCTAssertTrue(PresetQuarantineReason(.nestingTooDeep, detail: "wave_0_per_point").message.contains("64"))
        XCTAssertEqual(PresetQuarantineReason(.engineRejected, detail: String(repeating: "m", count: 900)).detail?.count, 300)
        for kind in PresetImportWarning.Kind.allCases {
            XCTAssertGreaterThan(PresetImportWarning(kind, detail: "1").message.count, 20, "\(kind)")
        }
    }

    // MARK: - US3: the app ended during a trial or while first showing a preset (R17-R19, S4)

    func testAnAppThatEndedDuringATrialQuarantinesThePresetAndNeverRetriesIt() async throws {
        let hanging = FakeTrial()
        hanging.hangs = true
        let recordPath = directory.appendingPathComponent("trial.json").path
        let recordSeen = LockedFlag()
        hanging.onRun = { _ in recordSeen.value = FileManager.default.fileExists(atPath: recordPath) }
        let first = await library(hanging)
        let source = try F.write(F.valid, named: "killer.milk", in: folder)
        let stuck = Task { await first.importFile(at: source) }
        addTeardownBlock { stuck.cancel() }
        for _ in 0..<500 where hanging.calls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(hanging.calls.count, 1)
        XCTAssertTrue(recordSeen.value, "the record is on disk before the engine sees the preset (R17)")

        // "Relaunch": a new library on the same folder, the first one never finished.
        let trial = FakeTrial()
        let second = await library(trial)
        let snapshot = await second.snapshot
        XCTAssertEqual(snapshot.playable, [])
        XCTAssertEqual(snapshot.pending, [])
        XCTAssertEqual(snapshot.quarantined.map(\.quarantine?.kind), [.interruptedDuringCheck])
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordPath))
        await second.runPendingTrials()
        XCTAssertEqual(trial.calls, [], "no trial of it starts again")
        let id = try XCTUnwrap(snapshot.quarantined.first?.id)
        let data = await second.data(for: id)
        XCTAssertNil(data)
        // A third launch changes nothing.
        let third = await library(FakeTrial())
        let later = await third.snapshot
        XCTAssertEqual(later.quarantined, snapshot.quarantined)
    }

    func testProvingOnScreen() async throws {
        let library = await library()
        let added = try preset(await library.importFile(at: try F.write(F.valid, named: "new.milk", in: folder)))
        let recordPath = directory.appendingPathComponent("proving.json").path

        var began = await library.beginProving(added.id)
        XCTAssertTrue(began)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordPath))
        await library.endProving(added.id, proven: false)                  // the user switched away early
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordPath))
        var snapshot = await library.snapshot
        XCTAssertEqual(snapshot.playable.map(\.provenOnScreen), [false])

        began = await library.beginProving(added.id)
        XCTAssertTrue(began)
        await library.endProving(added.id, proven: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordPath))
        snapshot = await library.snapshot
        XCTAssertEqual(snapshot.playable.map(\.provenOnScreen), [true])
        began = await library.beginProving(added.id)
        XCTAssertFalse(began, "a proven preset needs no record")
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordPath))

        let relaunched = await self.library()
        let later = await relaunched.snapshot
        XCTAssertEqual(later.playable.map(\.provenOnScreen), [true])
        XCTAssertEqual(later.quarantined, [])
    }

    func testAnAppThatEndedWhileFirstShowingAPresetQuarantinesIt() async throws {
        let first = await library()
        let added = try preset(await library_import(first, "crash.milk"))
        let other = try preset(await first.importFile(at: try F.write(F.preset(settings: ["zoom=4"]), named: "fine.milk", in: folder)))
        let began = await first.beginProving(added.id)
        XCTAssertTrue(began)

        let second = await library()
        let snapshot = await second.snapshot
        XCTAssertEqual(snapshot.playable.map(\.id), [other.id])
        XCTAssertEqual(snapshot.quarantined.map(\.id), [added.id])
        XCTAssertEqual(snapshot.quarantined.first?.quarantine?.kind, .interruptedOnScreen)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("proving.json").path))
        XCTAssertEqual(Set(F.snapshot(directory).keys), ["/index.json", "/files/\(other.fileName)", "/quarantine/\(added.fileName)"])
    }

    private func library_import(_ library: UserPresetLibrary, _ name: String) async throws -> PresetImportOutcome {
        await library.importFile(at: try F.write(F.valid, named: name, in: folder))
    }

    func testAFailureOnTheVisibleRendererQuarantines() async throws {
        let library = await library()
        let added = try preset(await library_import(library, "late.milk"))
        _ = await library.beginProving(added.id)
        await library.quarantineOnScreenFailure(added.id, message: "Could not compile per-pixel code")
        let snapshot = await library.snapshot
        XCTAssertEqual(snapshot.playable, [])
        XCTAssertEqual(snapshot.quarantined.first?.quarantine, PresetQuarantineReason(.failedOnScreen, detail: "Could not compile per-pixel code"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("proving.json").path))
        let data = await library.data(for: added.id)
        XCTAssertNil(data)
        XCTAssertEqual(Set(F.snapshot(directory).keys), ["/index.json", "/quarantine/\(added.fileName)"])
    }

    func testALeftoverRecordThatCannotBeSavedStillBlocksThePreset() async throws {
        let first = await library()
        let added = try preset(await library_import(first, "held.milk"))
        _ = await first.beginProving(added.id)
        // The next launch cannot write (storage full): the preset must still not play.
        let second = await library(write: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        let data = await second.data(for: added.id)
        XCTAssertNil(data)
        let snapshot = await second.snapshot
        XCTAssertEqual(snapshot.playable, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("proving.json").path),
                      "the record stays so a later launch can finish the quarantine")
        let third = await library()
        let later = await third.snapshot
        XCTAssertEqual(later.quarantined.map(\.id), [added.id])
    }

    func testARecordNamingAnUnknownPresetIsDropped() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":1,"presetID":"user/gone","phase":"trial"}"#.utf8).write(to: directory.appendingPathComponent("trial.json"))
        let library = await library()
        let snapshot = await library.snapshot
        XCTAssertEqual(snapshot.quarantined, [])
        XCTAssertEqual(F.snapshot(directory).count, 0)
    }
}
