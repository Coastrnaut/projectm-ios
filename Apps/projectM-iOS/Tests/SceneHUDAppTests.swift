// SceneHUDAppTests.swift — UIX-013-T07, T09, T10 (specs/233-uix-013-performance-hud; contract contracts/scene-hud.md).
// T07: the HUD's texts (C1) and its preference (C5). T09, T10: the acceptance "HUD is excluded from external output
// and recording" with real views: the real HUD panel (plus a pure green probe) on screen in the device window while
// (a) the visual shows in an external display window built like the app's (`ExternalDisplayViewController`), whose
// snapshot must be byte-identical with the HUD on and off; (b) a solid red Photo visual is recorded through the app's
// recording path and saved through Save Frame's source, each pixel-identical to a HUD-off run.
// Simulator results are never device evidence (UIX-013-T12 is the device check).
import AVFoundation
import FrameCapture
import FrameRecording
import Metal
import PerformanceControl
import PresentationLifecycle
import ShowControl
import SwiftUI
import UIKit
import XCTest
@testable import projectM_iOS

/// A free-storage value that never runs out.
private final class PlentyOfStorage: StorageProbe, @unchecked Sendable {
    func availableBytes(at directory: URL) -> Int64? { 64_000_000_000 }
}

@MainActor
private final class RecordingContextBox {
    var value: VideoRecordingCoordinator.Context
    init(_ value: VideoRecordingCoordinator.Context) { self.value = value }
}

/// The overlay under test: the real HUD panel with show texts, and a pure green probe the pixel checks can find.
private struct HUDUnderTest: View {
    static let green = Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1)
    static let content = SceneHUDContent(current: "Cue 2 of 5 · Build", currentSpoken: "Cue 2 of 5, Build", next: "Next: Drop",
                                         nextSpoken: "Next: Drop", tempo: "120 BPM · Tap", tempoSpoken: "120 BPM from tap",
                                         source: "Microphone · Active audio")

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            VStack(alignment: .leading, spacing: 2) {
                Rectangle().fill(Self.green).frame(width: 40, height: 30)
                SceneHUDPanel(content: Self.content)
            }
        }
        .ignoresSafeArea()
    }
}

@MainActor
final class SceneHUDAppTests: XCTestCase {
    // MARK: - T07: texts (C1)

    private static func list(_ labels: [String], at index: Int?) throws -> ShowCueList {
        let cues: [ShowCue] = labels.map { (label: String) -> ShowCue in
            ShowCue(id: UUID(), sceneID: UUID().uuidString, label: label)
        }
        let position: ShowPosition = index.map { (i: Int) -> ShowPosition in .cue(cues[i].id) } ?? .standby
        return try ShowCueList(id: UUID(), name: "Show", cues: cues, position: position)
    }

    private func make(_ list: ShowCueList, countdown: String? = nil, queued: String? = nil,
                      tempo: TempoReadout = .searching) -> SceneHUDContent {
        SceneHUDContent.make(list: list, countdown: countdown, queued: queued, tempo: tempo, source: "Microphone · Active audio")
    }

    func testCueLinesFollowTheShow() throws {
        let labels = ["Opening", "Build", "Drop"]
        let none = make(ShowCueList())
        XCTAssertEqual(none.current, "No cues")
        XCTAssertNil(none.next, "no next line without cues")

        let standby = make(try Self.list(labels, at: nil))
        XCTAssertEqual(standby.current, "Standby · 3 cues")
        XCTAssertEqual(standby.next, "Next: Opening")

        let second = make(try Self.list(labels, at: 1))
        XCTAssertEqual(second.current, "Cue 2 of 3 · Build")
        XCTAssertEqual(second.currentSpoken, "Cue 2 of 3, Build")
        XCTAssertEqual(second.next, "Next: Drop")

        XCTAssertEqual(make(try Self.list(labels, at: 2)).next, "Next: End of show")
        XCTAssertEqual(make(try Self.list(["Solo"], at: nil)).current, "Standby · 1 cue")
    }

    func testCountdownAndQueuedStepShapeTheNextLine() throws {
        let show = try Self.list(["Opening", "Build", "Drop"], at: 0)
        XCTAssertEqual(make(show, countdown: "Next in 0:12").next, "Next: Build · in 0:12")
        XCTAssertEqual(make(show, countdown: "Next in 0:12, held").nextSpoken, "Next: Build, in 0:12, held")
        XCTAssertEqual(make(show, countdown: "Next in 0:12", queued: "Next cue at the next bar").next, "Next cue at the next bar",
                       "SHOW-003: the queued step replaces the next cue")
        XCTAssertNil(make(ShowCueList(), queued: "Next cue at the next bar").next, "no cues: still no next line")
    }

