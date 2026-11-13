// PRE-015-T11: editing a user preset's text and name (PRE-015-R9-R15, R22; S5). A failing or
// refused edit never changes a stored byte; a saved edit replaces the text through the
// content-addressed store; an app that ends during an edit's check keeps the last good version.
import XCTest
@testable import PresetLibrary

final class UserPresetEditingTests: XCTestCase {
    private typealias F = UserPresetFixtures
    private var directory: URL!
    private var folder: URL!

    private let original = F.valid
    private let edited = F.preset(settings: ["fDecay=0.900000", "zoom=1.200000"], warp: F.warpShader, comp: F.compShader)
    private let otherBuiltIn = F.preset(settings: ["zoom=0.5"])

    override func setUpWithError() throws {
        directory = try F.tempDirectory(self).appendingPathComponent("UserPresets")
        folder = try F.tempDirectory(self)
    }

    private func library(_ trial: FakeTrial? = FakeTrial(), blocked: Set<String> = [], now: Double = 1_800_000_000,
                         write: (@Sendable (Data, URL) throws -> Void)? = nil) async -> UserPresetLibrary {
        let library = UserPresetLibrary(directory: directory, now: { Date(timeIntervalSince1970: now) }, write: write)
        _ = await library.load()
        let builtIn = [ContentHash.gitBlobSHA1Hex(Array(original.utf8)): PresetImportContext.BuiltIn(name: "Alpha", pack: "Included"),
                       ContentHash.gitBlobSHA1Hex(Array(otherBuiltIn.utf8)): PresetImportContext.BuiltIn(name: "Gamma", pack: "Cream of the Crop")]
        await library.setContext(PresetImportContext(builtIn: builtIn, blockedHashes: blocked, knownTextures: []))
        await library.setTrial(trial)
        return library
    }

    private func duplicate(_ library: UserPresetLibrary) async throws -> UserPreset {
        let data = Data(original.utf8)
        let source = BundledPresetSource(id: "included/Alpha.milk", name: "Alpha", author: "A", fileName: "Alpha.milk", packID: "included",
                                         packTitle: "Included", licenseStatement: "Basis.", blobHash: ContentHash.gitBlobSHA1Hex([UInt8](data)),
                                         requiresLibraryUnlock: false)
        guard case .added(let copy) = await library.duplicate(source, contents: data) else { throw CancellationError() }
        return copy
    }

    // MARK: - Saving

