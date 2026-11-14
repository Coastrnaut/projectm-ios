// PresetAuditionAcceptanceTests.swift — PRE-010-T06, T08, T09 (specs/168-pre-010-quick-audition;
// PRE-010-S1-S3): the roadmap acceptance "Cancel restores original preset and its navigation scope", in
// the app. A is chosen from "Tagged: Calm" (real tag store), B and C are previewed, Cancel: A is current
// and the last preset loaded, the scope is "Tagged: Calm", every key of the UserDefaults suite is
// byte-identical (`lastPresetID`, the stored scope, PRE-006's history), the history has no B or C entry
// (history on, injected clock, more than 3 s per preview), a SCN-010 history over the same settings has
// no undo step, and SCN-002's canonical scene bytes are unchanged. Also Keep, a committed selection
// during a preview, failed previews and where Preview is offered. Fake loader; no wall-clock assertions.
import Foundation
import PresetLibrary
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class PresetAuditionAcceptanceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!
    private var clock: Double = 1_000
    private var scheduled: [(at: Double, work: @MainActor () -> Void)] = []
    private var spoken: [String] = []

    override func setUp() async throws {
        suite = "PresetAuditionAcceptanceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.set(true, forKey: RecentPresetsStore.enabledKey)   // history on: the strictest case
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        clock = 1_000
        scheduled = []
        spoken = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    final class FakeLoader: PresetLoading {
        var failing: Set<String> = []
        /// Successful loads, in order (what the screen showed).
        var loaded: [String] = []
        var prewarms = 0
        func load(_ preset: IndexedPreset) async throws {
            if failing.contains(preset.name) { throw NSError(domain: "test", code: 1) }
            loaded.append(preset.name)
        }
        func prewarm(_ presets: [IndexedPreset]) { prewarms += 1 }
    }

    private static func record(_ name: String, source: String = "included", flash: [String]? = nil) -> [String: Any] {
        let id = source == "included" ? "frontend-uwp/\(name).milk" : "\(source)/F/\(name).milk"
        var record: [String: Any] = ["id": id, "name": name, "author": "A", "source": source,
                                     "folder": source == "included" ? [String]() : ["F"], "path": id,
                                     "hash": String(repeating: "0", count: 40)]
        if let flash { record["flash"] = flash }
        return record
    }

    /// Included: A, B, C, D, E (E may flash). Locked pack cream-of-the-crop: L.
    private func makeLibrary() throws -> PresetLibrary {
        let records: [[String: Any]] = ["A", "B", "C", "D"].map { (name: String) -> [String: Any] in Self.record(name) }
            + [Self.record("E", flash: ["strobe"]), Self.record("L", source: "cream-of-the-crop")]
        let packs: [[String: Any]] = [
            ["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "l", "presetCount": 5,
             "authors": [String](), "locked": false],
            ["id": "cream-of-the-crop", "title": "Cream of the Crop", "sourceURL": "u", "commit": "c", "license": "l",
             "presetCount": 1, "authors": [String](), "locked": true],
        ]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    private func makeCoordinator(_ loader: FakeLoader, settings: AppSettings? = nil) throws -> PresetCoordinator {
        let coordinator = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                            settings: settings ?? AppSettings(defaults: defaults, systemReduceMotion: false),
                                            loader: loader, collections: PresetCollectionStore(directory: directory),
                                            tags: PresetTagStore(directory: directory))
        coordinator.attach(try makeLibrary())
        let recent = RecentPresetsCoordinator(store: RecentPresetsStore(defaults: defaults),
                                              now: { [unowned self] () -> Double in self.clock },
                                              schedule: { [unowned self] (delay: Double, work: @escaping @MainActor () -> Void) in
                                                  self.scheduled.append((at: self.clock + delay, work: work))
                                              })
        coordinator.recent = recent
        coordinator.announceLibrary = { [unowned self] (text: String) in self.spoken.append(text) }
        return coordinator
    }

    private func preset(_ name: String, _ coordinator: PresetCoordinator) throws -> IndexedPreset {
        try XCTUnwrap(coordinator.library?.presets.first { $0.name == name }, name)
    }

    private func advance(_ seconds: Double) {
        clock += seconds
        let due = scheduled.filter { (item: (at: Double, work: @MainActor () -> Void)) -> Bool in item.at <= clock }
        scheduled.removeAll { (item: (at: Double, work: @MainActor () -> Void)) -> Bool in item.at <= clock }
        for item in due { item.work() }
    }

    /// Every key of the suite with its value's binary plist bytes.
    private func storedBytes() throws -> [String: Data] {
        var result: [String: Data] = [:]
        for (key, value) in defaults.persistentDomain(forName: suite) ?? [:] {
            result[key] = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        }
        return result
    }

    /// The scene inputs as AppCoordinator builds them from these settings (the parts a preset could touch).
    private func sceneInputs(_ settings: AppSettings) -> SceneInputs {
        SceneInputs(visual: SceneAutosaveCapture.recordedVisual(settings.visual, beforeCamera: settings.visualBeforeCamera),
                    bars: settings.circularSpectrumBars, orientation: settings.linearSpectrumOrientation,
                    spacing: settings.linearSpectrumSpacing, glowEnabled: settings.glowEnabled,
                    glowIntensity: settings.glowIntensity, glowRadius: settings.glowRadius, glowThreshold: settings.glowThreshold,
                    text: TextOverlaySpec.default, photoID: nil, videoID: nil)
    }

    private func sceneBytes(_ settings: AppSettings) -> [UInt8] {
        SceneAutosaveCapture.document(sceneInputs(settings), carry: SceneAutosaveFixtures.carry, liveBindings: nil).document.encoded()
    }

    // MARK: - S1: the roadmap acceptance

    func testCancelRestoresTheOriginalPresetAndItsTaggedScopeAndStoresNothing() async throws {
        let loader = FakeLoader()
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let coordinator = try makeCoordinator(loader, settings: settings)
        for name in ["A", "B", "C"] { XCTAssertTrue(coordinator.addTag("Calm", to: try preset(name, coordinator))) }
        coordinator.toggleTag("Calm")
        let calm = PresetScope.tagged(coordinator.activeTags)
        await coordinator.choose(try preset("A", coordinator), from: calm)
        advance(3)   // A is recorded by PRE-006
        let recent = try XCTUnwrap(coordinator.recent)
        XCTAssertEqual(recent.ids, ["frontend-uwp/A.milk"])
        let history = SceneHistoryCoordinator()
        history.inputs = { [unowned self] () -> SceneInputs in self.sceneInputs(settings) }
        history.carry = { () -> SceneAutosaveCarry in SceneAutosaveFixtures.carry }
        history.start(observing: false)
        let storedBefore = try storedBytes()
        let sceneBefore = sceneBytes(settings)
        let scopeLineBefore = coordinator.scopeLine
        XCTAssertTrue(scopeLineBefore.hasPrefix("Tagged"), scopeLineBefore)
        let prewarmsBefore = loader.prewarms
        spoken = []

        await coordinator.preview(try preset("B", coordinator), from: calm)
        XCTAssertEqual(coordinator.audition?.showing?.name, "B")
        XCTAssertEqual(coordinator.current?.name, "A", "the controls still name the original")
        XCTAssertTrue(coordinator.rowLabel(try preset("B", coordinator), locked: false).hasSuffix(PresetCoordinator.previewingLabel))
        advance(5)
        await coordinator.preview(try preset("C", coordinator), from: calm)
        XCTAssertEqual(coordinator.onScreen?.name, "C")
        advance(5)
        await coordinator.cancelAudition()
        advance(5)
        history.capture()

        XCTAssertEqual(coordinator.current?.name, "A")
        XCTAssertEqual(loader.loaded, ["A", "B", "C", "A"], "A was loaded again last")
        XCTAssertNil(coordinator.audition)
        XCTAssertEqual(coordinator.scope, calm)
        XCTAssertEqual(coordinator.scopeLine, scopeLineBefore)
        XCTAssertEqual(try storedBytes(), storedBefore, "lastPresetID, the stored scope and the history are byte-identical")
        XCTAssertEqual(recent.ids, ["frontend-uwp/A.milk"], "no history entry for B or C")
        XCTAssertFalse(history.canUndo, "no undo step")
        XCTAssertEqual(sceneBytes(settings), sceneBefore, "the autosaved scene is unchanged")
        XCTAssertEqual(loader.prewarms, prewarmsBefore, "previews plan and warm nothing")
        XCTAssertEqual(spoken, [PresetCoordinator.previewingText("B"), PresetCoordinator.previewingText("C"),
                                PresetCoordinator.cancelledText("A")], "R9: library lane")
    }

    // MARK: - S2: Keep

    func testKeepCommitsLikeATapWithoutASecondLoad() async throws {
        let loader = FakeLoader()
        let coordinator = try makeCoordinator(loader)
        await coordinator.select(try preset("A", coordinator), in: .included)
        let friday = try XCTUnwrap(coordinator.createCollection(named: "Friday"))
        XCTAssertEqual(coordinator.addToCollection(try preset("B", coordinator), friday.id), .added)
        spoken = []

        await coordinator.preview(try preset("B", coordinator), from: .collection(friday.id))
        XCTAssertEqual(defaults.string(forKey: FavoritesStore.lastPresetKey), "frontend-uwp/A.milk", "not yet")
        let kept = await coordinator.keepAudition()
        XCTAssertTrue(kept)
        advance(3)

        XCTAssertEqual(loader.loaded, ["A", "B"], "B loaded once")
        XCTAssertEqual(coordinator.current?.name, "B")
        XCTAssertNil(coordinator.audition)
        XCTAssertEqual(coordinator.scope, .collection(friday.id))
        XCTAssertEqual(defaults.string(forKey: AppSettings.presetScopeKey), PresetScope.collection(friday.id).storageValue)
        XCTAssertEqual(defaults.string(forKey: FavoritesStore.lastPresetKey), "frontend-uwp/B.milk")
        XCTAssertEqual(coordinator.recent?.ids.first, "frontend-uwp/B.milk", "the history dwell starts at Keep")
        XCTAssertEqual(spoken, [PresetCoordinator.previewingText("B"), PresetCoordinator.keptText("B")])
    }

    func testACommittedSelectionDuringAPreviewEndsItWithoutARestore() async throws {
        let loader = FakeLoader()
        let coordinator = try makeCoordinator(loader)
        await coordinator.select(try preset("A", coordinator))
        await coordinator.preview(try preset("B", coordinator), from: .included)
        await coordinator.next()   // e.g. MIDI or OSC while the browser is open
        XCTAssertNil(coordinator.audition)
        XCTAssertEqual(loader.loaded.count, 3, "\(loader.loaded)")
        XCTAssertEqual(coordinator.current?.name, loader.loaded.last)
        await coordinator.cancelAudition()   // closing the browser afterwards restores nothing
        XCTAssertEqual(loader.loaded.count, 3)
    }

    // MARK: - S3: failed previews

    func testAFailedFirstPreviewLeavesTheOriginalAndStoresNothing() async throws {
        let loader = FakeLoader()
        loader.failing = ["B"]
        let coordinator = try makeCoordinator(loader)
        await coordinator.select(try preset("A", coordinator))
        let storedBefore = try storedBytes()
        spoken = []

        await coordinator.preview(try preset("B", coordinator), from: .included)

        XCTAssertEqual(coordinator.current?.name, "A")
        XCTAssertEqual(coordinator.onScreen?.name, "A")
        XCTAssertFalse(coordinator.isPreviewing)
        XCTAssertEqual(coordinator.audition?.notice, PresetCoordinator.previewFailedText("B"))
        XCTAssertNil(coordinator.failureMessage, "the committed preset did not fail")
        XCTAssertTrue(coordinator.excludedThisSession.contains("frontend-uwp/B.milk"), "FR-118")
        XCTAssertFalse(coordinator.canPreview(try preset("B", coordinator)))
        XCTAssertEqual(try storedBytes(), storedBefore)
        XCTAssertEqual(spoken, [PresetCoordinator.previewFailedText("B")])
        await coordinator.cancelAudition()
        XCTAssertEqual(loader.loaded, ["A"], "nothing to restore")
        XCTAssertNil(coordinator.audition)
    }

    func testAFailedLaterPreviewKeepsThePreviousPreviewAndCancelStillReturnsToTheOriginal() async throws {
        let loader = FakeLoader()
        loader.failing = ["D"]
        let coordinator = try makeCoordinator(loader)
        await coordinator.select(try preset("A", coordinator))
        await coordinator.preview(try preset("C", coordinator), from: .included)
        await coordinator.preview(try preset("D", coordinator), from: .included)
        XCTAssertEqual(coordinator.audition?.showing?.name, "C")
        XCTAssertEqual(coordinator.audition?.notice, PresetCoordinator.previewFailedText("D"))
        await coordinator.cancelAudition()
        XCTAssertEqual(loader.loaded, ["A", "C", "A"])
        XCTAssertEqual(coordinator.current?.name, "A")
    }

    // MARK: - R1: where Preview is offered

    func testPreviewIsNotOfferedForLockedFlaggedOrOnScreenPresets() async throws {
        let loader = FakeLoader()
        let coordinator = try makeCoordinator(loader, settings: AppSettings(defaults: defaults, systemReduceMotion: true))
        await coordinator.select(try preset("A", coordinator))
        XCTAssertFalse(coordinator.canPreview(try preset("A", coordinator)), "on screen")
        XCTAssertFalse(coordinator.canPreview(try preset("L", coordinator)), "locked")
        XCTAssertFalse(coordinator.canPreview(try preset("E", coordinator)), "flagged with Reduce flashing on")
        XCTAssertTrue(coordinator.canPreview(try preset("B", coordinator)))
        await coordinator.preview(try preset("E", coordinator), from: .included)
        XCTAssertNil(coordinator.audition, "refused")
        XCTAssertEqual(loader.loaded, ["A"])
    }
}
