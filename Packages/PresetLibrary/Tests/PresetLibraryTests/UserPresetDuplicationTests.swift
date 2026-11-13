// PRE-015-T06, T16: duplicating a built-in preset into the user library, and the purchase
// boundary for copies (PRE-015-R2-R8, R20; S1, S4). The "bundle" is a read-only temporary folder
// holding a synthetic preset written for this repository.
import XCTest
@testable import PresetLibrary

final class UserPresetDuplicationTests: XCTestCase {
    private typealias F = UserPresetFixtures
    private var bundle: URL!
    private var directory: URL!
    private var bundledFile: URL!

    override func setUpWithError() throws {
        bundle = try F.tempDirectory(self).appendingPathComponent("App.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        bundledFile = try F.write(F.valid, named: "Alpha.milk", in: bundle)
        // Read-only like an installed app bundle: any write attempt would fail loudly.
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: bundledFile.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bundle.path)
        addTeardownBlock { [bundle] in
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundle!.path)
        }
        directory = try F.tempDirectory(self).appendingPathComponent("UserPresets")
    }

    private var bundledBytes: Data { (try? Data(contentsOf: bundledFile)) ?? Data() }

    private func source(_ name: String = "Alpha", bytes: Data? = nil, packID: String = "included", locked: Bool = false) -> BundledPresetSource {
        let data = bytes ?? bundledBytes
        return BundledPresetSource(id: "\(packID)/\(name).milk", name: name, author: "Example Author", fileName: "\(name).milk",
                                   packID: packID, packTitle: packID == "included" ? "Included" : "Cream of the Crop",
                                   licenseStatement: "Assumed public domain by the projectM team.",
                                   blobHash: ContentHash.gitBlobSHA1Hex([UInt8](data)), requiresLibraryUnlock: locked)
    }

    private func library(_ trial: FakeTrial? = FakeTrial(), unlocked: Bool = false, blocked: Set<String> = [],
                         write: (@Sendable (Data, URL) throws -> Void)? = nil) async -> UserPresetLibrary {
        let library = UserPresetLibrary(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) }, write: write)
        _ = await library.load()
        let builtIn = [ContentHash.gitBlobSHA1Hex([UInt8](bundledBytes)): PresetImportContext.BuiltIn(name: "Alpha", pack: "Included")]
        await library.setContext(PresetImportContext(builtIn: builtIn, blockedHashes: blocked, knownTextures: []))
        await library.setTrial(trial)
        await library.setLibraryUnlocked(unlocked)
        return library
    }

    private func copy(_ outcome: PresetDuplicateOutcome, file: StaticString = #filePath, line: UInt = #line) throws -> UserPreset {
        switch outcome {
        case .added(let preset), .waiting(let preset), .quarantined(let preset): return preset
        case .refused(let refusal):
            XCTFail("refused: \(refusal)", file: file, line: line)
            throw CancellationError()
        }
    }

    private func bundleState() throws -> (Data, String, Date) {
        let attributes = try FileManager.default.attributesOfItem(atPath: bundledFile.path)
        return (bundledBytes, ContentHash.gitBlobSHA1Hex([UInt8](bundledBytes)), try XCTUnwrap(attributes[.modificationDate] as? Date))
    }

    // MARK: - US1

    func testADuplicateIsAByteIdenticalCopyWithItsOwnIdAndOrigin() async throws {
        let before = try bundleState()
        let library = await library()
        let outcome = await library.duplicate(source(), contents: bundledBytes)
        guard case .added(let added) = outcome else { return XCTFail("\(outcome)") }

        XCTAssertTrue(added.id.hasPrefix("user/"))
        XCTAssertNotEqual(added.id, "included/Alpha.milk")
        XCTAssertEqual(added.name, "Alpha copy")
        XCTAssertEqual(added.author, "Example Author")
        XCTAssertEqual(added.originalFileName, "Alpha.milk")
        XCTAssertEqual(added.state, .playable)
        XCTAssertEqual(added.sha256, ContentHash.sha256Hex([UInt8](bundledBytes)))
        XCTAssertEqual(added.blobHash, before.1)
        XCTAssertEqual(added.license.origin, .bundledDuplicate)
        XCTAssertFalse(added.license.rightsVerified)
        XCTAssertFalse(added.license.authorFromFileName)
        XCTAssertNil(added.modifiedAt)
        XCTAssertEqual(added.duplicateOf, PresetDuplicateOrigin(
            presetID: "included/Alpha.milk", name: "Alpha", packID: "included", packTitle: "Included",
            sha256: ContentHash.sha256Hex([UInt8](bundledBytes)), blobHash: before.1,
            licenseStatement: "Assumed public domain by the projectM team.", requiresLibraryUnlock: false))
        XCTAssertEqual(outcome.message(sourceName: "Alpha"), "Duplicated “Alpha” to My Presets as “Alpha copy”.")
        XCTAssertFalse(outcome.needsAlert)

        // The stored copy is the bundled bytes; the bundled file is untouched.
        let stored = try Data(contentsOf: directory.appendingPathComponent("files/\(added.sha256).milk"))
        XCTAssertEqual(stored, before.0)
        let data = await library.data(for: added.id)
        XCTAssertEqual(data, before.0)
        let after = try bundleState()
        XCTAssertEqual(after.0, before.0)
        XCTAssertEqual(after.1, before.1)
        XCTAssertEqual(after.2, before.2)

        // A relaunch reads it back as a copy.
        let relaunched = await self.library()
        let snapshot = await relaunched.snapshot
        XCTAssertEqual(snapshot.playable, [added])
    }

    func testTheCopyIsTriedLikeAnImport() async throws {
        let quarantining = FakeTrial([.failed("Could not compile per-pixel code")])
        let quarantined = await library(quarantining).duplicate(source(), contents: bundledBytes)
        guard case .quarantined(let preset) = quarantined else { return XCTFail("\(quarantined)") }
        XCTAssertEqual(preset.quarantine?.kind, .engineRejected)
        XCTAssertEqual(quarantining.calls, [bundledBytes])
        XCTAssertTrue(quarantined.message(sourceName: "Alpha").hasPrefix("“Alpha copy” was put in Quarantine."))
        XCTAssertTrue(quarantined.needsAlert)

        directory = try F.tempDirectory(self).appendingPathComponent("UserPresets")
        let waiting = await library(nil).duplicate(source(), contents: bundledBytes)
        guard case .waiting(let pending) = waiting else { return XCTFail("\(waiting)") }
        XCTAssertEqual(pending.state, .pending)
        XCTAssertEqual(waiting.message(sourceName: "Alpha"), "“Alpha copy” was saved and will be checked before it can play.")
    }

    func testRefusalsStoreNothing() async throws {
        let invalid = Data(F.preset(comp: ["shader_body", "{", "ret = tex2D(sampler_main, uv).xyz;"]).utf8)   // brace never closed
        let cases: [(BundledPresetSource, Data, PresetDuplicateRefusal)] = [
            (source(), Data(F.preset(settings: ["zoom=2.0"]).utf8), .sourceMismatch),            // bytes are not the indexed preset
            (source(bytes: invalid), invalid, .invalid(reason: PresetQuarantineReason(.incompleteShader, detail: "comp_").message)),
            (source(bytes: Data()), Data(), .sourceMismatch),
        ]
        for (index, item) in cases.enumerated() {
            directory = try F.tempDirectory(self).appendingPathComponent("UserPresets")
            let trial = FakeTrial()
            let outcome = await library(trial).duplicate(item.0, contents: item.1)
            XCTAssertEqual(outcome, .refused(item.2), "\(index)")
            XCTAssertEqual(F.snapshot(directory), [:], "\(index)")
            XCTAssertTrue(trial.calls.isEmpty, "\(index)")
        }

        directory = try F.tempDirectory(self).appendingPathComponent("UserPresets")
        let blocked = await library(blocked: [ContentHash.gitBlobSHA1Hex([UInt8](bundledBytes))]).duplicate(source(), contents: bundledBytes)
        XCTAssertEqual(blocked, .refused(.blocked))
        XCTAssertEqual(F.snapshot(directory), [:])
        XCTAssertEqual(blocked.message(sourceName: "Alpha"),
                       "“Alpha” was not duplicated. This preset was removed from the library at its author's request.")
    }

    func testAnUnchangedCopyIsNotMadeTwice() async throws {
        let library = await library()
        let first = try copy(await library.duplicate(source(), contents: bundledBytes))
        let snapshot = F.snapshot(directory)
        let again = await library.duplicate(source(), contents: bundledBytes)
        XCTAssertEqual(again, .refused(.alreadyCopied(name: first.name)))
        XCTAssertEqual(again.message(sourceName: "Alpha"), "“Alpha” was not duplicated. Its unchanged copy is already in My Presets as “Alpha copy”.")
        XCTAssertEqual(F.snapshot(directory), snapshot)

        // Same text in Quarantine.
        _ = await library.quarantineOnScreenFailure(first.id, message: "boom")
        let quarantined = await library.duplicate(source(), contents: bundledBytes)
        guard case .refused(.alreadyInQuarantine(let name, _)) = quarantined else { return XCTFail("\(quarantined)") }
        XCTAssertEqual(name, "Alpha copy")
    }

    func testCopyNamesAreNumbered() {
        XCTAssertEqual(UserPresetName.copyName(of: "Alpha", taken: []), "Alpha copy")
        XCTAssertEqual(UserPresetName.copyName(of: "Alpha", taken: ["alpha COPY"]), "Alpha copy 2")
        XCTAssertEqual(UserPresetName.copyName(of: "Alpha", taken: ["Alpha copy", "Alpha copy 2", "Alpha copy 4"]), "Alpha copy 3")
        let long = String(repeating: "n", count: 200)
        let named = UserPresetName.copyName(of: long, taken: [])
        XCTAssertEqual(named.count, PresetImportLimits.maxNameCharacters)
        XCTAssertTrue(named.hasSuffix(" copy"))
        let second = UserPresetName.copyName(of: long, taken: [named])
        XCTAssertEqual(second.count, PresetImportLimits.maxNameCharacters)
        XCTAssertTrue(second.hasSuffix(" copy 2"))
    }

    func testASecondCopyAfterAnEditIsNumbered() async throws {
        let library = await library()
        let first = try copy(await library.duplicate(source(), contents: bundledBytes))
        let edited = await library.edit(first.id, name: first.name, text: F.preset(settings: ["zoom=1.2"]), expectedSHA256: first.sha256)
        guard case .saved = edited else { return XCTFail("\(edited)") }
        let second = try copy(await library.duplicate(source(), contents: bundledBytes))
        XCTAssertEqual(second.name, "Alpha copy 2")
        XCTAssertNotEqual(second.id, first.id)
    }

    func testLimitsAndUnavailableAndSaveFailure() async throws {
        // Full.
        let library = await library()
        for n in 0..<PresetImportLimits.maxUserPresets {
            let text = F.preset(settings: ["zoom=\(n)"])
            _ = await library.duplicate(source("P\(n)", bytes: Data(text.utf8)), contents: Data(text.utf8))
        }
        let full = await library.duplicate(source(), contents: bundledBytes)
        XCTAssertEqual(full, .refused(.libraryFull))

        // A record from a newer app version.
        directory = try F.tempDirectory(self).appendingPathComponent("UserPresets")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":9,"presets":[]}"#.utf8).write(to: directory.appendingPathComponent("index.json"))
        let newer = await self.library().duplicate(source(), contents: bundledBytes)
        XCTAssertEqual(newer, .refused(.libraryUnavailable))

        // The record cannot be saved: nothing is left behind.
        directory = try F.tempDirectory(self).appendingPathComponent("UserPresets")
        struct Failure: Error {}
        let failing = await self.library(write: { _, _ in throw Failure() })
        let failed = await failing.duplicate(source(), contents: bundledBytes)
        XCTAssertEqual(failed, .refused(.saveFailed))
        XCTAssertEqual(F.snapshot(directory), [:])
    }

    func testEveryRefusalHasWords() {
        let refusals: [PresetDuplicateRefusal] = [.locked, .notPlayable, .sourceMismatch, .blocked, .alreadyCopied(name: "A"),
                                                  .alreadyInQuarantine(name: "A", reason: "R."), .invalid(reason: "R."),
                                                  .libraryFull, .libraryUnavailable, .saveFailed]
        for refusal in refusals {
            XCTAssertFalse(refusal.message.isEmpty)
            XCTAssertTrue(refusal.message.hasSuffix("."), refusal.message)
        }
        XCTAssertEqual(PresetDuplicateRefusal.locked.message, "It is in a pack that needs the full library.")
    }

    // MARK: - US3: the purchase boundary (T16)

    func testALockedPresetCannotBeDuplicatedWithoutTheUnlock() async throws {
        let trial = FakeTrial()
        let library = await library(trial, unlocked: false)
        let outcome = await library.duplicate(source(packID: "cream-of-the-crop", locked: true), contents: bundledBytes)
        XCTAssertEqual(outcome, .refused(.locked))
        XCTAssertEqual(F.snapshot(directory), [:])
        XCTAssertTrue(trial.calls.isEmpty)
    }

    func testCopiesOfLockedPacksAreHeldWhileTheEntitlementIsAbsent() async throws {
        let trial = FakeTrial()
        let library = await library(trial, unlocked: true)
        let locked = try copy(await library.duplicate(source(packID: "cream-of-the-crop", locked: true), contents: bundledBytes))
        XCTAssertEqual(locked.duplicateOf?.requiresLibraryUnlock, true)
        let includedText = F.preset(settings: ["zoom=1.5"])
        let free = try copy(await library.duplicate(source("Beta", bytes: Data(includedText.utf8)), contents: Data(includedText.utf8)))
        let files = F.snapshot(directory)

        await library.setLibraryUnlocked(false)   // refund or revocation
        var snapshot = await library.snapshot
        XCTAssertEqual(snapshot.playable.map(\.id), [free.id])
        XCTAssertEqual(snapshot.needsUnlock.map(\.id), [locked.id])
        let lockedData = await library.data(for: locked.id)
        XCTAssertNil(lockedData)
        let lockedText = await library.editorText(for: locked.id)
        XCTAssertNil(lockedText)
        let edit = await library.edit(locked.id, name: "X", text: F.preset(settings: ["zoom=3"]), expectedSHA256: locked.sha256)
        XCTAssertEqual(edit, .refused(.needsUnlock))
        let freeData = await library.data(for: free.id)
        XCTAssertNotNil(freeData)
        XCTAssertEqual(F.snapshot(directory), files, "nothing is deleted or rewritten")

        // A relaunch without the entitlement keeps holding it.
        let relaunched = await self.library(trial, unlocked: false)
        snapshot = await relaunched.snapshot
        XCTAssertEqual(snapshot.needsUnlock.map(\.id), [locked.id])

        await library.setLibraryUnlocked(true)   // restored
        snapshot = await library.snapshot
        XCTAssertEqual(Set(snapshot.playable.map(\.id)), [free.id, locked.id])
        XCTAssertEqual(snapshot.needsUnlock, [])
        let restored = await library.data(for: locked.id)
        XCTAssertEqual(restored, bundledBytes)
    }

    func testAHeldPendingCopyIsNotTried() async throws {
        let library = await library(nil, unlocked: true)
        let pending = try copy(await library.duplicate(source(packID: "cream-of-the-crop", locked: true), contents: bundledBytes))
        XCTAssertEqual(pending.state, .pending)
        await library.setLibraryUnlocked(false)
        let trial = FakeTrial()
        await library.setTrial(trial)
        await library.runPendingTrials()
        XCTAssertTrue(trial.calls.isEmpty)
        let held = await library.snapshot
        XCTAssertEqual(held.needsUnlock.map(\.id), [pending.id])
        XCTAssertEqual(held.pending, [])
        await library.setLibraryUnlocked(true)
        await library.runPendingTrials()
        XCTAssertEqual(trial.calls, [bundledBytes])
    }
}