    func testASavedEditReplacesTheTextAndKeepsTheId() async throws {
        let trial = FakeTrial()
        let first = await library(trial)
        let copy = try await duplicate(first)
        let later = await library(trial, now: 1_800_000_100)
        let outcome = await later.edit(copy.id, name: "My Alpha", text: edited, expectedSHA256: copy.sha256)
        guard case .saved(let saved) = outcome else { return XCTFail("\(outcome)") }

        let bytes = Array(edited.utf8)
        XCTAssertEqual(saved.id, copy.id)
        XCTAssertEqual(saved.name, "My Alpha")
        XCTAssertEqual(saved.sha256, ContentHash.sha256Hex(bytes))
        XCTAssertEqual(saved.blobHash, ContentHash.gitBlobSHA1Hex(bytes))
        XCTAssertEqual(saved.byteCount, bytes.count)
        XCTAssertEqual(saved.state, .playable)
        XCTAssertFalse(saved.provenOnScreen)
        XCTAssertEqual(saved.modifiedAt, Date(timeIntervalSince1970: 1_800_000_100))
        XCTAssertEqual(saved.importedAt, copy.importedAt)
        XCTAssertEqual(saved.duplicateOf, copy.duplicateOf, "the origin is history; it does not change")
        XCTAssertEqual(trial.calls.last, Data(bytes), "the edited text was tried before it was stored")
        XCTAssertEqual(outcome.message, "Saved “My Alpha”.")

        // Content-addressed: the new text is stored, the old one is gone, nothing else is there.
        XCTAssertEqual(Set(F.snapshot(directory).keys), ["/index.json", "/files/\(saved.sha256).milk"])
        let data = await later.data(for: copy.id)
        XCTAssertEqual(data, Data(bytes))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("edit.json").path))
        let relaunched = await library()
        let snapshot = await relaunched.snapshot
        XCTAssertEqual(snapshot.playable, [saved])
    }

    func testUnchangedTextAndNameSaveNothingAndANameOnlyChangeNeedsNoTrial() async throws {
        let trial = FakeTrial()
        let library = await library(trial)
        let copy = try await duplicate(library)
        let before = F.snapshot(directory)
        let calls = trial.calls.count

        let same = await library.edit(copy.id, name: copy.name, text: original, expectedSHA256: copy.sha256)
        XCTAssertEqual(same, .unchanged)
        let none = await library.edit(copy.id, name: "  \(copy.name) ", text: nil, expectedSHA256: copy.sha256)
        XCTAssertEqual(none, .unchanged)
        XCTAssertEqual(F.snapshot(directory), before)

        let renamed = await library.edit(copy.id, name: "Renamed\n/", text: nil, expectedSHA256: copy.sha256)
        guard case .saved(let saved) = renamed else { return XCTFail("\(renamed)") }
        XCTAssertEqual(saved.name, "Renamed _")
        XCTAssertEqual(saved.sha256, copy.sha256)
        XCTAssertEqual(trial.calls.count, calls, "a rename is not tried")
        XCTAssertEqual(saved.modifiedAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testEditingBackToTheOwnSourceTextIsAllowed() async throws {
        let library = await library()
        let copy = try await duplicate(library)
        guard case .saved(let changed) = await library.edit(copy.id, name: copy.name, text: edited, expectedSHA256: copy.sha256) else {
            return XCTFail()
        }
        let back = await library.edit(copy.id, name: copy.name, text: original, expectedSHA256: changed.sha256)
        guard case .saved(let restored) = back else { return XCTFail("\(back)") }
        XCTAssertEqual(restored.sha256, copy.sha256)
    }

    // MARK: - Refusals and failures change nothing (R12, S5)

    func testEveryRefusedOrFailingEditLeavesTheStoredPresetIdentical() async throws {
        let blockedText = F.preset(settings: ["zoom=9.9"])
        let library = await library(FakeTrial(), blocked: [ContentHash.gitBlobSHA1Hex(Array(blockedText.utf8))])
        let copy = try await duplicate(library)
        let otherText = F.preset(settings: ["zoom=0.7"])
        let other = try await importPreset(otherText, into: library)
        let before = F.snapshot(directory)

        let oversize = String(repeating: "x", count: PresetImportLimits.maxFileBytes + 1)
        let cases: [(String, String?, PresetEditRefusal)] = [
            ("   ", edited, .emptyName),
            (copy.name, "", .emptyText),
            (copy.name, " \n\t", .emptyText),
            (copy.name, oversize, .tooLarge),
            (copy.name, blockedText, .blocked),
            (copy.name, otherBuiltIn, .sameAsBuiltIn(name: "Gamma", pack: "Cream of the Crop")),
            (copy.name, otherText, .sameAsUserPreset(name: other.name)),
            (copy.name, "MILKDROP_PRESET_VERSION=201\nzoom=1\n", .invalid(reason: PresetQuarantineReason(.missingHeader).message)),
        ]
        for (index, item) in cases.enumerated() {
            let outcome = await library.edit(copy.id, name: item.0, text: item.1, expectedSHA256: copy.sha256)
            XCTAssertEqual(outcome, .refused(item.2), "\(index)")
            XCTAssertEqual(F.snapshot(directory), before, "\(index)")
            XCTAssertTrue(outcome.message.hasPrefix("Not saved. "), outcome.message)
        }
        let data = await library.data(for: copy.id)
        XCTAssertEqual(data, Data(original.utf8))
    }

    func testAFailingCheckKeepsTheLastGoodVersion() async throws {
        for (result, refusal) in [(PresetTrialResult.failed("Could not compile\nper-frame code"), PresetEditRefusal.checkFailed(message: "Could not compile per-frame code")),
                                  (.timedOut, .checkTimedOut),
                                  (.unavailable("background"), .checkUnavailable)] {
            directory = try F.tempDirectory(self).appendingPathComponent("UserPresets")
            let trial = FakeTrial()
            let library = await library(trial)
            let copy = try await duplicate(library)
            let before = F.snapshot(directory)
            let queued = FakeTrial([result])
            await library.setTrial(queued)
            let outcome = await library.edit(copy.id, name: "New", text: edited, expectedSHA256: copy.sha256)
            XCTAssertEqual(outcome, .refused(refusal))
            XCTAssertEqual(F.snapshot(directory), before)
            let snapshot = await library.snapshot
            XCTAssertEqual(snapshot.playable, [copy], "still playable, not quarantined")
        }

        // No engine at all: nothing is stored unchecked.
        directory = try F.tempDirectory(self).appendingPathComponent("UserPresets")
        let library = await library()
        let copy = try await duplicate(library)
        await library.setTrial(nil)
        let outcome = await library.edit(copy.id, name: copy.name, text: edited, expectedSHA256: copy.sha256)
        XCTAssertEqual(outcome, .refused(.checkUnavailable))
    }

    func testOnlyPlayablePresetsCanBeEdited() async throws {
        let library = await library(nil)   // no trial: imports wait
        let pending = try await importPreset(F.preset(settings: ["zoom=3"]), into: library)
        XCTAssertEqual(pending.state, .pending)
        let refused = await library.edit(pending.id, name: "x", text: edited, expectedSHA256: pending.sha256)
        XCTAssertEqual(refused, .refused(.notEditable))
        let text = await library.editorText(for: pending.id)
        XCTAssertNil(text)
        let unknown = await library.edit("user/unknown", name: "x", text: edited, expectedSHA256: pending.sha256)
        XCTAssertEqual(unknown, .refused(.notEditable))
        let bad = try await importPreset("not a preset\n", into: library)
        let quarantined = await library.edit(bad.id, name: "x", text: edited, expectedSHA256: bad.sha256)
        XCTAssertEqual(quarantined, .refused(.notEditable))
    }

    func testARecordSaveFailureRemovesTheNewText() async throws {
        let failing = LockedFlag()
        let library = await library(write: { data, url in
            if failing.value { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let copy = try await duplicate(library)
        let before = F.snapshot(directory)
        failing.value = true
        let outcome = await library.edit(copy.id, name: copy.name, text: edited, expectedSHA256: copy.sha256)
        XCTAssertEqual(outcome, .refused(.saveFailed))
        XCTAssertEqual(F.snapshot(directory), before)
        let data = await library.data(for: copy.id)
        XCTAssertEqual(data, Data(original.utf8))
    }

    func testAnEditOfAPresetThatChangedMeanwhileIsRefused() async throws {
        let trial = FakeTrial()
        let library = await library(trial)
        let copy = try await duplicate(library)
        let stale = await library.edit(copy.id, name: copy.name, text: edited, expectedSHA256: String(repeating: "0", count: 64))
        XCTAssertEqual(stale, .refused(.changedMeanwhile))

        // Removed while its edit was being tried.
        let racing = FakeTrial()
        racing.onRun = { [library] _ in Task { await library.remove(copy.id) } }
        racing.delay = .milliseconds(200)
        await library.setTrial(racing)
        let outcome = await library.edit(copy.id, name: copy.name, text: edited, expectedSHA256: copy.sha256)
        XCTAssertEqual(outcome, .refused(.changedMeanwhile))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("files/\(ContentHash.sha256Hex(Array(edited.utf8))).milk").path))
    }

    // MARK: - The app ends during an edit's check (R13)

    func testAnAppThatEndedDuringAnEditCheckKeepsTheLastGoodVersion() async throws {
        let library = await library()
        let copy = try await duplicate(library)
        let candidate = ContentHash.sha256Hex(Array(edited.utf8))
        let recorded = LockedFlag()
        let hanging = FakeTrial()
        hanging.hangs = true
        hanging.onRun = { [directory] _ in
            recorded.value = FileManager.default.fileExists(atPath: directory!.appendingPathComponent("edit.json").path)
        }
        await library.setTrial(hanging)
        let (id, name, text, sha) = (copy.id, copy.name, edited, copy.sha256)
        let task = Task { await library.edit(id, name: name, text: text, expectedSHA256: sha) }
        while hanging.calls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(recorded.value, "the record is on disk before the engine sees the text")
        let record = try Data(contentsOf: directory.appendingPathComponent("edit.json"))
        XCTAssertTrue(String(decoding: record, as: UTF8.self).contains(candidate))
        _ = task   // never returns: the app "died" during the check

        // "Relaunch" while the record is still there.
        let relaunched = await self.library()
        let snapshot = await relaunched.snapshot
        XCTAssertEqual(snapshot.playable.map(\.id), [copy.id], "not quarantined")
        let data = await relaunched.data(for: copy.id)
        XCTAssertEqual(data, Data(original.utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("edit.json").path))
        let notices = await relaunched.takeEditNotices()
        XCTAssertEqual(notices, ["Alpha copy"])
        let again = await relaunched.takeEditNotices()
        XCTAssertEqual(again, [])
        XCTAssertEqual(PresetEditRefusal.interruptedNotice(name: "Alpha copy"),
                       "An edit to “Alpha copy” was not saved because the app closed while checking it.")
    }

    // MARK: - Editor text

    func testEditorTextIsDecoded() async throws {
        let library = await library()
        let copy = try await duplicate(library)
        let text = await library.editorText(for: copy.id)
        XCTAssertEqual(text, PresetEditorText(text: original, isUTF8: true, sha256: copy.sha256))

        var latin1 = Array("// Caf".utf8) + [0xE9] + Array("\n".utf8)
        latin1 += Array(F.preset(settings: ["zoom=1.3"]).utf8)
        let imported = try await importPreset(Data(latin1), into: library)
        let decoded = await library.editorText(for: imported.id)
        XCTAssertEqual(decoded?.isUTF8, false)
        XCTAssertTrue(decoded?.text.hasPrefix("// Café\n") == true)
        // Saving writes UTF-8.
        let outcome = await library.edit(imported.id, name: imported.name, text: decoded!.text, expectedSHA256: imported.sha256)
        guard case .saved(let saved) = outcome else { return XCTFail("\(outcome)") }
        let stored = await library.data(for: saved.id)
        XCTAssertEqual(stored.map { String(decoding: $0, as: UTF8.self) }, decoded?.text)
    }

    func testEveryRefusalHasWords() {
        let refusals: [PresetEditRefusal] = [.notEditable, .needsUnlock, .emptyName, .emptyText, .tooLarge, .blocked,
                                             .sameAsBuiltIn(name: "A", pack: "P"), .sameAsUserPreset(name: "A"), .invalid(reason: "R."),
                                             .checkFailed(message: "m"), .checkTimedOut, .checkUnavailable, .libraryUnavailable,
                                             .saveFailed, .changedMeanwhile]
        for refusal in refusals {
            XCTAssertTrue(refusal.message.hasSuffix("."), refusal.message)
            XCTAssertEqual(PresetEditOutcome.refused(refusal).message, "Not saved. " + refusal.message)
        }
        XCTAssertEqual(PresetEditRefusal.checkFailed(message: "Could not compile").message,
                       "The visualizer could not load the edited preset (Could not compile). Your last saved version still plays.")
    }

    // MARK: - Helpers

    private func importPreset(_ text: String, into library: UserPresetLibrary) async throws -> UserPreset {
        try await importPreset(Data(text.utf8), into: library)
    }

    private func importPreset(_ data: Data, into library: UserPresetLibrary) async throws -> UserPreset {
        let url = try F.write(data, named: "Imported \(UUID().uuidString.prefix(4)).milk", in: folder)
        switch await library.importFile(at: url) {
        case .added(let p), .waiting(let p), .quarantined(let p): return p
        case .refused(let refusal):
            XCTFail("\(refusal)")
            throw CancellationError()
        }
    }
}
