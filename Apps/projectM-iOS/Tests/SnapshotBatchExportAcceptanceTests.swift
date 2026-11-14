// SnapshotBatchExportAcceptanceTests.swift — REC-002-T07 to T09 (US1-US3; REC-002-R2 to R9, R12; S1 to S4): the
// roadmap acceptance "Batch of five scenes produces five correctly named files". Five SCN-008 snapshots with tricky
// names are rendered through the real offscreen renderer (the native generator and the FX-001 glow) and written to a
// temporary folder; the coordinator is wired with the app's own `connect` over real AppSettings, a real SCN-002
// autosave on a temporary folder, a real SCN-010 history and the SCN-008 snapshots. The scene file and its backup
// (bytes), the snapshot list, the undo stack and the live values must be unchanged. No clock, no simulator UI.
import FrameCapture
import Foundation
import ParameterGraph
import SceneFormat
import VisualEffects
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class SnapshotBatchExportAcceptanceTests: XCTestCase {
    private typealias F = SceneAutosaveFixtures

    static let trickyNames = ["Dawn/Dusk", "Dawn:Dusk", "🌅🌅", "Sunset 🌅", "..."]
    static let expectedFiles = ["01-Dawn-Dusk.png", "02-Dawn-Dusk.png", "03-Snapshot.png", "04-Sunset.png", "05-Snapshot.png"]

    @MainActor
    private final class Harness {
        let folder = SceneAutosaveFixtures.folder()
        let batchFolder = FileManager.default.temporaryDirectory.appendingPathComponent("REC002-\(UUID().uuidString)", isDirectory: true)
        let suite = "REC002-\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: AppSettings
        let autosave: SceneAutosaveCoordinator
        let history = SceneHistoryCoordinator()
        let snapshots = SceneSnapshotCoordinator()
        let compare = SceneCompareCoordinator()
        let export: SnapshotBatchExportCoordinator
        var announced: [String] = []

        init(photos: PhotosSaveCoordinator? = nil) throws {
            defaults = UserDefaults(suiteName: suite)!
            settings = AppSettings(defaults: defaults, systemReduceMotion: false)
            autosave = SceneAutosaveCoordinator(store: SceneAutosaveStore(directory: folder), registry: try F.registry(),
                                                clock: { () -> Double in 0 }, schedulesTimer: false)
            export = SnapshotBatchExportCoordinator(store: SnapshotBatchFileStore(directory: batchFolder))
            self.photos = photos
        }

        let photos: PhotosSaveCoordinator?

        var inputs: SceneInputs {
            SceneInputs(visual: settings.visual, bars: settings.circularSpectrumBars, orientation: settings.linearSpectrumOrientation,
                        spacing: settings.linearSpectrumSpacing, glowEnabled: settings.glowEnabled,
                        glowIntensity: settings.glowIntensity, glowRadius: settings.glowRadius, glowThreshold: settings.glowThreshold,
                        text: .default, photoID: nil, videoID: nil)
        }

        /// Commits a scene, wires everything as the app does, then saves five snapshots named `names` (glow on at
        /// 0.1, 0.3, … for odd ones, off for even ones) and leaves the live glow at 0.5.
        func load(names: [String] = SnapshotBatchExportAcceptanceTests.trickyNames) throws {
            try autosave.store.save(SceneAutosaveCapture.document(F.inputs(), carry: F.carry, liveBindings: nil).document.encoded())
            let values = try XCTUnwrap(autosave.restore(assets: nil))
            settings.visual = .circularSpectrum
            SceneAutosaveCapture.apply(values, to: settings)
            autosave.inputs = { [unowned self] () -> SceneInputs in self.inputs }
            autosave.startTracking(observeLifecycle: false)
            history.inputs = { [unowned self] () -> SceneInputs in self.inputs }
            history.carry = { [unowned self] () -> SceneAutosaveCarry in self.autosave.carrySnapshot }
            history.start(observing: false)
            let announce: (String) -> Void = { [unowned self] (text: String) -> Void in self.announced.append(text) }
            snapshots.connect(settings: settings, autosave: autosave, history: history, announce: announce)
            compare.connect(snapshots: snapshots, autosave: autosave, history: history, lock: settings.sceneLock,
                            inputs: { [unowned self] () -> SceneInputs? in self.inputs }, announce: announce)
            export.connect(settings: settings, snapshots: snapshots, photos: photos, announce: announce)
            for (i, name) in names.enumerated() {
                edit(intensity: 0.1 + 0.2 * Double(i), glow: i % 2 == 0)
                XCTAssertTrue(snapshots.save())
                XCTAssertNil(snapshots.rename(at: i, to: name), name)
            }
            edit(intensity: 0.5, glow: true)
            autosave.commitNow()
            autosave.drain()
        }

        func edit(intensity: Double, glow: Bool) {
            settings.glowEnabled = glow
            settings.glowIntensity = intensity
            history.capture()
            history.endCoalescing()
            autosave.inputsChanged()
        }

        /// Everything the export must not change.
        var fingerprint: [String] {
            let main: Int = (try? Data(contentsOf: autosave.store.main))?.hashValue ?? 0
            let backup: Int = (try? Data(contentsOf: autosave.store.backup))?.hashValue ?? 0
            let h = history.history
            let undo: [String] = (h?.undoSteps ?? []).map { (s: SceneHistoryStep<SceneInputs>) -> String in s.label }
            let entries: String = String(describing: autosave.snapshotEntries)
            return [String(main), String(backup), entries, undo.joined(separator: ","), String(describing: inputs),
                    String(autosave.isPending)]
        }

        func batchFiles() -> [String] {
            let folders: [String] = (try? FileManager.default.contentsOfDirectory(atPath: batchFolder.path)) ?? []
            var names: [String] = []
            for f in folders {
                names += (try? FileManager.default.contentsOfDirectory(atPath: batchFolder.appendingPathComponent(f).path)) ?? []
            }
            return names.sorted()
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: batchFolder)
            UserDefaults().removePersistentDomain(forName: suite)
        }
    }

    /// S1, S2, R2, R3, R5, R9: five tricky snapshots → exactly five correctly named PNGs of 1920 × 1080 through the real
    /// renderer, with the scene locked; the scene file, backup, snapshot list, undo stack and live values unchanged.
    func testFiveSnapshotsProduceFiveCorrectlyNamedPNGsAndChangeNothing() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.load()
        XCTAssertFalse(h.autosave.isPending)
        h.settings.sceneLock.lock()   // R9: exporting edits nothing, so it works while locked
        let before: [String] = h.fingerprint

        h.export.prepare()
        XCTAssertEqual(h.export.selection, Set(0..<5))
        XCTAssertNil(h.export.start())
        await h.export.waitForBatch()

        XCTAssertEqual(h.export.phase, .finished)
        XCTAssertEqual(h.export.files.map(\.lastPathComponent), Self.expectedFiles)
        XCTAssertEqual(h.batchFiles(), Self.expectedFiles.sorted(), "exactly five files on disk")
        for url in h.export.files {
            let data = try Data(contentsOf: url)
            let info = try XCTUnwrap(FrameImageEncoder.inspect(data), url.lastPathComponent)
            XCTAssertEqual(info.format, .png)
            XCTAssertEqual(info.width, 1920)
            XCTAssertEqual(info.height, 1080)
        }
        XCTAssertEqual(h.export.probe.split(separator: "|").count, 5)
        XCTAssertEqual(h.announced.last, "Exported 5 images")
        h.autosave.drain()
        XCTAssertEqual(h.fingerprint, before, "the scene file, backup, snapshots, undo stack and live values are unchanged")

        // Images differ where the snapshots differ (glow on at 0.1 vs off) and Done deletes the batch.
        let first = try Data(contentsOf: h.export.files[0]), second = try Data(contentsOf: h.export.files[1])
        XCTAssertNotEqual(first, second)
        h.export.done()
        XCTAssertEqual(h.batchFiles(), [])
        XCTAssertEqual(h.export.files, [])
    }

    /// S3, R7: Cancel before the second image leaves no file and offers nothing.
    func testCancelMidBatchLeavesNoFiles() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.load()
        h.export.size = .square
        h.export.prepare()
        h.export.beforeImage = { [unowned h] (position: Int) -> Void in if position == 2 { h.export.cancel() } }
        XCTAssertNil(h.export.start())
        await h.export.waitForBatch()
        XCTAssertEqual(h.export.phase, .cancelled)
        XCTAssertEqual(h.export.files, [])
        XCTAssertEqual(h.batchFiles(), [], "the partial batch folder was deleted")
        XCTAssertEqual(h.announced.last, SnapshotBatchExportCoordinator.cancelledMessage)
    }

    /// US3, R1, R4, R8, R9, R6: two of five at Square, in list order; refusals; Save to Photos stopping part-way;
    /// leftovers removed at init.
    func testSelectionSizeRefusalsPhotosAndLeftovers() async throws {
        let access = FakeAccess()
        let saver = FakeSaver(failAfter: 1)
        let photos = PhotosSaveCoordinator(access: access, saver: saver)
        let h = try Harness(photos: photos)
        defer { h.cleanUp() }
        try h.load()
        h.export.prepare()
        h.export.size = .square
        h.export.selection = [1, 3]
        XCTAssertNil(h.export.start())
        await h.export.waitForBatch()
        XCTAssertEqual(h.export.files.map(\.lastPathComponent), ["01-Dawn-Dusk.png", "02-Sunset.png"])
        for url in h.export.files {
            let info = try XCTUnwrap(FrameImageEncoder.inspect(try Data(contentsOf: url)))
            XCTAssertEqual([info.width, info.height], [1080, 1080])
        }

        h.export.saveAllToPhotos()
        try await waitUntil { !h.export.isSavingToPhotos }
        XCTAssertEqual(saver.count, 1)
        XCTAssertEqual(h.export.status, "Saved 1 of 2 to Photos. " + PhotosSaveOutcome.failedText)
        XCTAssertEqual(h.export.phase, .finished, "the batch stays offered")

        // A new export replaces the offered batch (one folder at a time).
        h.export.selection = [0]
        XCTAssertNil(h.export.start())
        await h.export.waitForBatch()
        XCTAssertEqual(h.batchFiles(), ["01-Dawn-Dusk.png"])

        // Refusals: nothing selected, a non-native visual, Compare active.
        h.export.selection = []
        XCTAssertEqual(h.export.start(), .nothingSelected)
        h.export.selection = [0]
        h.settings.visual = .projectM
        XCTAssertEqual(h.export.start(), .unsupportedVisual)
        XCTAssertFalse(h.export.visualSupported)
        h.settings.visual = .circularSpectrum
        XCTAssertNil(h.compare.start(a: .current, b: 0))
        XCTAssertEqual(h.export.start(), .comparing)
        h.compare.cancel()

        // R6: a leftover batch from a killed app is deleted when the coordinator is created.
        let leftover = h.batchFolder.appendingPathComponent("leftover", isDirectory: true)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data([1]).write(to: leftover.appendingPathComponent("x.png"))
        _ = SnapshotBatchExportCoordinator(store: SnapshotBatchFileStore(directory: h.batchFolder))
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
    }

    /// S4, R3: the same inputs give the same pixels; the linear spectrum takes the item's orientation.
    func testRenderingIsDeterministic() throws {
        let renderer = try SnapshotStillRenderer()
        let values = SnapshotRenderValues(barCount: .b32, orientation: .vertical, spacing: 0.2,
                                          glow: BloomParameters(enabled: true, intensity: 0.8))
        let clamp = AppSettings(defaults: UserDefaults(suiteName: "REC002-\(UUID().uuidString)")!, systemReduceMotion: false).safetyClamp
        let a = try renderer.renderPixels(style: .circular, values: values, reduceFlashing: true, clamp: clamp, width: 96, height: 54)
        let b = try renderer.renderPixels(style: .circular, values: values, reduceFlashing: true, clamp: clamp, width: 96, height: 54)
        XCTAssertEqual(a, b)
        let lit: Bool = {
            guard case let .sRGBBGRA8TopDown(bytes) = a.layout else { return false }
            return bytes.contains { (v: UInt8) -> Bool in v > 40 }
        }()
        XCTAssertTrue(lit, "the spectrum drew something")
        let line = try renderer.renderPixels(style: .linear(.vertical, spacing: 0.2), values: values, reduceFlashing: true,
                                             clamp: clamp, width: 96, height: 54)
        XCTAssertNotEqual(a, line)
        XCTAssertEqual(SnapshotSyntheticAudio.bands(count: 16), SnapshotSyntheticAudio.bands(count: 16))
    }

    // MARK: - Helpers

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }

    private final class FakeAccess: PhotosAccessProviding {
        func status() -> PhotosAccess { .granted }
        func request() async -> PhotosAccess { .granted }
    }

    /// Saves `failAfter` items, then fails.
    private final class FakeSaver: PhotosSaving {
        let failAfter: Int
        var count = 0
        init(failAfter: Int) { self.failAfter = failAfter }
        func save(_ item: PhotosSaveItem) async throws {
            guard count < failAfter else { throw CocoaError(.fileWriteUnknown) }
            count += 1
        }
    }
}
