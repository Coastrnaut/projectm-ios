// HotPlugAcceptanceTests.swift — OUT-002-T06, T07, T09 (spec specs/161-out-002-display-hotplug,
// contracts/hot-plug.md): the row's acceptance, "Connect/disconnect fixture leaves internal render
// session active". A fake display connector drives the real ExternalDisplayCoordinator through
// `ExternalDisplayEventSink` with real off-screen windows and slots; the settle timer is a manual
// scheduler and the render session's frames come from an injected clock, so nothing reads the wall
// clock. A real VideoRecordingCoordinator records the session's frames. Simulator results are never
// device evidence (OUT-002-T12 is).
import FrameRecording
import Metal
import PresentationLifecycle
import UIKit
import XCTest
@testable import projectM_iOS

/// The settle timer, fired by hand.
@MainActor
private final class ManualSettleScheduler {
    private(set) var scheduled: [(Double, @MainActor () -> Void)] = []

    var scheduler: ExternalDisplayCoordinator.SettleScheduler {
        { [unowned self] (seconds: Double, body: @escaping @MainActor () -> Void) -> Void in self.scheduled.append((seconds, body)) }
    }

    /// Fires every timer scheduled so far (the settle time has passed).
    func fireAll() {
        let due = scheduled
        scheduled = []
        for (_, body) in due { body() }
    }
}

/// A fake external display: an external slot of 1920 × 1080 pt at scale 1, reported through the event
/// seam like the real scene delegate. `windowed`: the slot is the root of an off-screen window, so a
/// visual moved into it draws; otherwise it is a bare slot, whose release proves the coordinator keeps
/// nothing (UIKit may keep a hidden window, and its root view, until a later run-loop turn).
@MainActor
private final class FakeDisplayConnector {
    private let sink: any ExternalDisplayEventSink
    private let scene: UIWindowScene
    private var window: UIWindow?
    /// The bare slot, owned like a scene owns its window until the display disconnects.
    private var bareSlot: VisualSlotView?
    private var count = 0
    private(set) var id = ""
    weak var lastSlot: VisualSlotView?

    private let windowed: Bool

    init(sink: any ExternalDisplayEventSink, scene: UIWindowScene, windowed: Bool) {
        self.sink = sink
        self.scene = scene
        self.windowed = windowed
    }

    func connect() {
        count += 1
        id = "fake-display-\(count)"
        let controller = ExternalDisplayViewController()
        controller.slot.traitOverrides.displayScale = 1
        guard windowed else {
            let slot = controller.slot
            slot.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            slot.layoutIfNeeded()
            bareSlot = slot
            lastSlot = slot
            sink.externalConnected(id: id, slot: slot, geometry: slot.geometry, foreground: true)
            return
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 100_000, y: 0, width: 1920, height: 1080)
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        self.window = window
        lastSlot = controller.slot
        sink.externalConnected(id: id, slot: controller.slot, geometry: controller.slot.geometry, foreground: true)
    }

    func disconnect() {
        autoreleasepool {
            sink.externalDisconnected(id: id)
            bareSlot = nil
            window?.rootViewController = nil
            window?.isHidden = true
            window = nil
        }
    }
}

/// What a scene applies to the session (scene ID, preset, parameters, effects history); hot-plug
/// must leave it as it was.
private struct SceneWitness: Equatable {
    var sceneID: String
    var preset: String
    var parameters: [String: Double]
    var trailsHistoryFrames: Int
}

/// The internal render session: a visual whose view the coordinator moves. It draws only while its
/// view is in a window, sizes its drawable from its bounds and display scale (like every host), counts
/// a trails reset on a drawable size change (FX-009-R5), counts lifecycle calls, and feeds a recording
/// with each frame of the injected clock.
@MainActor
private final class HotPlugRenderSession: UIView, VideoRecordingSource {
    let recordingDevice: MTLDevice
    private let queue: MTLCommandQueue
    var videoRecording: VideoRecordingTap?
    private(set) var recordingDrawableSize: CGSize = .zero
    var scene: SceneWitness
    private(set) var frames = 0
    private(set) var sizeChanges = 0
    private(set) var trailsResets = 0
    /// Calls that would mean the session restarted (pause/resume, scene re-apply); hot-plug makes none.
    private(set) var restarts = 0
    private(set) var running = true
    private var drawn = 0

    init(device: MTLDevice, scene: SceneWitness) throws {
        recordingDevice = device
        queue = try XCTUnwrap(device.makeCommandQueue())
        self.scene = scene
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    var isPresentingFrames: Bool { running && window != nil && recordingDrawableSize.width >= 2 }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        guard size != recordingDrawableSize else { return }
        if recordingDrawableSize != .zero {
            sizeChanges += 1
            trailsResets += 1   // FX-009-R5: a new output size starts clean
            scene.trailsHistoryFrames = 0
        }
        recordingDrawableSize = size
    }

