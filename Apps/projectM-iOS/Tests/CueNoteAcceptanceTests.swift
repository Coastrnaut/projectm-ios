// CueNoteAcceptanceTests.swift — SHOW-012-T09, T11 (specs/285-show-012-cue-annotations; R6, R7, R9, R10; S2, S4;
// contract show-cue-note.md N4). T09: editing a cue's private note through the coordinator the editor calls (saved and
// reloaded, nothing applied, refused while locked, copied by Duplicate Scene). T11: the roadmap acceptance "Notes ... do
// not appear in live output", with the pattern of UIX-013's SceneHUDAppTests and SHOW-007's ShowTransportAcceptanceTests:
// a real `ShowCoordinator` over a temporary store wired as `AppCoordinator.connectShow` does (the applied scene goes to the
// app's settings and Text visual path and to a real `OSCSendCoordinator` with scene names on, over a capturing
// transport), SHOW-007's transport, UIX-013's HUD texts and an external display window built like the app's. A distinctive
// note on the applied cue appears in none of them. No clock, no network.
import Foundation
import ParameterGraph
import PerformanceControl
import SceneFormat
import ShowControl
import ShowStorage
import Synchronization
import TextLayer
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class CueNoteAcceptanceTests: XCTestCase {
    /// A string that occurs nowhere else in the app or the test data.
    static let secret = "ZQX-PRIVATE-7731 drummer cue"

    /// Records every datagram Send OSC hands to the network.
    private final class CapturingTransport: OSCSendTransport, Sendable {
        let sent = Mutex<[[UInt8]]>([])
        func open(host: OSCPeerAddress, port: UInt16, events: @escaping @Sendable (OSCSendTransportEvent) -> Void) {}
        func send(_ bytes: [UInt8]) { sent.withLock { $0.append(bytes) } }
        func close() {}
    }

    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var show: ShowCoordinator!
    private var folder: URL!
    private var applied: [SceneDocument] = []
    private var announcements: [String] = []

    override func setUp() async throws {
        let suite = "SHOW012-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let folder: URL = self.folder
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        show = makeShow()
        let looks: [(VisualChoice, String)] = [(.circularSpectrum, "Intro"), (.text, "Drop")]
        for (visual, label) in looks {
            let look = ShowLook(visual: visual, bars: 64, orientation: .vertical, spacing: 0.2, glowEnabled: false,
                                glowIntensity: 0.5, glowRadius: 0.02, glowThreshold: 0.5, text: TextOverlaySpec(message: label),
                                photoID: nil, videoID: nil)
            XCTAssertTrue(show.addScene(ShowSceneSnapshot.document(look, id: UUID().uuidString, name: label), label: label))
        }
    }

    private func makeShow() -> ShowCoordinator {
        let made = ShowCoordinator(store: ShowStore(directory: folder), registry: try? SceneArchiveService.appRegistry())
        made.sceneLock = settings.sceneLock   // AppCoordinator.connectSceneLock
        made.applyScene = { [unowned self] (document: SceneDocument, _: [SceneIssue]) -> [String] in
            self.applied.append(document)
            return []
        }
        made.announce = { [unowned self] (text: String) in self.announcements.append(text) }
        made.announceLibrary = { [unowned self] (text: String) in self.announcements.append(text) }
        return made
    }

    private var drop: ShowCue { show.list.cues[1] }

    // MARK: - T09: editing (R6, R7, R10; S4)

    func testANoteIsSavedReloadedAndAppliesNothing() throws {
        XCTAssertTrue(show.setOperatorNote(drop.id, to: "  " + Self.secret + "\n\n"))
        XCTAssertEqual(drop.operatorNote, Self.secret, "stored trimmed")
        XCTAssertTrue(applied.isEmpty, "R6: a note never applies a scene")
        XCTAssertEqual(show.list.position, .standby, "and never moves the position")
        XCTAssertTrue(announcements.isEmpty, "R8: never announced")
        XCTAssertEqual(makeShow().list.cues[1].operatorNote, Self.secret, "saved at once: a relaunch reads it back")

        XCTAssertFalse(show.setOperatorNote(drop.id, to: String(repeating: "x", count: 501)))
        XCTAssertEqual(drop.operatorNote, Self.secret, "a too-long note changes nothing")
        XCTAssertNotNil(show.editorMessage)
        XCTAssertTrue(show.setOperatorNote(drop.id, to: ""))
        XCTAssertNil(makeShow().list.cues[1].operatorNote, "empty text removes the note")
    }

    func testTheLockRefusesNoteEditsAndDuplicateKeepsTheNote() throws {
        XCTAssertTrue(show.setOperatorNote(drop.id, to: Self.secret))
        let copy = try XCTUnwrap(show.duplicateScene(of: drop.id))
        XCTAssertEqual(show.list.cues.first { $0.id == copy.id }?.operatorNote, Self.secret, "R10: Duplicate Scene copies the note")

        settings.sceneLock.lock()
        XCTAssertTrue(show.isEditLocked)
        XCTAssertFalse(show.setOperatorNote(drop.id, to: "changed"), "R7: refused while locked")
        XCTAssertFalse(show.setOperatorNote(drop.id, to: nil))
        XCTAssertEqual(drop.operatorNote, Self.secret, "S4: zero note edits succeed while locked")
        XCTAssertEqual(show.editorMessage, SceneLock.refusalMessage)
        XCTAssertEqual(makeShow().list.cues[1].operatorNote, Self.secret, "nothing saved")
        settings.sceneLock.unlock()
        XCTAssertTrue(show.setOperatorNote(drop.id, to: "changed"))
    }

    // MARK: - T11: never in live output (R9; S2)

    func testANoteNeverReachesLiveOutput() throws {
        XCTAssertTrue(show.setOperatorNote(show.list.cues[0].id, to: Self.secret + " (intro)"))
        XCTAssertTrue(show.setOperatorNote(drop.id, to: Self.secret))

        // Send OSC on, with scene names (OSC-005-R6, R7), over a capturing transport.
        let routable = OSCRoutesCoordinator.routable()
        let receiver = UITestFakeOSC.makeReceiver(store: OSCRoutesCoordinator.makeStore(routable: routable),
                                                  routes: OSCRoutesCoordinator.initialRoutes(routable: routable, defaults: defaults))
        let osc = OSCReceiverCoordinator(settings: settings, receiver: receiver)
        let transport = CapturingTransport()
        let send = OSCSendCoordinator(osc: osc, defaults: defaults, transport: transport,
                                      beatGrid: { () -> (anchor: UInt64, period: UInt64)? in nil },
                                      clock: { () -> UInt64 in 0 }, pollsBeats: false)
        osc.sender = send
        osc.setEnabled(true)
        XCTAssertTrue(send.submitDestination(host: "127.0.0.1", port: "9000"))
        send.setIncludeSceneNames(true)
        send.setEnabled(true)
        addTeardownBlock { @MainActor in send.setEnabled(false); osc.setEnabled(false) }

        // The applied scene goes through the app's settings and Text visual path and Send OSC (AppCoordinator+Show).
        let texts = TextOverlayCoordinator(store: TextOverlayStore(defaults: defaults))
        let registry = try SceneArchiveService.appRegistry()
        show.applyScene = { [unowned self] (document: SceneDocument, warnings: [SceneIssue]) -> [String] in
            self.applied.append(document)
            AppCoordinator.set(ShowSceneSnapshot.apply(of: document, warnings: warnings, registry: registry),
                               settings: self.settings, texts: texts)
            send.post(.scene(name: document.name))
            return []
        }
        let clock = ShowManualClock()
        let driver = ShowAutoAdvanceCoordinator(show: show, clock: clock, runsLoop: false)
        let showTransport = ShowTransportCoordinator(show: show, driver: driver, defaults: defaults)

        var outputs: [String] = []
        for step in [{ () -> ShowStep in self.show.next() }, { () -> ShowStep in self.show.next() }] {
            XCTAssertTrue(step().moved)
            let hud = SceneHUDContent.make(list: show.list, countdown: "Next in 0:30", queued: nil, tempo: .manual(bpm: 120),
                                           source: "Microphone · Active audio")
            outputs += [hud.current, hud.currentSpoken, hud.next ?? "", hud.nextSpoken ?? "", hud.tempo, hud.tempoSpoken, hud.source]
            outputs += [show.statusText, show.accessibilityValue, show.notice ?? "", showTransport.positionText()]
            outputs.append(texts.spec.message)
        }
        XCTAssertEqual(show.list.activeCue?.id, drop.id)
        XCTAssertEqual(texts.spec.message, "Drop", "the Text visual shows the scene's own text")
        XCTAssertEqual(applied.count, 2)
        outputs += announcements
        outputs += applied.map { (document: SceneDocument) -> String in String(decoding: document.encoded(), as: UTF8.self) }

        let datagrams: [[UInt8]] = transport.sent.withLock { $0 }
        XCTAssertEqual(datagrams.count, 2, "one scene message per applied cue")
        XCTAssertEqual(datagrams.last, OSCEncoder.encode(OSCMessage(address: "/projectm/scene", arguments: [.string("Drop")])))
        let needle: [UInt8] = Array("ZQX-PRIVATE".utf8)
        for datagram in datagrams {
            XCTAssertFalse(contains(datagram, needle), "OSC send carries no note")
        }
        for text in outputs {
            XCTAssertFalse(text.contains("ZQX-PRIVATE"), "live output text holds no note: \(text)")
        }
        XCTAssertFalse(outputs.joined().isEmpty)
        try assertExternalDisplayHoldsNoNote()
    }

    /// OUT-001: the external display window holds the visual only, and no view in it carries the note.
    private func assertExternalDisplayHoldsNoNote() throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        let external = ExternalDisplayCoordinator()
        let device = VisualSlotView(role: .device)
        device.frame = CGRect(x: 0, y: 0, width: 240, height: 320)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let controller = ExternalDisplayViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let visual = UIView()
        external.registerDeviceSlot(device)
        external.show(visual)
        external.visualizerActive(true)
        external.externalConnected(id: "tv", slot: controller.slot, geometry: controller.slot.geometry, foreground: true)
        XCTAssertEqual(controller.slot.subviews, [visual], "the external slot holds the visual and nothing else")
        for view in [window] + descendants(window) {
            let texts: [String] = [view.accessibilityLabel, view.accessibilityValue, (view as? UILabel)?.text].compactMap { $0 }
            XCTAssertFalse(texts.contains { (t: String) -> Bool in t.contains("ZQX-PRIVATE") }, "external view \(type(of: view))")
        }
        external.externalDisconnected(id: "tv")
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { (child: UIView) -> [UIView] in descendants(child) }
    }

    private func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }
}
