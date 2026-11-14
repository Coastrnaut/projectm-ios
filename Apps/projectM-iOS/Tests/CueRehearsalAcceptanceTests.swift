// CueRehearsalAcceptanceTests.swift — SHOW-006-T14 (specs/237-show-006-cue-rehearsal; R4, R5; S1, S2; contract C1):
// the roadmap acceptance "Preview changes do not alter currently presented frame", with real views and the real
// offscreen renderer (REC-002's still, on the GPU), modelled on UIX-013-T09/T10:
// (a) the visual shows in an external window built like the app's (`ExternalDisplayViewController`) while the real
//     rehearsal panel shows in the device window: the external snapshot is byte-identical with rehearsal off, on, and
//     after three draft edits (each re-rendered);
// (b) a solid red Photo visual (deterministic) is captured through Save Frame's source and recorded through the app's
//     recording path with rehearsal off, then on while draft edits re-render the preview during the recording: the
//     still and every recorded frame are pixel-identical;
// (c) the live settings (their stored defaults), the show's position and applied scene, the SCN-002 autosave's edit
//     revision and the SCN-010 history are unchanged after rehearsal with edits.
// Simulator results are never device evidence (SHOW-006-T17 is the device check).
import AVFoundation
import FlashSafety
import FrameCapture
import FrameRecording
import Metal
import ParameterGraph
import PresentationLifecycle
import SceneFormat
import ShowControl
import ShowStorage
import SwiftUI
import TextLayer
import UIKit
import VisualGenerators
import XCTest
@testable import projectM_iOS

private final class AmpleStorage: StorageProbe, @unchecked Sendable {
    func availableBytes(at directory: URL) -> Int64? { 64_000_000_000 }
}

@MainActor
private final class RecordingContextHolder {
    var value: VideoRecordingCoordinator.Context
    init(_ value: VideoRecordingCoordinator.Context) { self.value = value }
}

@MainActor
final class CueRehearsalAcceptanceTests: XCTestCase {
    private typealias F = SceneAutosaveFixtures

    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var show: ShowCoordinator!
    private var rehearsal: CueRehearsalCoordinator!
    private var applied = 0

    /// A show of three cues (Circular, Linear, Circular) at cue 1 over a temporary store, real AppSettings and the real
    /// rehearsal coordinator wired as `AppCoordinator.makeCueRehearsal` wires it (live values and safety read only).
    override func setUp() async throws {
        let suite = "SHOW006A-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        settings.visual = .circularSpectrum
        show = ShowCoordinator(store: ShowStore(directory: url), registry: try SceneArchiveService.appRegistry())
        show.applyScene = { [unowned self] (_: SceneDocument, _: [SceneIssue]) -> [String] in
            self.applied += 1
            return []
        }
        for (n, visual) in [VisualChoice.circularSpectrum, .linearSpectrum, .circularSpectrum].enumerated() {
            let look = ShowLook(visual: visual, bars: 64, orientation: .vertical, spacing: 0.2, glowEnabled: true,
                                glowIntensity: 0.6, glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""),
                                photoID: nil, videoID: nil)
            XCTAssertTrue(show.addScene(ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Scene \(n + 1)"), label: "Cue \(n + 1)"))
        }
        show.next()
        applied = 0
        let settings: AppSettings = settings
        rehearsal = CueRehearsalCoordinator(show: show, liveValues: { () -> SnapshotRenderValues in SnapshotRenderValues(settings: settings) },
                                            safety: { () -> (reduceFlashing: Bool, clamp: SafetyClamp) in
                                                (reduceFlashing: settings.effectiveReduceFlashing, clamp: settings.safetyClamp)
                                            })
        rehearsal.minimumInterval = .zero
    }

    // MARK: - Helpers

    private func scene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        return scene
    }

