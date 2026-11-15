// PresetNoteAppTests.swift — PRE-011-T12, T15 (specs/242-pre-011-preset-notes; roadmap acceptance "Notes survive
// relaunch and never appear in exported diagnostics"):
//
// * A note saved through PresetCoordinator is read unchanged by a new coordinator on the same folder (a simulated
//   relaunch); the row label says ", has note"; the announcement names the preset, never the text.
// * With notes holding distinctive marker strings saved through the app's store (and present in notes.json), the
//   PERF-012 performance report (built through the Export button's gathering path) and a diagnostics snapshot with
//   the app's frame drop counts, encoded through `DiagnosticsExporter` (JSON and text), contain no marker.
// * Search finds a preset by its note; PRE-018 lists a dangling note and its safe fix removes it.
// A synthetic library, a fake loader, stores in a temporary directory; no wall clock (injected uptime).
import AudioCore
import Diagnostics
import FrameTiming
import PresetLibrary
import XCTest
@testable import projectM_iOS

@MainActor
final class PresetNoteAppTests: XCTestCase {
    private static let marker = "ZQX-PRIVATE-NOTE-7731"
    private static let secondMarker = "Lovelace wedding cue, do not share"

    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!
    private var announcements: [String] = []

    override func setUp() async throws {
        suite = "PresetNoteAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        announcements = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private final class FakeLoader: PresetLoading {
        func load(_ preset: IndexedPreset) async throws {}
    }

    private func library() throws -> PresetLibrary {
        func record(_ name: String) -> [String: Any] {
            let id = "included/\(name).milk"
            return ["id": id, "name": name, "author": "A", "source": "included", "folder": [String](), "path": id, "hash": "h-\(name)"]
        }
        let packs: [[String: Any]] = [["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "l",
                                       "presetCount": 2, "authors": [], "locked": false]]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": [record("Alpha"), record("Beta")]]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    /// A coordinator as the app makes it, its notes in `directory` (a second call = a relaunch).
    private func launch() throws -> PresetCoordinator {
        let coordinator = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                            settings: AppSettings(defaults: defaults, systemReduceMotion: false), loader: FakeLoader(),
                                            collections: PresetCollectionStore(directory: directory),
                                            tags: PresetTagStore(directory: directory),
                                            smart: PresetSmartCollectionStore(directory: directory),
                                            notes: PresetNoteStore(directory: directory))
        coordinator.attach(try library())
        coordinator.announceLibrary = { [weak self] (text: String) in self?.announcements.append(text) }
        return coordinator
    }

    private func preset(_ name: String, _ coordinator: PresetCoordinator) throws -> IndexedPreset {
        try XCTUnwrap(coordinator.library?.presets.first { $0.name == name }, name)
    }

    // MARK: - Acceptance: survives relaunch

    func testANoteSurvivesRelaunch() throws {
        let first = try launch()
        let alpha = try preset("Alpha", first)
        XCTAssertTrue(first.saveNote("  Slow build for the intro \n", for: alpha))
        XCTAssertEqual(announcements, ["Note saved for Alpha."], "names the preset, never the text")
        XCTAssertTrue(first.rowLabel(alpha, locked: false).hasSuffix(", has note"))

        let relaunched = try launch()
        XCTAssertEqual(relaunched.note(of: try preset("Alpha", relaunched)), "Slow build for the intro")
        XCTAssertNil(relaunched.notesNotice)
        XCTAssertFalse(relaunched.hasNote(try preset("Beta", relaunched)))

        XCTAssertTrue(relaunched.saveNote("   ", for: try preset("Alpha", relaunched)))
        XCTAssertEqual(announcements.last, "Note removed from Alpha.")
        XCTAssertNil(try launch().note(of: alpha), "the removal survives relaunch too")
    }

    func testATooLongNoteIsRefusedAndNothingChanges() throws {
        let coordinator = try launch()
        let alpha = try preset("Alpha", coordinator)
        XCTAssertTrue(coordinator.saveNote("Kept", for: alpha))
        XCTAssertFalse(coordinator.saveNote(String(repeating: "x", count: 2_001), for: alpha))
        XCTAssertEqual(coordinator.notesMessage, "A note can be at most 2,000 characters.")
        XCTAssertEqual(coordinator.note(of: alpha), "Kept")
        XCTAssertEqual(PresetCoordinator.noteCountText(1_999), "1,999 of 2,000")
    }

    // MARK: - Acceptance: never in exported diagnostics