    func testTempoLineNamesItsSourceAndSourceIsVerbatim() {
        let show = ShowCueList()
        let cases: [(TempoReadout, String, String)] = [
            (.manual(bpm: 120), "120 BPM · Tap", "120 BPM from tap"),
            (.stable(bpm: 120.4), "120 BPM · Estimated", "120 BPM, estimated"),
            (.uncertain(bpm: 118), "≈118 BPM · Estimated", "About 118 BPM, estimated"),
            (.searching, "— BPM · None", "No tempo"),
        ]
        for (readout, text, spoken) in cases {
            let content = make(show, tempo: readout)
            XCTAssertEqual(content.tempo, text)
            XCTAssertEqual(content.tempoSpoken, spoken)
        }
        XCTAssertEqual(make(show).source, "Microphone · Active audio", "FR-042's text, unchanged (Constitution IV)")
    }

    // MARK: - T07: preference (C5)

    func testPreferenceIsOffByDefaultAndStoredOnChange() throws {
        let name = "uix013-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        let setting = SceneHUDSetting(defaults: defaults)
        XCTAssertFalse(setting.isEnabled)
        XCTAssertNil(defaults.object(forKey: SceneHUDSetting.key), "nothing stored until changed")
        setting.isEnabled = true
        XCTAssertEqual(defaults.object(forKey: SceneHUDSetting.key) as? Bool, true)
        XCTAssertTrue(SceneHUDSetting(defaults: defaults).isEnabled, "kept across launches")
        XCTAssertEqual(SceneHUDSetting.key, "settings.visualizer.sceneHUD")
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

    /// The HUD's hosting view, laid over `root` (HUD on); removing it is HUD off.
    private func addHUD(to root: UIViewController) -> UIHostingController<HUDUnderTest> {
        let overlay = UIHostingController(rootView: HUDUnderTest())
        overlay.view.backgroundColor = .clear
        root.addChild(overlay)
        overlay.view.frame = root.view.bounds
        root.view.addSubview(overlay.view)
        overlay.didMove(toParent: root)
        root.view.layoutIfNeeded()
        return overlay
    }

    private func removeHUD(_ overlay: UIHostingController<HUDUnderTest>) {
        overlay.willMove(toParent: nil)
        overlay.view.removeFromSuperview()
        overlay.removeFromParent()
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

    /// The pixel at (x, y) of a snapshot `width` pixels wide (top-left origin).
    private func pixel(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> [UInt8] {
        let i = (y * width + x) * 4
        return Array(bytes[i..<(i + 4)])
    }

    nonisolated static func isProbeGreen(_ r: Int, _ g: Int, _ b: Int) -> Bool { g > 150 && g > r + 60 && g > b + 60 }

    /// Every view in the tree under `view`.
    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { (child: UIView) -> [UIView] in descendants(child) }
    }

    // MARK: - T09: external output (R8, S1)

    func testExternalDisplayNeverShowsTheHUD() throws {
        let scene = try scene()
        let external = ExternalDisplayCoordinator()
        // The device window: its slot below, the HUD above (as in VisualizerView).
        let deviceWindow = UIWindow(windowScene: scene)
        deviceWindow.frame = CGRect(x: 0, y: 0, width: 240, height: 320)
        let deviceRoot = UIViewController()
        deviceWindow.rootViewController = deviceRoot
        let deviceSlot = VisualSlotView(role: .device)
        deviceSlot.frame = deviceRoot.view.bounds
        deviceRoot.view.addSubview(deviceSlot)
        deviceWindow.isHidden = false
        // The external window, built like ExternalDisplaySceneDelegate's.
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
        let hud = addHUD(to: deviceRoot)
        let deviceShot: [UInt8] = snapshot(deviceWindow)
        let probe: [UInt8] = pixel(deviceShot, width: 240, x: 20, y: 15)
        XCTAssertTrue(Self.isProbeGreen(Int(probe[0]), Int(probe[1]), Int(probe[2])), "the HUD is on the device screen: \(probe)")
        let on: [UInt8] = snapshot(externalWindow)
        removeHUD(hud)

        XCTAssertFalse(off.isEmpty)
        XCTAssertEqual(on.count, off.count)
        XCTAssertTrue(on == off, "S1: the external display's picture is byte-identical with the HUD on and off")
        let centre: [UInt8] = pixel(on, width: 320, x: 160, y: 90)
        XCTAssertEqual(Array(centre.prefix(3)), [0, 0, 255], "the external picture is the visual")
        let externalViews: [UIView] = descendants(externalWindow)
        XCTAssertFalse(externalViews.contains { (v: UIView) -> Bool in String(describing: type(of: v)).contains("Hosting") },
                       "no SwiftUI hosting view on the external display")
        XCTAssertFalse(externalViews.contains { (v: UIView) -> Bool in v.accessibilityIdentifier == "sceneHUD" })
        XCTAssertEqual(controller.slot.subviews, [visual], "the external slot holds the visual and nothing else (OUT-001-R1)")
    }

    // MARK: - T10: recording and Save Frame (R9, S2)

    private func redPicture(width: Int, height: Int) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { (c: UIGraphicsImageRendererContext) in
            UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uix013-\(UUID().uuidString).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
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

    /// Records `frames` frames of the photo and returns the file (debug directory: no mover).
    private func record(_ photo: PhotoVisualHost, frames: Int) async throws -> URL {
        let context = RecordingContextBox(.init(source: photo, visualShown: true, outputLive: true, paused: false))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("uix013-out-\(UUID().uuidString)", isDirectory: true)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("uix013-work-\(UUID().uuidString)", isDirectory: true)
        let recording = VideoRecordingCoordinator(directory: work, debugDirectory: out, checkInterval: nil,
                                                  storageProbe: PlentyOfStorage(), storageCheckInterval: nil) { context.value }
        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
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

    func testRecordingAndSavedFrameAreIdenticalWithTheHUDOn() async throws {
        let scene = try scene()
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

        // HUD off.
        let stillOff = FrameColorConversion.rgba8(try await captureFrame(photo), policy: .opaqueOverBlack)
        let fileOff = try await record(photo, frames: 12)
        // HUD on (the real panel and the green probe over the visual, in the same window).
        let hud = addHUD(to: root)
        let shown: [UInt8] = snapshot(window)
        let probe: [UInt8] = pixel(shown, width: 240, x: 20, y: 15)
        XCTAssertTrue(Self.isProbeGreen(Int(probe[0]), Int(probe[1]), Int(probe[2])), "the HUD is on screen: \(probe)")
        let stillOn = FrameColorConversion.rgba8(try await captureFrame(photo), policy: .opaqueOverBlack)
        let fileOn = try await record(photo, frames: 12)
        removeHUD(hud)

        // Save Frame: pixel-identical.
        XCTAssertEqual(stillOn.width, stillOff.width)
        XCTAssertEqual(stillOn.height, stillOff.height)
        XCTAssertTrue(stillOn.rgba == stillOff.rgba, "S2: the saved frame is pixel-identical with the HUD on and off")
        let corner = stillOn.pixel(x: 1, y: 1)
        XCTAssertEqual([Int(corner.r), Int(corner.g), Int(corner.b)], [255, 0, 0], "the still is the red visual")

        // Recording: no probe pixel, and every decoded frame equals the HUD-off recording's frame.
        let framesOff = try await decodedFrames(fileOff)
        let framesOn = try await decodedFrames(fileOn)
        XCTAssertGreaterThanOrEqual(framesOn.count, 10)
        var green = 0
        for frame in framesOn {
            for i in stride(from: 0, to: frame.count, by: 4) where Self.isProbeGreen(Int(frame[i + 2]), Int(frame[i + 1]), Int(frame[i])) {
                green += 1
            }
        }
        XCTAssertEqual(green, 0, "no HUD probe pixel in any recorded frame")
        let compared: Int = min(framesOn.count, framesOff.count)
        var differing = 0
        for index in 0..<compared where framesOn[index] != framesOff[index] { differing += 1 }
        print("UIX-013 acceptance: frames on=\(framesOn.count) off=\(framesOff.count) differing=\(differing) still=\(stillOn.width)x\(stillOn.height)")
        XCTAssertEqual(differing, 0, "S2: each recorded frame is pixel-identical to the HUD-off recording's frame")
        try? FileManager.default.removeItem(at: fileOn.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: fileOff.deletingLastPathComponent())
    }
}
