// ShowCoordinatorTests.swift — SHOW-001-T12, T14, T16 in the app: a step reads, validates and applies
// the cue's scene (the look round-trips through the snapshot and Settings' setters), edits never apply,
// a missing or invalid scene leaves the output unchanged with a notice, the show and its position
// survive a relaunch, layers the app cannot draw are named, and a visual switch under a blackout stays
// black. Each store is a fresh temporary folder; nothing reads the wall clock.
import Foundation
import Metal
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import UIKit
import VisualEffects
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class ShowCoordinatorTests: XCTestCase {
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShowCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func registry() throws -> ParameterRegistry { try SceneArchiveService.appRegistry() }

    private func look(_ visual: VisualChoice, bars: Int = 64, glow: Bool = false, text: String = "") -> ShowLook {
        ShowLook(visual: visual, bars: bars, orientation: .horizontal, spacing: 0.5, glowEnabled: glow, glowIntensity: 0.7,
                 glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: text), photoID: nil, videoID: nil)
    }

    /// A coordinator over a temporary store that records what it applies.
    private func coordinator(at url: URL) throws -> (ShowCoordinator, () -> [String]) {
        let show = ShowCoordinator(store: ShowStore(directory: url), registry: try registry())
        var applied: [String] = []
        show.applyScene = { (document: SceneDocument, _: [SceneIssue]) -> [String] in
            applied.append(document.id)
            return []
        }
        show.announce = { (_: String) in }
        return (show, { applied })
    }

    private func settings() -> AppSettings {
        let suite = "ShowCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return AppSettings(defaults: defaults, systemReduceMotion: false)
    }

    // MARK: Apply (T12)

    func testStepsApplyTheCueScenesAndEditsNeverApply() throws {
        let url = folder()
        let (show, applied) = try coordinator(at: url)
        let looks = [look(.circularSpectrum), look(.linearSpectrum), look(.text, text: "Hi")]
        var ids: [String] = []
        for item in looks {
            let document = ShowSceneSnapshot.document(item, id: UUID().uuidString, name: item.visual.title)
            ids.append(document.id)
            XCTAssertTrue(show.addScene(document, label: item.visual.title))
        }
        XCTAssertEqual(applied(), [], "adding never applies")
        show.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertTrue(show.rename(show.list.cues[0].id, to: "Words"))
        XCTAssertFalse(show.rename(show.list.cues[0].id, to: ""))
        XCTAssertEqual(applied(), [], "editing never applies")

        show.next()
        show.next()
        show.next()
        XCTAssertEqual(show.next().outcome, .atEnd)
        show.previous()
        XCTAssertEqual(applied(), [ids[2], ids[0], ids[1], ids[0]], "only moves apply, in order")
        XCTAssertEqual(show.appliedSceneID, ids[0])
        XCTAssertEqual(show.statusText, "Cue 2 of 3 · Circular Spectrum")
        XCTAssertEqual(show.accessibilityValue, "Cue 2 of 3, Circular Spectrum")
        XCTAssertNil(show.notice)

        // Relaunch: the show, its order, labels and position come back; nothing is applied at launch.
        let (again, appliedAgain) = try coordinator(at: url)
        XCTAssertEqual(again.list, show.list)
        XCTAssertEqual(again.list.activeSceneID, ids[0])
        XCTAssertEqual(appliedAgain(), [])
    }

    func testTheLookRoundTripsThroughTheSnapshotIntoSettings() throws {
        let registry = try registry()
        let texts = TextOverlayCoordinator.makeDefault(defaults: UserDefaults(suiteName: "ShowCoordinatorTests-text-\(UUID().uuidString)")!)
        for original in [look(.linearSpectrum), look(.circularSpectrum, bars: 16, glow: true), look(.text, bars: 32, text: "Finale"), look(.projectM)] {
            let document = ShowSceneSnapshot.document(original, id: UUID().uuidString, name: "S")
            let decoded = try SceneDocument.decode(document.encoded())
            let loaded = try decoded.document.liveState(registry: registry)
            let apply = ShowSceneSnapshot.apply(of: decoded.document, warnings: loaded.warnings, registry: registry)
            XCTAssertEqual(apply.visual, original.visual)
            XCTAssertEqual(apply.omittedKinds, [])
            XCTAssertFalse(apply.missingMedia)
            let settings = settings()
            AppCoordinator.set(apply, settings: settings, texts: texts)
            XCTAssertEqual(settings.visual, original.visual)
            XCTAssertEqual(settings.circularSpectrumBars, original.bars)
            XCTAssertEqual(settings.linearSpectrumOrientation, original.orientation)
            XCTAssertEqual(settings.linearSpectrumSpacing, original.spacing)
            XCTAssertEqual(settings.glowEnabled, original.glowEnabled)
            XCTAssertEqual(settings.glowIntensity, original.glowIntensity, accuracy: 1e-9)
            if original.visual == .text { XCTAssertEqual(texts.spec.message, "Finale") }
        }
    }

    func testCameraRecordsTheVisualBeforeItAndUndrawableLayersAreNamed() throws {
        XCTAssertEqual(ShowSceneSnapshot.recordedVisual(.camera, beforeCamera: .linearSpectrum), .linearSpectrum)
        XCTAssertEqual(ShowSceneSnapshot.recordedVisual(.camera, beforeCamera: .camera), .projectM)
        let registry = try registry()
        let document = SceneDocument(id: UUID().uuidString, name: "Mixed",
                                     layers: [SceneLayer(instance: 1, content: .camera), SceneLayer(instance: 2, content: .circularSpectrum)])
        let loaded = try document.liveState(registry: registry)
        let apply = ShowSceneSnapshot.apply(of: document, warnings: loaded.warnings, registry: registry)
        XCTAssertEqual(apply.visual, .circularSpectrum, "a cue never selects Camera")
        XCTAssertEqual(apply.omittedKinds, ["camera"])
    }

    func testAPhotoNoLongerStoredIsAppliedWithANote() throws {
        let registry = try registry()
        var item = look(.photo)
        item.photoID = UUID()
        let document = ShowSceneSnapshot.document(item, id: UUID().uuidString, name: "Photo")
        let loaded = try document.liveState(registry: registry, assets: StoredMediaAvailability(photos: [], videos: []))
        let apply = ShowSceneSnapshot.apply(of: document, warnings: loaded.warnings, registry: registry)
        XCTAssertEqual(apply.visual, .photo)
        XCTAssertTrue(apply.missingMedia)
    }

    // MARK: Failures (SHOW-001-R9)

    func testAMissingOrInvalidSceneMovesTheShowLeavesTheOutputAndPostsANotice() throws {
        let url = folder()
        let (show, applied) = try coordinator(at: url)
        var announced: [String] = []
        show.announce = { (message: String) in announced.append(message) }
        let good = ShowSceneSnapshot.document(look(.circularSpectrum), id: UUID().uuidString, name: "Good")
        XCTAssertTrue(show.addScene(good, label: "Good"))
        let bad = ShowSceneSnapshot.document(look(.linearSpectrum), id: UUID().uuidString, name: "Bad")
        XCTAssertTrue(show.addScene(bad, label: "Bad"))
        // An SCN-001 error: a layer without its asset.
        let invalid = SceneDocument(id: UUID().uuidString, name: "Invalid", layers: [SceneLayer(instance: 1, content: .photo(asset: "nope"))])
        XCTAssertTrue(show.addScene(invalid, label: "Invalid"))
        try FileManager.default.removeItem(at: ShowStore(directory: url).sceneFile(bad.id))

        show.next()
        XCTAssertEqual(applied(), [good.id])
        let step = show.next()
        XCTAssertEqual(step.outcome, .moved, "the show still moves")
        XCTAssertEqual(show.list.activeSceneID, bad.id)
        XCTAssertEqual(applied(), [good.id], "the output is unchanged")
        XCTAssertEqual(show.notice, "Cue 2: the scene could not be shown.")
        XCTAssertEqual(announced, ["Cue 2: the scene could not be shown."])
        XCTAssertTrue(show.isSceneMissing(show.list.cues[1]))
        show.next()
        XCTAssertEqual(applied(), [good.id], "an invalid scene is not applied")
        XCTAssertEqual(show.notice, "Cue 3: the scene could not be shown.")
        XCTAssertEqual(show.appliedSceneID, good.id)
    }

    func testASaveFailureKeepsTheSessionStateAndSaysSo() throws {
        let url = folder()
        // A file where the folder should be: nothing can be written.
        try Data("x".utf8).write(to: url)
        let show = ShowCoordinator(store: ShowStore(directory: url), registry: try registry())
        let document = ShowSceneSnapshot.document(look(.circularSpectrum), id: UUID().uuidString, name: "S")
        XCTAssertFalse(show.addScene(document, label: "S"))
        XCTAssertEqual(show.editorMessage, ShowCoordinator.saveFailedMessage)
        XCTAssertTrue(show.list.cues.isEmpty, "no cue refers to a scene that could not be stored")
    }

    func testARefusedShowFileIsSetAsideAndTheEditorSaysSo() throws {
        let url = folder()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url.appendingPathComponent("show.json"))
        let show = ShowCoordinator(store: ShowStore(directory: url), registry: try registry())
        XCTAssertTrue(show.list.cues.isEmpty)
        XCTAssertEqual(show.editorMessage, ShowCoordinator.setAsideMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent("show.damaged-1.json").path))
    }

    // MARK: Blackout (T16, SHOW-001-R10)

    func testAVisualSwitchWhileBlackedOutStaysBlack() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let first = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32, glow: BloomParameters())
        let second = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b16, glow: BloomParameters())
        let external = ExternalDisplayCoordinator()
        external.usesDisplayLink = false
        let slot = VisualSlotView(role: .device)
        slot.frame = CGRect(x: 0, y: 0, width: 200, height: 400)
        external.registerDeviceSlot(slot)
        external.show(first.view)
        external.visualizerActive(true)
        external.setBlackout(true)
        XCTAssertTrue(slot.isOutputBlack)
        external.show(second.view)   // what a cue's visual switch does to the slot
        XCTAssertTrue(slot.isOutputBlack, "the step keeps the output black")
        XCTAssertTrue(second.view.superview === slot)
        XCTAssertEqual(external.blackoutPhase, .blackedOut)
    }
}