    func testDiagnosticsExportsNeverContainNotes() throws {
        let coordinator = try launch()
        XCTAssertTrue(coordinator.saveNote(Self.marker, for: try preset("Alpha", coordinator)))
        XCTAssertTrue(coordinator.saveNote(Self.secondMarker, for: try preset("Beta", coordinator)))
        let saved = try String(contentsOf: directory.appendingPathComponent(PresetNoteStore.fileName), encoding: .utf8)
        XCTAssertTrue(saved.contains(Self.marker), "the markers are live, saved notes")

        // PERF-012: the Export button's gathering path, with frames measured.
        let attachment = FrameDropAttachment()
        var uptime: TimeInterval = 1_000
        let recorder = PerformanceStateRecorder(uptime: { () -> TimeInterval in uptime },
                                                read: { () -> PerformanceStateReading in
                                                    PerformanceStateReading(thermal: .nominal, lowPower: false, profile: .standard, settings: .full)
                                                }, observes: false)
        uptime += 12
        let inputs: PerformanceReportInputs = AppCoordinator.gatherPerformanceReportInputs(
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000), recorder: recorder, frameDrops: attachment,
            frameStages: FrameStageAttachment(), recording: nil, visual: .projectM, overlayShown: false, pools: [],
            footprint: 100_000_000, available: 1_000_000_000)
        let report: Data = try DiagnosticsExporter.encode(PerformanceReportBuilder.build(inputs))

        // The diagnostics snapshot (CaptureLab's export format) with the app's frame drop counts, JSON and text.
        var snapshot: DiagnosticsSnapshot = try DiagnosticsSnapshot.build(
            from: Self.diagnosticsInput(), note: nil, device: DiagnosticsEnvironment.device(), app: DiagnosticsEnvironment.app(),
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000))
        snapshot.frameDrops = AppCoordinator.exportFrameDrops(attachment.reportEntries(recording: nil))
        let exported: [String] = [try XCTUnwrap(String(data: report, encoding: .utf8)),
                                  try XCTUnwrap(String(data: try DiagnosticsExporter.encode(snapshot), encoding: .utf8)),
                                  DiagnosticsExporter.text(snapshot)]
        for text in exported {
            for forbidden in [Self.marker, "ZQX", Self.secondMarker, "Lovelace", PresetNoteStore.fileName] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), "a diagnostics export contains \(forbidden)")
            }
        }
    }

    private static func diagnosticsInput() -> DiagnosticsInput {
        let format = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: true, sampleType: .float32)
        return DiagnosticsInput(
            sourceMode: .inAppPlayback, finalState: .active, stopReason: nil, hasVerifiedActiveAudio: true,
            statistics: PCMSinkStatistics(sampleCount: 48_000, bufferCount: 100, firstSampleSeconds: 0.05, lastSampleSeconds: 1.05,
                                          cadenceMeanMs: 10.7, cadenceMaxMs: 23, droppedSamples: 0, lateBuffers: 0, format: format,
                                          formatChangeCount: 0, startToFirstAudioMs: 50),
            durationSeconds: 1.1, formats: [(format, 0.05)], peakDBFSMax: -6, rmsDBFSMean: -12,
            transitions: [StateTransition(atSeconds: 0, state: .active)], lifecycle: [])
    }

    // MARK: - Search and integrity

    func testSearchFindsAPresetByItsNote() throws {
        let coordinator = try launch()
        XCTAssertTrue(coordinator.saveNote("Perfect for the Café opening", for: try preset("Beta", coordinator)))
        XCTAssertEqual(coordinator.searchResults("cafe").groups.flatMap(\.presets).map(\.name), ["Beta"])
        XCTAssertEqual(coordinator.searchResults("alpha").groups.flatMap(\.presets).map(\.name), ["Alpha"], "names still match")
    }

    func testADanglingNoteIsListedAndItsSafeFixRemovesIt() throws {
        let coordinator = try launch()
        try coordinator.noteStore.set("A preset that was removed", for: "user/gone")
        XCTAssertEqual(coordinator.integrityReferences().notes, ["user/gone"])
        let issue = PresetIntegrityIssue(kind: .danglingReference, presetID: "user/gone", store: .notes, actions: [.removeReference])
        XCTAssertEqual(issue.title(of: .removeReference), "Remove Note")
        XCTAssertTrue(coordinator.removeDanglingReference(issue))
        XCTAssertNil(try launch().noteStore.note(for: "user/gone"))
    }
}
