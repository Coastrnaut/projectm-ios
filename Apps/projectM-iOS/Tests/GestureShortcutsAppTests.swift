// GestureShortcutsAppTests.swift — UIX-006-T09 (specs/290-uix-006-touch-gesture-mapping; R5-R9; S3, S4; contract G3,
// G4). The performer over a real show (temporary store, three cues), a real `PresetCoordinator` (synthetic library),
// a real `TempoCoordinator` (injected clock) and the real HUD preference: each catalogue action produces the change
// its control does. Then the app coordinator: the switch, VoiceOver, the controls staying hidden, the scene lock
// (edits refused, actions not) and the stored mapping across a relaunch. No wall clock, no simulator UI.
import Foundation
import PerformanceControl
import PresetLibrary
import SceneFormat
import ShowControl
import ShowStorage
import XCTest
@testable import projectM_iOS

@MainActor
final class GestureShortcutsAppTests: XCTestCase {
    final class FakeLoader: PresetLoading {
        func load(_ preset: IndexedPreset) async throws {}
    }

    private func defaults() throws -> UserDefaults {
        let name = "UIX006-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    private static func library() throws -> PresetLibrary {
        let records: [[String: Any]] = ["Alpha", "Beta", "Gamma"].map { (name: String) -> [String: Any] in
            ["id": "frontend-uwp/\(name).milk", "name": name, "author": "A", "source": "included", "folder": [String](),
             "path": "frontend-uwp/\(name).milk", "hash": String(repeating: "0", count: 40)]
        }
        let packs: [[String: Any]] = [["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "l",
                                       "presetCount": 3, "authors": [String](), "locked": false]]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    /// Waits (yielding, at most ~2 s of polling) for an async action's effect.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// S3: each action through the real coordinators.
    func testEachActionRunsItsControlsPath() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("UIX006-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let defaults = try defaults()
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let show = ShowCoordinator(store: ShowStore(directory: root.appendingPathComponent("Show", isDirectory: true)),
                                   registry: try SceneArchiveService.appRegistry())
        show.applyScene = { (_: SceneDocument, _: [SceneIssue]) -> [String] in [] }
        show.announce = { (_: String) in }
        for index in 1...3 {
            let look = ShowLook(visual: .circularSpectrum, bars: 64, orientation: .vertical, spacing: 0.2, glowEnabled: false,
                                glowIntensity: 0.5, glowRadius: 0.02, glowThreshold: 0.5, text: .default, photoID: nil, videoID: nil)
            XCTAssertTrue(show.addScene(ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Scene \(index)"), label: "Cue \(index)"))
        }
        let folder: URL = root.appendingPathComponent("Presets", isDirectory: true)
        let presets = PresetCoordinator(store: FavoritesStore(defaults: defaults), settings: settings, loader: FakeLoader(),
                                        collections: PresetCollectionStore(directory: folder), tags: PresetTagStore(directory: folder),
                                        smart: PresetSmartCollectionStore(directory: folder))
        presets.attach(try Self.library())
        var now: UInt64 = 1_000_000_000
        let tempo = TempoCoordinator(clock: { () -> UInt64 in now }, stateClock: { () -> UInt64 in now }, announce: { (_: String) in })
        let hud = SceneHUDSetting(defaults: defaults)
        var announcedChanges = 0
        let performer = GestureShortcutPerformer(show: show, presets: presets, tempo: tempo, hud: hud,
                                                 announcePresetChange: { (change: @escaping () async -> Void) async -> Void in
                                                     await change()
                                                     announcedChanges += 1
                                                 })

        func cueIndex() -> Int? {
            guard case .cue(let id) = show.list.position else { return nil }
            return show.list.cues.firstIndex { (cue: ShowCue) -> Bool in cue.id == id }
        }
        performer.perform(.nextCue)   // Go: standby → cue 1
        XCTAssertEqual(cueIndex(), 0)
        performer.perform(.nextCue)
        XCTAssertEqual(cueIndex(), 1, "Go advances the show by one cue")
        performer.perform(.previousCue)
        XCTAssertEqual(cueIndex(), 0)

        let before: IndexedPreset? = presets.current
        performer.perform(.nextPreset)
        let changed: Bool = await eventually { presets.current != nil && presets.current != before }
        XCTAssertTrue(changed, "Next preset loads another preset")
        let afterNext: IndexedPreset? = presets.current
        performer.perform(.previousPreset)
        let back: Bool = await eventually { presets.current != afterNext }
        XCTAssertTrue(back, "Previous preset steps back")
        XCTAssertEqual(announcedChanges, 2, "both steps went through the preset announcement")

        let taps: Int = tempo.tapsInSequence
        performer.perform(.tapTempo)
        now += 500_000_000
        XCTAssertEqual(tempo.tapsInSequence, taps + 1, "Tap tempo records one tap")

        XCTAssertFalse(hud.isEnabled)
        performer.perform(.toggleHUD)
        XCTAssertTrue(hud.isEnabled, "Show/hide HUD flips UIX-013's preference")
        performer.perform(.none)
        XCTAssertEqual(performer.count, 7, "None runs nothing and is not counted")
        XCTAssertEqual(performer.last, .toggleHUD)
    }

    /// R5-R8 on the app coordinator: off, VoiceOver, controls hidden, lock.
    func testAppCoordinatorResolvesQuietlyAndHonoursSwitchVoiceOverAndLock() throws {
        let coordinator = AppCoordinator(defaults: try defaults())
        let setting: GestureShortcutsSetting = coordinator.gestureShortcuts
        XCTAssertFalse(setting.isEnabled, "off by default")
        let hudBefore: Bool = coordinator.sceneHUD.isEnabled
        XCTAssertNil(coordinator.handleGestureShortcut(Set(PerformanceGesture.allCases), voiceOverRunning: false), "switch off: nothing")

        setting.setEnabled(true)
        setting.setAction(.toggleHUD, for: .threeFingerTap)
        if coordinator.controlsVisible { coordinator.toggleControls() }
        XCTAssertFalse(coordinator.controlsVisible)
        XCTAssertNil(coordinator.handleGestureShortcut([.threeFingerTap, .twoFingerTap], voiceOverRunning: true), "VoiceOver: nothing")
        XCTAssertEqual(coordinator.sceneHUD.isEnabled, hudBefore)

        let winner = coordinator.handleGestureShortcut([.threeFingerTap, .twoFingerTap], voiceOverRunning: false)
        XCTAssertEqual(winner, GestureShortcutResolution(gesture: .threeFingerTap, action: .toggleHUD))
        XCTAssertNotEqual(coordinator.sceneHUD.isEnabled, hudBefore)
        XCTAssertFalse(coordinator.controlsVisible, "the controls are not revealed")
        XCTAssertEqual(coordinator.lastGestureShortcut, .toggleHUD)
        XCTAssertEqual(coordinator.gestureShortcutCount, 1)

        // R8: the lock refuses editing the mapping, never the action.
        let lock: SceneLock = coordinator.settings.sceneLock
        lock.lock()
        let refusals: Int = lock.refusals
        setting.setAction(.none, for: .threeFingerTap)
        setting.setEnabled(false)
        XCTAssertEqual(setting.action(for: .threeFingerTap), .toggleHUD, "mapping edit refused while locked")
        XCTAssertTrue(setting.isEnabled, "switch edit refused while locked")
        XCTAssertEqual(lock.refusals, refusals + 2)
        XCTAssertNotNil(coordinator.handleGestureShortcut([.threeFingerTap], voiceOverRunning: false), "the action still runs")
        XCTAssertEqual(coordinator.gestureShortcutCount, 2)
        lock.unlock()
    }

    /// S4, R9: the mapping persists in one key and reads back after a relaunch; unknown stored values read as defaults.
    func testMappingPersists() throws {
        let defaults = try defaults()
        let first = GestureShortcutsSetting(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: GestureShortcutsSetting.key), "nothing written until a change")
        first.setEnabled(true)
        first.setAction(.nextPreset, for: .twoFingerTap)
        first.setAction(.none, for: .twoFingerSwipeLeft)
        let relaunched = GestureShortcutsSetting(defaults: defaults)
        XCTAssertTrue(relaunched.isEnabled)
        XCTAssertEqual(relaunched.action(for: .twoFingerTap), .nextPreset)
        XCTAssertEqual(relaunched.action(for: .twoFingerSwipeLeft), .none)
        XCTAssertEqual(relaunched.action(for: .twoFingerSwipeRight), .previousCue, "untouched: the default")
        XCTAssertEqual(GestureShortcutsSetting.key, "settings.gestures.shortcuts")
        defaults.set("not json", forKey: GestureShortcutsSetting.key)
        XCTAssertEqual(GestureShortcutsSetting(defaults: defaults).configuration, GestureShortcutConfiguration(), "damaged: defaults")
    }
}