    func restart() {
        restarts += 1
    }

    /// One frame at `time` (seconds of the injected clock): drawn and offered to the recording.
    func frame(at time: Double) throws {
        layoutIfNeeded()
        guard isPresentingFrames else { return }
        frames += 1
        scene.trailsHistoryFrames += 1
        let w = Int(recordingDrawableSize.width), h = Int(recordingDrawableSize.height)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget]
        let drawable = try XCTUnwrap(recordingDevice.makeTexture(descriptor: d))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        drawn += 1
        let level = Double(drawn % 10) / 10
        videoRecording?.record(commandBuffer: commands, presentationNanoseconds: UInt64(time * 1e9), drawable: drawable) { (texture: MTLTexture) -> Bool in
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: level, green: level, blue: level, alpha: 1)
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
            encoder.endEncoding()
            return true
        }
        commands.commit()
        commands.waitUntilCompleted()
        videoRecording?.recorder.waitForPendingFrames()
    }
}

private final class AmpleStorage: StorageProbe, @unchecked Sendable {
    func availableBytes(at directory: URL) -> Int64? { 1 << 40 }
}

@MainActor
final class HotPlugAcceptanceTests: XCTestCase {
    private let scene = SceneWitness(sceneID: "scene-A", preset: "Geiss - Starfish 1", parameters: ["glow": 0.4, "trails": 0.2],
                                     trailsHistoryFrames: 0)
    private var clock = 0.0

