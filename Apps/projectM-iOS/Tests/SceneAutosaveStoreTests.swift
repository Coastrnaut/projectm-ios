// SceneAutosaveStoreTests.swift — SCN-002-T05, T12: atomic saves, injected failures, crash leftovers
// and the load fallback (SCN-002-R5 to R7, R13; S2, S3; contracts/scene-autosave.md A1-A3). Each test
// uses its own temporary folder; no clock, no network.
import Foundation
import ParameterGraph
import SceneFormat
import TextLayer
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

/// Shared fixtures for the SCN-002 tests.
enum SceneAutosaveFixtures {
    static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SCN002-\(UUID().uuidString)", isDirectory: true)
    }

    static func inputs(visual: VisualChoice = .circularSpectrum, bars: Int = 64, message: String = "") -> SceneInputs {
        var text = TextOverlaySpec.default
        _ = text.setMessage(message)
        return SceneInputs(visual: visual, bars: bars, orientation: .vertical, spacing: 0.2, glowEnabled: false,
                           glowIntensity: 0.5, glowRadius: 0.02, glowThreshold: 0.7, text: text, photoID: nil, videoID: nil)
    }

    static let carry = SceneAutosaveCarry(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: SceneAutosaveCarry.defaultName)

    static func document(bars: Int, visual: VisualChoice = .circularSpectrum) -> SceneDocument {
        SceneAutosaveCapture.document(inputs(visual: visual, bars: bars), carry: carry, liveBindings: nil).document
    }

    static func registry() throws -> ParameterRegistry { try SceneArchiveService.appRegistry() }

    static func bars(_ document: SceneDocument?) -> String? {
        document?.parameters[VisualParameterIDs.circularSpectrumBarCount]?.enumCaseID
    }
}

final class SceneAutosaveStoreTests: XCTestCase {
    private typealias F = SceneAutosaveFixtures

    private func withStore(_ body: (SceneAutosaveStore, ParameterRegistry) throws -> Void) throws {
        let folder = F.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(SceneAutosaveStore(directory: folder), try F.registry())
    }