    private func device() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return device
    }

    /// The real panel's hosting view over `root` (rehearsal on); removing it is rehearsal off.
    private func addPanel(to root: UIViewController) -> UIHostingController<CueRehearsalPanel> {
        let overlay = UIHostingController(rootView: CueRehearsalPanel(rehearsal: rehearsal))
        overlay.view.backgroundColor = .clear
        root.addChild(overlay)
        overlay.view.frame = root.view.bounds
        root.view.addSubview(overlay.view)
        overlay.didMove(toParent: root)
        root.view.layoutIfNeeded()
        return overlay
    }

    private func removePanel(_ overlay: UIHostingController<CueRehearsalPanel>) {
        overlay.willMove(toParent: nil)
        overlay.view.removeFromSuperview()
        overlay.removeFromParent()
    }

    /// Three draft edits, each rendered offscreen before the next.
    private func editThreeTimes() async {
        let edits: [(inout SnapshotRenderValues) -> Void] = [
            { (v: inout SnapshotRenderValues) in v.glow.intensity = 0.95 },
            { (v: inout SnapshotRenderValues) in v.barCount = .b16 },
            { (v: inout SnapshotRenderValues) in v.glow.threshold = 0.2 },
        ]
        for edit in edits {
            rehearsal.editDraft(edit)
            await rehearsal.waitUntilIdle()
        }
    }

    /// What the window shows, as RGBA bytes at scale 1.
    private func snapshot(_ window: UIWindow) -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { (_: UIGraphicsImageRendererContext) in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cg = image.cgImage else { return [] }
        let width: Int = cg.width, height: Int = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        bytes.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Void in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    private func poll(_ description: String, timeout: Double = 10, _ condition: @MainActor () -> Bool) async throws {
        var waited: Double = 0
        while !condition() {
            if waited >= timeout {
                XCTFail("timed out: \(description)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
            waited += 0.02
        }
    }

    private func captureFrame(_ source: any FrameCaptureSource) async throws -> CapturedPixels {
        var result: CapturedPixels??
        source.captureFrame { (pixels: CapturedPixels?) in result = .some(pixels) }
        try await poll("captured") { result != nil }
        return try XCTUnwrap(result ?? nil)
    }

    /// Records `frames` frames of the photo, running `during` once the recording has started.
    private func record(_ photo: PhotoVisualHost, frames: Int, during: () async -> Void = {}) async throws -> URL {
        let context = RecordingContextHolder(.init(source: photo, visualShown: true, outputLive: true, paused: false))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("show006-out-\(UUID().uuidString)", isDirectory: true)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("show006-work-\(UUID().uuidString)", isDirectory: true)
        let recording = VideoRecordingCoordinator(directory: work, debugDirectory: out, checkInterval: nil,
                                                  storageProbe: AmpleStorage(), storageCheckInterval: nil) { context.value }
        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
        await during()
        let tap = try XCTUnwrap(photo.videoRecording)
        try await poll("frames recorded") { tap.recorder.statistics.written >= frames }
        recording.stop(.user)
        try await poll("finished", timeout: 15) { recording.state == .idle && recording.probe.hasPrefix("video") }
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: out.path).first { $0.hasSuffix(".mp4") })
        return out.appendingPathComponent(name)
    }

    /// The decoded frames as BGRA bytes.
    private func decodedFrames(_ url: URL) async throws -> [[UInt8]] {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack] = try await asset.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: try XCTUnwrap(tracks.first),
                                              outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var frames: [[UInt8]] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let width: Int = CVPixelBufferGetWidth(buffer), height: Int = CVPixelBufferGetHeight(buffer)
            let row: Int = CVPixelBufferGetBytesPerRow(buffer)
            var bytes: [UInt8] = []
            bytes.reserveCapacity(width * height * 4)
            if let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) {
                for y in 0..<height { bytes.append(contentsOf: UnsafeBufferPointer(start: base + y * row, count: width * 4)) }
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            frames.append(bytes)
        }
        XCTAssertEqual(reader.status, .completed)
        return frames
    }

    private func redPicture(width: Int, height: Int) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { (c: UIGraphicsImageRendererContext) in
            UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("show006-\(UUID().uuidString).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }

    /// The stored settings, the position and the applied scene: everything a preview must not touch.
    private var liveFingerprint: String {
        let stored: [String: Any] = defaults.dictionaryRepresentation().filter { (e: (key: String, value: Any)) -> Bool in e.key.hasPrefix("settings.") }
        let keys: [String] = stored.keys.sorted().map { (k: String) -> String in k + "=" + String(describing: stored[k]!) }
        let position: String = show.list.activeIndex.map(String.init) ?? "standby"
        return keys.joined(separator: ";") + "|" + position + "|" + (show.appliedSceneID ?? "none") + "|" + String(applied)
    }

    // MARK: - (a) External display (S1)

    func testExternalDisplayPictureIsIdenticalWithRehearsalOffOnAndWhileEditing() async throws {
        _ = try device()
        let scene = try scene()
        let external = ExternalDisplayCoordinator()
        let deviceWindow = UIWindow(windowScene: scene)
        deviceWindow.frame = CGRect(x: 0, y: 0, width: 260, height: 420)
        let deviceRoot = UIViewController()
        deviceWindow.rootViewController = deviceRoot
        let deviceSlot = VisualSlotView(role: .device)
        deviceSlot.frame = deviceRoot.view.bounds
        deviceRoot.view.addSubview(deviceSlot)
        deviceWindow.isHidden = false
        let externalWindow = UIWindow(windowScene: scene)
        externalWindow.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let controller = ExternalDisplayViewController()
        externalWindow.rootViewController = controller
        controller.slot.traitOverrides.displayScale = 1
        externalWindow.isHidden = false
        controller.view.layoutIfNeeded()
        defer { deviceWindow.isHidden = true; externalWindow.isHidden = true }

        let visual = UIView()
        visual.backgroundColor = UIColor(red: 0, green: 0, blue: 1, alpha: 1)   // a solid blue stand-in visual
        external.registerDeviceSlot(deviceSlot)
        external.show(visual)
        external.visualizerActive(true)
        external.externalConnected(id: "tv", slot: controller.slot, geometry: controller.slot.geometry, foreground: true)
        XCTAssertTrue(visual.superview === controller.slot, "the visual is on the external display")
        controller.slot.layoutIfNeeded()

        let off: [UInt8] = snapshot(externalWindow)
        rehearsal.setOn(true)
        let panel = addPanel(to: deviceRoot)
        await rehearsal.waitUntilIdle()
        guard case .rendered = rehearsal.picture else { return XCTFail("the panel shows a rendered preview: \(rehearsal.picture)") }
        XCTAssertEqual(rehearsal.cueNumber, 2)
        let on: [UInt8] = snapshot(externalWindow)
        await editThreeTimes()
        _ = snapshot(deviceWindow)   // the panel redraws with the edited preview
        let edited: [UInt8] = snapshot(externalWindow)
        XCTAssertGreaterThanOrEqual(rehearsal.renderCount, 4, "the load and each edit rendered offscreen")
        removePanel(panel)
        rehearsal.close()

        XCTAssertFalse(off.isEmpty)
        XCTAssertTrue(on == off, "S1: the external picture is byte-identical with rehearsal on")
        XCTAssertTrue(edited == off, "S1: and after three preview edits")
        let centre: Int = (90 * 320 + 160) * 4
        XCTAssertEqual(Array(edited[centre..<(centre + 3)]), [0, 0, 255], "the external picture is the visual")
        XCTAssertEqual(controller.slot.subviews, [visual], "the external slot holds the visual and nothing else")
    }

    // MARK: - (b, c) Save Frame, recording and live state (S1, S2)

    func testPresentedFramesAndLiveStateAreUnchangedByRehearsalAndItsEdits() async throws {
        let scene = try scene()
        // SCN-002 autosave and SCN-010 history over the same settings, tracking edits as the app does.
        let folder = F.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let autosave = SceneAutosaveCoordinator(store: SceneAutosaveStore(directory: folder), registry: try F.registry(),
                                                clock: { () -> Double in 0 }, schedulesTimer: false)
        let settings: AppSettings = settings
        let inputs: () -> SceneInputs = { () -> SceneInputs in
            SceneInputs(visual: settings.visual, bars: settings.circularSpectrumBars, orientation: settings.linearSpectrumOrientation,
                        spacing: settings.linearSpectrumSpacing, glowEnabled: settings.glowEnabled,
                        glowIntensity: settings.glowIntensity, glowRadius: settings.glowRadius, glowThreshold: settings.glowThreshold,
                        text: .default, photoID: nil, videoID: nil)
        }
        autosave.inputs = inputs
        autosave.startTracking(observeLifecycle: false)
        let history = SceneHistoryCoordinator()
        history.inputs = inputs
        history.start(observing: true)

        let photo = try PhotoVisualHost.make(device: try device(), reader: nil, barCount: .b32)
        photo.content = .file(try redPicture(width: 240, height: 160))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 240, height: 160)
        let root = UIViewController()
        window.rootViewController = root
        photo.view.frame = root.view.bounds
        photo.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(photo.view)
        window.isHidden = false
        window.layoutIfNeeded()
        photo.view.layoutIfNeeded()
        photo.resume()
        defer { photo.pause(); window.isHidden = true }
        try await poll("the picture is shown") { photo.framesShown > 2 }

        let before: String = liveFingerprint
        let revisionBefore: Int = autosave.editRevision
        let undoBefore: Bool = history.canUndo

        // Rehearsal off.
        let stillOff = FrameColorConversion.rgba8(try await captureFrame(photo), policy: .opaqueOverBlack)
        let fileOff = try await record(photo, frames: 4)
        // Rehearsal on, the panel over the visual, preview edits made while recording.
        rehearsal.setOn(true)
        let panel = addPanel(to: root)
        await rehearsal.waitUntilIdle()
        let stillOn = FrameColorConversion.rgba8(try await captureFrame(photo), policy: .opaqueOverBlack)
        let fileOn = try await record(photo, frames: 4) { () async -> Void in await self.editThreeTimes() }
        XCTAssertGreaterThanOrEqual(rehearsal.renderCount, 4)
        XCTAssertEqual(rehearsal.draft?.isEdited, true, "the draft holds the edits")
        removePanel(panel)
        rehearsal.close()
        history.capture()
        autosave.inputsChanged()

        // S2: nothing live changed.
        XCTAssertEqual(liveFingerprint, before, "S2: settings, position, applied scene and applies unchanged")
        XCTAssertEqual(autosave.editRevision, revisionBefore, "S2: no autosave edit")
        XCTAssertEqual(history.canUndo, undoBefore, "S2: no history step")

        // S1: Save Frame identical, every recorded frame identical.
        XCTAssertEqual(stillOn.width, stillOff.width)
        XCTAssertTrue(stillOn.rgba == stillOff.rgba, "S1: the presented frame is pixel-identical with rehearsal on")
        let corner = stillOn.pixel(x: 1, y: 1)
        XCTAssertEqual([Int(corner.r), Int(corner.g), Int(corner.b)], [255, 0, 0], "the still is the red visual")
        let framesOff = try await decodedFrames(fileOff)
        let framesOn = try await decodedFrames(fileOn)
        XCTAssertGreaterThanOrEqual(framesOn.count, 4)
        let compared: Int = min(framesOn.count, framesOff.count)
        var differing = 0
        for index in 0..<compared where framesOn[index] != framesOff[index] { differing += 1 }
        print("SHOW-006 acceptance: frames on=\(framesOn.count) off=\(framesOff.count) differing=\(differing) renders=\(rehearsal.renderCount)")
        XCTAssertEqual(differing, 0, "S1: each recorded frame is pixel-identical with rehearsal off")
        try? FileManager.default.removeItem(at: fileOn.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: fileOff.deletingLastPathComponent())
    }
}