    private func windowScene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        return scene
    }

    private func metal() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return device
    }

    /// The device side: an off-screen 200 × 400 pt window at scale 2 holding the device slot, the
    /// session shown in it on the visualizer screen.
    private func fixture(settle: ManualSettleScheduler, windowed: Bool = false) throws
        -> (ExternalDisplayCoordinator, VisualSlotView, HotPlugRenderSession, FakeDisplayConnector) {
        let windowScene = try windowScene()
        let coordinator = ExternalDisplayCoordinator(connectSettle: HotPlugSettle.defaultInterval, scheduleSettle: settle.scheduler)
        coordinator.usesDisplayLink = false
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: -100_000, y: 0, width: 200, height: 400)
        let deviceSlot = VisualSlotView(role: .device)
        deviceSlot.traitOverrides.displayScale = 2
        deviceSlot.frame = window.bounds
        window.addSubview(deviceSlot)
        window.isHidden = false
        addTeardownBlock { @MainActor in window.isHidden = true }
        let session = try HotPlugRenderSession(device: try metal(), scene: scene)
        coordinator.registerDeviceSlot(deviceSlot)
        coordinator.show(session)
        coordinator.visualizerActive(true)
        deviceSlot.layoutIfNeeded()
        return (coordinator, deviceSlot, session, FakeDisplayConnector(sink: coordinator, scene: windowScene, windowed: windowed))
    }

    /// `count` frames of the injected clock (30 fps); returns how many the session drew.
    @discardableResult
    private func run(_ session: HotPlugRenderSession, frames count: Int) throws -> Int {
        let before = session.frames
        for _ in 0..<count {
            clock += 1.0 / 30
            try session.frame(at: clock)
        }
        return session.frames - before
    }

    private func recordingCoordinator(_ session: HotPlugRenderSession) -> VideoRecordingCoordinator {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("out002-\(UUID().uuidString)", isDirectory: true)
        return VideoRecordingCoordinator(directory: base.appendingPathComponent("work"), debugDirectory: base.appendingPathComponent("out"),
                                         checkInterval: nil, storageProbe: AmpleStorage(), storageCheckInterval: nil) {
            [weak session] () -> VideoRecordingCoordinator.Context in
            VideoRecordingCoordinator.Context(source: session, visualShown: true, outputLive: true, paused: false)
        }
    }

    private func finish(_ recording: VideoRecordingCoordinator) {
        guard recording.state == .recording else { return }
        recording.toggle()
        let done = expectation(description: "recording finished")
        var fulfilled = false
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { (_: Timer) in
            MainActor.assumeIsolated {
                if !fulfilled, recording.state == .idle {
                    fulfilled = true
                    done.fulfill()
                }
            }
        }
        wait(for: [done], timeout: 10)
        timer.invalidate()
    }

    // MARK: - Acceptance (T06; OUT-002-S1)

    /// Connect, disconnect, connect, disconnect with a scene applied and a recording running: the same
    /// session keeps drawing, nothing restarts, no trails reset, nothing external remains, the
    /// recording goes on.
    func testConnectDisconnectFixtureLeavesTheInternalRenderSessionActive() throws {
        let settle = ManualSettleScheduler()
        let (coordinator, deviceSlot, session, connector) = try fixture(settle: settle)
        let recording = recordingCoordinator(session)
        coordinator.follow(recording)
        var changes: [ExternalDisplayConnectionChange] = []
        coordinator.onConnectionChange = { (change: ExternalDisplayConnectionChange) -> Void in changes.append(change) }
        defer { finish(recording) }

        XCTAssertEqual(try run(session, frames: 3), 3, "the session draws on the device")
        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
        XCTAssertTrue(coordinator.holdsPlacement, "the recording holds the placement")
        let sceneBefore = session.scene
        try run(session, frames: 2)

        for cycle in 1...2 {
            connector.connect()
            XCTAssertEqual(try run(session, frames: 2), 2, "cycle \(cycle): drawing while the display settles")
            settle.fireAll()
            XCTAssertTrue(coordinator.currentVisual === session, "the same session instance")
            XCTAssertTrue(session.superview === deviceSlot, "held on the device while recording")
            XCTAssertFalse(coordinator.showsVisualExternally)
            XCTAssertTrue(connector.lastSlot?.subviews.isEmpty ?? true, "the external display stays black")
            XCTAssertEqual(try run(session, frames: 2), 2)
            recording.checkContext()
            connector.disconnect()
            XCTAssertEqual(try run(session, frames: 2), 2, "cycle \(cycle): still drawing after the disconnect")
            recording.checkContext()
            XCTAssertEqual(recording.state, .recording, "cycle \(cycle): the recording continues")
        }

        XCTAssertTrue(coordinator.currentVisual === session)
        XCTAssertTrue(session.running)
        XCTAssertEqual(session.frames, 3 + 2 + 2 * 6, "every frame of the injected clock was drawn")
        XCTAssertEqual(session.restarts, 0, "no pause, resume or re-apply")
        XCTAssertEqual(session.sizeChanges, 0, "the internal output size never changed")
        XCTAssertEqual(session.trailsResets, 0, "so the trails were never reset")
        var expectedScene = sceneBefore
        expectedScene.trailsHistoryFrames = sceneBefore.trailsHistoryFrames + 2 + 2 * 6
        XCTAssertEqual(session.scene, expectedScene, "scene, preset, parameters unchanged; trails history kept growing")
        XCTAssertEqual(coordinator.externalResources, .zero, "nothing of a disconnected display remains")
        XCTAssertNil(connector.lastSlot, "the last external slot was released")
        XCTAssertEqual(recording.state, .recording)
        XCTAssertNil(recording.lastStopReason)
        XCTAssertEqual(changes, [.connected(heldByRecording: true), .disconnected, .connected(heldByRecording: true), .disconnected])
    }

    /// Without a recording the visual moves; the session is still the same instance and keeps
    /// drawing, the scene is unchanged, and trails reset only on the size changes (FX-009-R5).
    func testWithoutARecordingTheVisualMovesAndOnlySizeChangesResetTrails() throws {
        let settle = ManualSettleScheduler()
        let (coordinator, deviceSlot, session, connector) = try fixture(settle: settle, windowed: true)
        try run(session, frames: 2)
        let sceneBefore = session.scene
        connector.connect()
        XCTAssertTrue(session.superview === deviceSlot, "not before it settles")
        settle.fireAll()
        let external = try XCTUnwrap(connector.lastSlot)
        XCTAssertTrue(session.superview === external, "moved when settled")
        XCTAssertTrue(coordinator.showsVisualExternally)
        XCTAssertEqual(try run(session, frames: 3), 3, "drawing on the external display")
        XCTAssertEqual(session.recordingDrawableSize, CGSize(width: 1920, height: 1080))
        connector.disconnect()
        XCTAssertTrue(session.superview === deviceSlot, "back inside the disconnect call")
        XCTAssertEqual(try run(session, frames: 3), 3)
        XCTAssertEqual(session.recordingDrawableSize, CGSize(width: 400, height: 800))
        XCTAssertTrue(coordinator.currentVisual === session)
        XCTAssertEqual(session.restarts, 0)
        XCTAssertEqual(session.sizeChanges, 2)
        XCTAssertEqual(session.trailsResets, 2, "one per output size change, none of its own")
        XCTAssertEqual(session.scene.sceneID, sceneBefore.sceneID)
        XCTAssertEqual(session.scene.preset, sceneBefore.preset)
        XCTAssertEqual(session.scene.parameters, sceneBefore.parameters)
        XCTAssertEqual(coordinator.externalResources, .zero)
    }

    /// A display held off by a recording receives the visual when the recording ends.
    func testAHeldConnectionMovesWhenTheRecordingEnds() throws {
        let settle = ManualSettleScheduler()
        let (coordinator, deviceSlot, session, connector) = try fixture(settle: settle)
        let recording = recordingCoordinator(session)
        coordinator.follow(recording)
        try run(session, frames: 2)
        recording.toggle()
        try run(session, frames: 3)
        connector.connect()
        settle.fireAll()
        XCTAssertTrue(session.superview === deviceSlot)
        finish(recording)
        XCTAssertEqual(recording.lastStopReason, .user)
        XCTAssertFalse(coordinator.holdsPlacement)
        XCTAssertTrue(session.superview === connector.lastSlot, "the hold ended: OUT-001 routing applies")
        connector.disconnect()
    }

    // MARK: - Debounce and leaks (T07; OUT-002-S2)

    func testAConnectionThatDropsBeforeItSettlesMovesAndAnnouncesNothing() throws {
        let settle = ManualSettleScheduler()
        let (coordinator, deviceSlot, session, connector) = try fixture(settle: settle)
        var changes: [ExternalDisplayConnectionChange] = []
        coordinator.onConnectionChange = { (change: ExternalDisplayConnectionChange) -> Void in changes.append(change) }
        let placements = coordinator.placements
        connector.connect()
        XCTAssertEqual(coordinator.externalResources, ExternalResourceCounts(slots: 1, pending: 1, slotsHoldingVisual: 0))
        connector.disconnect()
        settle.fireAll()   // the stale timer
        XCTAssertTrue(session.superview === deviceSlot)
        XCTAssertEqual(coordinator.placements, placements, "the visual never moved")
        XCTAssertEqual(coordinator.settle.cancelled, 1)
        XCTAssertEqual(changes, [], "nothing announced")
        XCTAssertEqual(coordinator.externalResources, .zero)
    }

    func testTwentyBouncesAndTwentyCyclesLeaveNothingHeld() throws {
        let settle = ManualSettleScheduler()
        let (coordinator, deviceSlot, session, connector) = try fixture(settle: settle)
        var changes = 0
        coordinator.onConnectionChange = { (_: ExternalDisplayConnectionChange) -> Void in changes += 1 }
        let placements = coordinator.placements
        for _ in 0..<20 {
            autoreleasepool {
                connector.connect()
                connector.disconnect()
            }
            settle.fireAll()
        }
        XCTAssertNil(connector.lastSlot, "every bounced slot was released")
        XCTAssertEqual(coordinator.placements, placements, "20 bounces moved nothing")
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(coordinator.settle.cancelled, 20)
        for _ in 0..<20 {
            autoreleasepool {
                connector.connect()
                settle.fireAll()
                connector.disconnect()
            }
        }
        XCTAssertNil(connector.lastSlot, "every settled slot was released")
        XCTAssertEqual(coordinator.placements, placements + 40, "out and back 20 times")
        XCTAssertEqual(changes, 40, "one connected and one disconnected per cycle")
        XCTAssertEqual(coordinator.externalResources, .zero)
        XCTAssertTrue(session.superview === deviceSlot)
        XCTAssertTrue(coordinator.currentVisual === session)
    }

    // MARK: - Blackout and announcements (T09; OUT-002-S3, R6)

    func testADisplayConnectingWhileBlackedOutIsBlackFromTheStart() throws {
        let settle = ManualSettleScheduler()
        let (coordinator, _, session, connector) = try fixture(settle: settle)
        coordinator.setBlackout(true)
        connector.connect()
        let external = try XCTUnwrap(connector.lastSlot)
        XCTAssertTrue(external.isOutputBlack, "black before the connect call returned")
        settle.fireAll()
        XCTAssertTrue(session.superview === external)
        XCTAssertTrue(external.isOutputBlack, "still black with the visual in it")
        XCTAssertEqual(coordinator.blackoutPhase, .blackedOut, "the blackout state is unchanged")
        connector.disconnect()
        XCTAssertTrue(coordinator.isOutputBlack, "the device slot is black too")
    }

    func testConnectionChangesAreSystemCaptionsOnTheirOwnLane() {
        let connected = StatusEventCatalog.externalDisplay(.connected(heldByRecording: false))
        XCTAssertEqual(connected.id, "X27")
        XCTAssertEqual(connected.announcement, "External display connected")
        XCTAssertEqual(connected.kind, .display)
        XCTAssertEqual(connected.cause, .system)
        XCTAssertEqual(connected.presentation, .caption)
        let held = StatusEventCatalog.externalDisplay(.connected(heldByRecording: true))
        XCTAssertEqual(held.announcement, "External display connected. It shows the visualization when the recording ends.")
        let disconnected = StatusEventCatalog.externalDisplay(.disconnected)
        XCTAssertEqual(disconnected.id, "X28")
        XCTAssertEqual(disconnected.visibleText, "External display disconnected")
        XCTAssertEqual(disconnected.kind, .display)
        var gate = AnnouncementGate()
        XCTAssertEqual(gate.submit("Output blacked out", kind: .output, now: 0), .speak)
        XCTAssertEqual(gate.submit(disconnected.announcement, kind: .display, now: 0.1), .speak, "a connection never holds a blackout")
    }
}