    func testSaveThenLoadRoundTrip() throws {
        try withStore { (store: SceneAutosaveStore, registry: ParameterRegistry) in
            let document = F.document(bars: 16)
            try store.save(document.encoded())
            let load = SceneAutosaveStore(directory: store.directory).load(registry: registry, assets: nil)
            XCTAssertEqual(load.source, .main)
            XCTAssertEqual(load.document, document)
            XCTAssertEqual(load.events, [])
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.temporary.path))
        }
    }

    /// S2: a failure (or a kill) at any step before the rename leaves the previous scene readable, and
    /// at least one complete committed scene exists after a failure at every step.
    func testInjectedFailureAtEveryStepKeepsACommittedScene() throws {
        // `keepOriginal` runs only when a migrated original is pending (SceneAutosaveMigrationTests, SCN-013).
        for failing in SceneAutosaveStep.allCases where failing != .keepOriginal {
            try withStore { (store: SceneAutosaveStore, registry: ParameterRegistry) in
                try store.save(F.document(bars: 16).encoded())
                try store.save(F.document(bars: 32).encoded())   // backup 16, main 32
                store.fault = { (step: SceneAutosaveStep) throws -> Void in
                    if step == failing { throw CocoaError(.fileWriteUnknown) }
                }
                if failing == .flushFolder {
                    XCTAssertNoThrow(try store.save(F.document(bars: 128).encoded()), "the rename stands")
                } else {
                    XCTAssertThrowsError(try store.save(F.document(bars: 128).encoded()), "\(failing)")
                }
                XCTAssertFalse(FileManager.default.fileExists(atPath: store.temporary.path), "\(failing): no temporary file left")
                let load = SceneAutosaveStore(directory: store.directory).load(registry: registry, assets: nil)
                XCTAssertEqual(load.source, .main, "\(failing)")
                let expected = failing == .flushFolder ? "128" : "32"
                XCTAssertEqual(F.bars(load.document), expected, "\(failing): the main file is whole")
            }
        }
    }

    /// A killed save leaves a partial temporary file: it is removed and never read.
    func testPartialTemporaryFileFromAKillIsIgnored() throws {
        try withStore { (store: SceneAutosaveStore, registry: ParameterRegistry) in
            try store.save(F.document(bars: 16).encoded())
            let partial = Array(F.document(bars: 32).encoded().prefix(40))
            XCTAssertTrue(FileManager.default.createFile(atPath: store.temporary.path, contents: Data(partial)))
            let load = SceneAutosaveStore(directory: store.directory).load(registry: registry, assets: nil)
            XCTAssertEqual(F.bars(load.document), "16")
            XCTAssertEqual(load.events, [])
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.temporary.path))
        }
    }

    /// S3: truncated, non-JSON and error-bearing main files fall back to the backup.
    func testDamagedMainFallsBackToBackup() throws {
        let damages: [(String, (Data) -> Data)] = [
            ("truncated", { (d: Data) -> Data in d.prefix(d.count / 2) }),
            ("not JSON", { (_: Data) -> Data in Data("not a scene".utf8) }),
            ("empty", { (_: Data) -> Data in Data() }),
            ("invalid scene ID", { (_: Data) -> Data in
                var bad = SceneAutosaveFixtures.document(bars: 64)
                bad.id = "not-a-uuid"
                return Data(bad.encoded())
            }),
        ]
        for (name, damage) in damages {
            try withStore { (store: SceneAutosaveStore, registry: ParameterRegistry) in
                try store.save(F.document(bars: 16).encoded())
                try store.save(F.document(bars: 32).encoded())
                let good = try Data(contentsOf: store.main)
                try damage(good).write(to: store.main)
                let load = SceneAutosaveStore(directory: store.directory).load(registry: registry, assets: nil)
                XCTAssertEqual(load.source, .backup, name)
                XCTAssertEqual(F.bars(load.document), "16", name)
                XCTAssertEqual(load.events.count, 2, "\(name): \(load.events)")
                XCTAssertEqual(load.events.last, .restoredFromBackup, name)
                if case .mainUnreadable = load.events.first {} else { XCTFail("\(name): \(load.events)") }
            }
        }
    }

    /// S3: both damaged → nothing restored, with events; a save afterwards writes a good file.
    func testBothDamagedRestoreNothing() throws {
        try withStore { (store: SceneAutosaveStore, registry: ParameterRegistry) in
            try store.save(F.document(bars: 16).encoded())
            try store.save(F.document(bars: 32).encoded())
            try Data("{".utf8).write(to: store.main)
            try Data().write(to: store.backup)
            let fresh = SceneAutosaveStore(directory: store.directory)
            let load = fresh.load(registry: registry, assets: nil)
            XCTAssertEqual(load.source, .none)
            XCTAssertNil(load.document)
            XCTAssertEqual(load.events.count, 3, "\(load.events)")
            XCTAssertEqual(load.events.last, .nothingRestored)
            try fresh.save(F.document(bars: 128).encoded())
            XCTAssertEqual(F.bars(SceneAutosaveStore(directory: store.directory).load(registry: registry, assets: nil).document), "128")
        }
    }

    /// A save after a fallback never links the damaged main file over the good backup.
    func testSaveAfterFallbackKeepsTheGoodBackup() throws {
        try withStore { (store: SceneAutosaveStore, registry: ParameterRegistry) in
            try store.save(F.document(bars: 16).encoded())
            try store.save(F.document(bars: 32).encoded())
            try Data("damaged".utf8).write(to: store.main)
            let fresh = SceneAutosaveStore(directory: store.directory)
            XCTAssertEqual(fresh.load(registry: registry, assets: nil).source, .backup)
            try fresh.save(F.document(bars: 128).encoded())
            let backup = try SceneDocument.decode([UInt8](Data(contentsOf: store.backup))).document
            XCTAssertEqual(F.bars(backup), "16", "the good backup stays")
            try fresh.save(F.document(bars: 64).encoded())
            let next = try SceneDocument.decode([UInt8](Data(contentsOf: store.backup))).document
            XCTAssertEqual(F.bars(next), "128", "once the main file is good it becomes the backup")
        }
    }

    /// A newer-version file is set aside once and never overwritten.
    func testNewerVersionFileIsSetAsideAndNeverOverwritten() throws {
        try withStore { (store: SceneAutosaveStore, registry: ParameterRegistry) in
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            let newer = Data("{\"format\":\"projectm-ios.scene\",\"version\":2,\"future\":true}".utf8)
            try newer.write(to: store.main)
            let load = store.load(registry: registry, assets: nil)
            XCTAssertEqual(load.source, .none)
            XCTAssertTrue(load.events.contains(.setAsideNewer(SceneAutosaveStore.mainName + SceneAutosaveStore.newerSuffix)), "\(load.events)")
            try store.save(F.document(bars: 16).encoded())
            try store.save(F.document(bars: 32).encoded())
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: store.main.path + SceneAutosaveStore.newerSuffix)), newer)
            XCTAssertEqual(F.bars(SceneAutosaveStore(directory: store.directory).load(registry: registry, assets: nil).document), "32")
        }
    }
}
