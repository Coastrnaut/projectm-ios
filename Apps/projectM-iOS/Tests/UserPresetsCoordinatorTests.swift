// PRE-012-T14, T21, T24, T27: imported presets through the app's coordinators
// (specs/008-pre-012-preset-import-validation; PRE-012-R14-R24, R28, R29; S4, S6). A synthetic
// built-in library, a real UserPresetLibrary in a temporary folder, a scripted trial and a fake
// renderer. The preset text is written here; none is a third-party file.
import AudioCore
import PresentationLifecycle
import PresetLibrary
import Rendering
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class UserPresetsCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var base: URL!
    private var announcements: [String] = []

    override func setUp() async throws {
        suite = "UserPresetsCoordinatorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        base = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("picked"), withIntermediateDirectories: true)
        announcements = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: - Fakes

    /// Records what the visible renderer was asked to load; throws for content marked as failing.
    final class FakeRenderer: VisualizerRenderer {
        let view = UIView()
        var reduceFlashing = false
        let supportsReduceFlashing = false
        var metrics = RenderMetrics.zero
        var presentedFrameCount = 0
        var loaded: [Preset] = []
        var failing: Set<Data> = []
        func attach(pcm: any NormalizedPCMReader) {}
        func setTextureSearchPaths(_ paths: [URL]) {}
        func pause() {}
        func resume() {}
        func setPreset(_ preset: Preset) async throws {
            if let data = preset.data, failing.contains(data) {
                throw NSError(domain: "PMEngineError", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not compile per-pixel code: syntax error"])
            }
            loaded.append(preset)
        }
    }

    final class ScriptedTrial: PresetTrialRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var queue: [PresetTrialResult]
        private var count = 0
        init(_ results: [PresetTrialResult] = []) { queue = results }
        var calls: Int { lock.withLock { count } }
        func run(_ contents: Data, timeout: Duration) async -> PresetTrialResult {
            lock.withLock {
                count += 1
                return queue.isEmpty ? .passed : queue.removeFirst()
            }
        }
    }

    private struct Rig {
        let presets: PresetCoordinator
        let userPresets: UserPresetsCoordinator
        let renderer: FakeRenderer
        let library: UserPresetLibrary
    }

    private static func record(_ id: String, _ name: String, _ source: String, hash: String = String(repeating: "0", count: 40)) -> [String: Any] {
        ["id": id, "name": name, "author": "A", "source": source, "folder": source == "included" ? [] : ["F"], "path": id, "hash": hash]
    }

    private func builtIn() throws -> PresetLibrary {
        let records = [Self.record("frontend-uwp/Alpha.milk", "Alpha", "included"), Self.record("frontend-uwp/Beta.milk", "Beta", "included"),
                       Self.record("cream-of-the-crop/F/c1.milk", "C1", "cream-of-the-crop",
                                   hash: ContentHash.gitBlobSHA1Hex(Array(text(zoom: "9.9").utf8)))]
        let packs: [[String: Any]] = [
            ["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "l", "presetCount": 2, "authors": [], "locked": false],
            ["id": "cream-of-the-crop", "title": "Cream of the Crop", "sourceURL": "u", "commit": "c", "license": "l", "presetCount": 1, "authors": [], "locked": true],
        ]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    /// A "launch": new coordinators over the same defaults and folders.
    private func launch(trial: ScriptedTrial? = ScriptedTrial(), provingPeriod: Duration = .seconds(60)) async throws -> Rig {
        let renderer = FakeRenderer()
        let loader = RendererPresetLoader()
        loader.renderer = renderer
        let presets = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                        settings: AppSettings(defaults: defaults, systemReduceMotion: false), loader: loader,
                                        collections: PresetCollectionStore(directory: base.appendingPathComponent("collections")))
        let library = UserPresetLibrary(directory: base.appendingPathComponent("UserPresets"))
        let userPresets = UserPresetsCoordinator(library: library, provingPeriod: provingPeriod) { [weak self] in self?.announcements.append($0) }
        userPresets.connect(presets: presets, loader: loader)
        await userPresets.load()
        let builtIn = try builtIn()
        await userPresets.prepare(library: builtIn, blockedHashes: [], knownTextures: [])
        loader.library = builtIn
        presets.attach(builtIn)
        await userPresets.rendererReady(trial: trial, presentedFrames: { [renderer] in renderer.presentedFrameCount })
        return Rig(presets: presets, userPresets: userPresets, renderer: renderer, library: library)
    }

    private func text(zoom: String = "1.01", perFrame: String = "rot = 0.02*sin(time);") -> String {
        ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "[preset00]", "fDecay=0.96", "zoom=\(zoom)", "per_frame_1=\(perFrame)", ""]
            .joined(separator: "\n")
    }

    private func pick(_ contents: String, named name: String) throws -> URL {
        let url = base.appendingPathComponent("picked").appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func indexed(_ name: String, in rig: Rig) throws -> IndexedPreset {
        try XCTUnwrap(rig.presets.library?.presets.first { $0.name == name }, name)
    }

    // MARK: - US1

    func testAnImportedPresetIsListedAndPlaysInItsOwnScope() async throws {
        let rig = try await launch()
        let contents = text()
        await rig.userPresets.importPicked(.success(try pick(contents, named: "Example Author - Sunrise.milk")))
        XCTAssertEqual(rig.userPresets.playable.map(\.name), ["Sunrise"])
        XCTAssertNil(rig.userPresets.resultMessage, "a clean add is announced, not alerted")
        XCTAssertEqual(announcements, ["Added “Sunrise” to My Presets."])
        XCTAssertFalse(rig.userPresets.isImporting)

        let sunrise = try indexed("Sunrise", in: rig)
        XCTAssertEqual(sunrise.source, PresetLibrary.userSource)
        XCTAssertEqual(sunrise.author, "Example Author")
        await rig.presets.choose(sunrise, from: .user)
        XCTAssertEqual(rig.presets.current, sunrise)
        XCTAssertEqual(rig.renderer.loaded.last?.data, Data(contents.utf8), "the stored copy is what the renderer loads")
        XCTAssertEqual(rig.presets.scopeLine, "My Presets · 1")
        XCTAssertFalse(rig.presets.purchaseRequested)

        await rig.userPresets.importPicked(.success(try pick(text(zoom: "1.02"), named: "Second.milk")))
        XCTAssertEqual(rig.presets.members.map(\.name), ["Second", "Sunrise"])
        await rig.presets.next()
        XCTAssertEqual(rig.presets.current?.name, "Second", "Next wraps inside My Presets")
        await rig.presets.previous()
        XCTAssertEqual(rig.presets.current?.name, "Sunrise")
        for _ in 0..<6 {
            await rig.presets.random()
            XCTAssertEqual(rig.presets.current?.source, PresetLibrary.userSource)
        }
        // R23: nothing about the purchase changed, and the built-in lists are what they were.
        XCTAssertFalse(rig.presets.unlocked)
        XCTAssertTrue(rig.presets.isLocked(try indexed("C1", in: rig)))
        XCTAssertEqual(rig.presets.library?.members(of: .all, unlocked: true, favorites: [], excluded: []).map(\.name), ["Alpha", "Beta", "C1"])
        XCTAssertEqual(rig.presets.library?.home.map(\.presetCount), try builtIn().home.map(\.presetCount))
    }

    func testFavoritesCollectionsAndTheScopeSurviveARelaunch() async throws {
        var rig = try await launch()
        await rig.userPresets.importPicked(.success(try pick(text(), named: "Mine.milk")))
        let mine = try indexed("Mine", in: rig)
        rig.presets.toggleFavorite(mine)
        let collection = try XCTUnwrap(rig.presets.createCollection(named: "Set"))
        XCTAssertEqual(rig.presets.addToCollection(mine, collection.id), .added)
        await rig.presets.choose(mine, from: .user)
        await rig.userPresets.abandonProving()   // the app leaves the screen before it ends (AppCoordinator.suspendVisualization)

        try FileManager.default.removeItem(at: base.appendingPathComponent("picked/Mine.milk"))   // the original is gone
        rig = try await launch()
        XCTAssertEqual(rig.presets.scope, .user)
        XCTAssertEqual(rig.presets.favoritesListing.map(\.name), ["Mine"], "attach must not drop a favorite that is a user preset")
        XCTAssertEqual(rig.presets.collectionListing(collection.id).map(\.name), ["Mine"])
        XCTAssertEqual(rig.presets.initialPreset?.name, "Mine")
        await rig.presets.select(try XCTUnwrap(rig.presets.initialPreset))
        XCTAssertEqual(rig.renderer.loaded.last?.data, Data(text().utf8))
    }

    func testRemovingAPresetKeepsWhatIsPlaying() async throws {
        let rig = try await launch()
        await rig.userPresets.importPicked(.success(try pick(text(), named: "Gone.milk")))
        let gone = try indexed("Gone", in: rig)
        await rig.presets.choose(gone, from: .user)
        XCTAssertTrue(rig.presets.addTag("Calm", to: gone))   // PRE-003-R7
        let record = try XCTUnwrap(rig.userPresets.playable.first)
        await rig.userPresets.remove(record)
        XCTAssertEqual(rig.userPresets.playable, [])
        XCTAssertEqual(rig.presets.tags(of: gone), [], "PRE-003-R7: removing a user preset prunes its tags")
        XCTAssertEqual(rig.presets.current, gone, "the playing preset keeps playing (spec Edge Cases)")
        XCTAssertEqual(rig.presets.scope, .included, "an empty My Presets is not kept as the scope")
        XCTAssertNil(rig.presets.library?.preset(id: gone.id))
        let data = await rig.library.data(for: gone.id)
        XCTAssertNil(data)
        XCTAssertEqual(rig.presets.library?.members(of: .included, unlocked: false, favorites: [], excluded: []).count, 2)
    }

    func testADuplicateOfABuiltInPresetIsRefusedAndUnlocksNothing() async throws {
        let rig = try await launch()
        await rig.userPresets.importPicked(.success(try pick(text(zoom: "9.9"), named: "copy of c1.milk")))
        XCTAssertEqual(rig.userPresets.resultMessage,
                       "“copy of c1.milk” was not imported. This preset is already in the library: “C1” in Cream of the Crop.")
        XCTAssertEqual(rig.userPresets.playable, [])
        XCTAssertEqual(rig.userPresets.quarantined, [])
        XCTAssertTrue(rig.presets.isLocked(try indexed("C1", in: rig)))
    }

    func testACancelledPickerChangesNothing() async throws {
        let rig = try await launch()
        await rig.userPresets.importPicked(.failure(CocoaError(.userCancelled)))
        XCTAssertNil(rig.userPresets.resultMessage)
        XCTAssertEqual(announcements, [])
        await rig.userPresets.importPicked(.failure(CocoaError(.fileReadNoPermission)))
        XCTAssertEqual(rig.userPresets.resultMessage, "The file could not be opened.")
    }

    // MARK: - US2

    func testAnInvalidFileIsQuarantinedAndReachesNoList() async throws {
        let rig = try await launch()
        await rig.presets.select(try indexed("Alpha", in: rig))
        let url = base.appendingPathComponent("picked/photo.milk")
        try Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]).write(to: url)
        await rig.userPresets.importPicked(.success(url))
        let message = "“photo.milk” was put in Quarantine. This file is not text. A Milkdrop preset is a plain text file."
        XCTAssertEqual(rig.userPresets.resultMessage, message)
        XCTAssertEqual(announcements, [message])
        XCTAssertEqual(rig.userPresets.quarantined.map(\.originalFileName), ["photo.milk"])
        XCTAssertEqual(rig.userPresets.playable, [])
        XCTAssertEqual(rig.presets.library?.userPresets, [])
        XCTAssertEqual(rig.presets.current?.name, "Alpha")
        XCTAssertEqual(rig.renderer.loaded.map(\.name), ["Alpha"], "nothing from the file reached the renderer")
        for scope in [PresetScope.user, .all, .included, .favorites] {
            XCTAssertFalse(rig.presets.library?.members(of: scope, unlocked: true, favorites: Set(rig.userPresets.quarantined.map(\.id)), excluded: [])
                .contains { $0.source == PresetLibrary.userSource } ?? true)
        }
        await rig.userPresets.remove(try XCTUnwrap(rig.userPresets.quarantined.first))
        XCTAssertEqual(rig.userPresets.quarantined, [])
    }

    func testAPresetTheEngineRejectsInTheTrialIsQuarantined() async throws {
        let rig = try await launch(trial: ScriptedTrial([.failed("Could not compile per-frame code: syntax error"), .timedOut]))
        await rig.presets.select(try indexed("Alpha", in: rig))
        await rig.userPresets.importPicked(.success(try pick(text(perFrame: "rot = = 3;"), named: "Bad.milk")))
        XCTAssertEqual(rig.userPresets.resultMessage,
                       "“Bad.milk” was put in Quarantine. The visualizer could not load this preset. (Could not compile per-frame code: syntax error)")
        await rig.userPresets.importPicked(.success(try pick(text(zoom: "3"), named: "Slow.milk")))
        XCTAssertEqual(rig.userPresets.quarantined.map(\.quarantine?.kind), [.timedOut, .engineRejected])
        XCTAssertEqual(rig.userPresets.playable, [])
        XCTAssertEqual(rig.renderer.loaded.map(\.name), ["Alpha"])
        XCTAssertEqual(rig.presets.current?.name, "Alpha")
    }

    func testWithoutATrialAPresetWaitsAndIsCheckedWhenTheRendererIsReady() async throws {
        let rig = try await launch(trial: nil)
        await rig.userPresets.importPicked(.success(try pick(text(), named: "Later.milk")))
        XCTAssertEqual(rig.userPresets.resultMessage, "“Later” was saved and will be checked before it can play.")
        XCTAssertEqual(rig.userPresets.pending.map(\.name), ["Later"])
        XCTAssertEqual(rig.presets.library?.userPresets, [], "not playable before it was tried (R14)")
        let trial = ScriptedTrial()
        await rig.userPresets.rendererReady(trial: trial, presentedFrames: { 0 })
        XCTAssertEqual(trial.calls, 1)
        XCTAssertEqual(rig.userPresets.pending, [])
        XCTAssertEqual(rig.presets.library?.userPresets.map(\.name), ["Later"])
    }

    // MARK: - US3

    func testAUserPresetThatFailsOnScreenIsQuarantinedAndThePreviousOneStays() async throws {
        let rig = try await launch()
        let alpha = try indexed("Alpha", in: rig)
        await rig.presets.select(alpha)
        let contents = text(zoom: "1.5")
        await rig.userPresets.importPicked(.success(try pick(contents, named: "Late failure.milk")))
        rig.renderer.failing = [Data(contents.utf8)]
        await rig.presets.choose(try indexed("Late failure", in: rig), from: .user)

        XCTAssertEqual(rig.presets.current, alpha, "FR-045: the previous preset keeps playing")
        XCTAssertEqual(rig.presets.failureMessage, UserPresetText.onScreenFailure)
        XCTAssertEqual(rig.userPresets.playable, [])
        XCTAssertEqual(rig.userPresets.quarantined.first?.quarantine,
                       PresetQuarantineReason(.failedOnScreen, detail: "Could not compile per-pixel code: syntax error"))
        XCTAssertFalse(rig.presets.members.contains { $0.source == PresetLibrary.userSource })
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("UserPresets/proving.json").path))
        // It never comes back, in this launch or the next.
        let again = try await launch()
        XCTAssertEqual(again.presets.library?.userPresets, [])
    }

    func testAnUnprovenPresetIsProvenAfterItDrewForTheProvingPeriod() async throws {
        let rig = try await launch(provingPeriod: .milliseconds(150))
        await rig.userPresets.importPicked(.success(try pick(text(), named: "Prove.milk")))
        let record = base.appendingPathComponent("UserPresets/proving.json").path
        await rig.presets.choose(try indexed("Prove", in: rig), from: .user)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record), "the record is there while the preset is first shown (R18)")
        rig.renderer.presentedFrameCount += 120
        for _ in 0..<200 where rig.userPresets.playable.first?.provenOnScreen != true { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(rig.userPresets.playable.map(\.provenOnScreen), [true])
        XCTAssertFalse(FileManager.default.fileExists(atPath: record))
        // A proven preset is loaded without a record.
        await rig.presets.select(try indexed("Alpha", in: rig))
        await rig.presets.choose(try indexed("Prove", in: rig), from: .user)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record))
    }

    func testProvingEndsWithoutProofWhenThePresetStopsBeingShownOrDrawsNothing() async throws {
        let rig = try await launch(provingPeriod: .milliseconds(150))
        await rig.userPresets.importPicked(.success(try pick(text(), named: "Brief.milk")))
        let record = base.appendingPathComponent("UserPresets/proving.json").path
        let brief = try indexed("Brief", in: rig)

        await rig.presets.choose(brief, from: .user)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record))
        await rig.presets.select(try indexed("Alpha", in: rig))          // switched away at once
        XCTAssertFalse(FileManager.default.fileExists(atPath: record))
        XCTAssertEqual(rig.userPresets.playable.map(\.provenOnScreen), [false])

        await rig.presets.choose(brief, from: .user)                      // shown, but no frame is presented (paused)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record))
        XCTAssertEqual(rig.userPresets.playable.map(\.provenOnScreen), [false])

        await rig.presets.choose(brief, from: .user)                      // chosen again, then the app leaves the screen
        XCTAssertTrue(FileManager.default.fileExists(atPath: record))
        await rig.userPresets.abandonProving()
        XCTAssertFalse(FileManager.default.fileExists(atPath: record))
    }

    func testAPresetThatWasOnScreenWhenTheAppEndedIsNotTheInitialPreset() async throws {
        var rig = try await launch()
        await rig.userPresets.importPicked(.success(try pick(text(), named: "Crasher.milk")))
        let crasher = try indexed("Crasher", in: rig)
        await rig.presets.choose(crasher, from: .user)                    // last preset = Crasher, scope = My Presets, record on disk
        XCTAssertTrue(FileManager.default.fileExists(atPath: base.appendingPathComponent("UserPresets/proving.json").path))

        rig = try await launch()                                          // the app "died" and starts again
        XCTAssertEqual(rig.userPresets.quarantined.map(\.quarantine?.kind), [.interruptedOnScreen])
        XCTAssertEqual(rig.presets.library?.userPresets, [])
        XCTAssertEqual(rig.presets.scope, .included, "the stored scope, My Presets, is empty now and falls back")
        XCTAssertEqual(rig.presets.initialPreset?.name, "Alpha", "the app starts with another playable preset")
        await rig.presets.next()
        XCTAssertEqual(rig.renderer.loaded.map(\.name), ["Alpha"])
    }

    // MARK: - Labels (R29)

    func testRowLabels() {
        XCTAssertEqual(UserPresetsCoordinator.myPresetsRowLabel(count: 1), "My Presets, 1 preset")
        XCTAssertEqual(UserPresetsCoordinator.myPresetsRowLabel(count: 12), "My Presets, 12 presets")
        XCTAssertEqual(UserPresetsCoordinator.quarantineRowLabel(count: 0), "Quarantine, 0 files")
        XCTAssertEqual(UserPresetsCoordinator.quarantineRowLabel(count: 1), "Quarantine, 1 file")
        XCTAssertEqual(UserPresetsCoordinator.quarantinedFileLabel(fileName: "photo.milk", reason: "This file is not text."),
                       "photo.milk, not playable. This file is not text.")
        XCTAssertEqual(UserPresetsCoordinator.pendingLabel(name: "Later"), "Later, waiting to be checked")
        XCTAssertEqual(UserPresetsCoordinator.byteCountText(1_536), "1,536 bytes")
    }
}
