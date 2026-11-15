// SafeAreaGuidesAppTests.swift — OUT-005-T06, T07, T09 (specs/258-out-005-safe-area-guides; contracts C1-C5).
// T06: the acceptance "Guides are absent from recorded and external output by default", with the pattern of
// UIX-013's SceneHUDAppTests: the real `SafeAreaGuidesLayer` (plus a pure green probe) on screen in the device
// window while (a) a stand-in visual shows in an external display window built like the app's
// (`ExternalDisplayViewController`), whose snapshot must be byte-identical with the guides on and off; (b) a
// solid red Photo visual is recorded through the app's recording path and saved through Save Frame's source,
// each pixel-identical to a guides-off run. T07: the external display's shape. T09: the preference.
// Simulator results are never device evidence (OUT-005-T12 is the device check).
import AVFoundation
import FrameCapture
import FrameRecording
import Metal
import PerformanceControl
import PresentationLifecycle
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

/// The overlay under test: the real guides layer (centre cross on) and a pure green probe the pixel checks can find.
private struct GuidesUnderTest: View {
    static let green = Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1)
    let setting: SafeAreaGuideSetting
    let external: ExternalDisplayCoordinator

    var body: some View {
        ZStack(alignment: .topLeading) {
            SafeAreaGuidesLayer(setting: setting, external: external)
            Rectangle().fill(Self.green).frame(width: 40, height: 30)
        }
        .ignoresSafeArea()
    }
}

@MainActor
final class SafeAreaGuidesAppTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let name = "out005-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    /// Guides on, with the centre cross, in a fresh suite.
    private func guidesOn() throws -> SafeAreaGuideSetting {
        let setting = SafeAreaGuideSetting(defaults: try defaults())
        setting.isEnabled = true
        setting.showsCentreCross = true
        return setting
    }

    // MARK: - T09: preference (C3, S3)

    func testPreferenceIsOffByDefaultStoredOnChangeAndRestored() throws {
        let defaults = try defaults()
        let setting = SafeAreaGuideSetting(defaults: defaults)
        XCTAssertFalse(setting.isEnabled, "off by default (OUT-005-R5)")
        XCTAssertEqual(setting.choice, SafeAreaGuideChoice.default)
        for key in SafeAreaGuideSetting.allKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed: \(key)") }
        setting.isEnabled = true
        setting.actionPercent = 90
        setting.titlePercent = 40   // clamped to 70
        setting.showsCentreCross = true
        XCTAssertEqual(setting.titlePercent, 70)
        let again = SafeAreaGuideSetting(defaults: defaults)
        XCTAssertTrue(again.isEnabled)
        XCTAssertEqual(again.choice, SafeAreaGuideChoice(actionPercent: 90, titlePercent: 70, showsCentreCross: true), "kept across launches")
        defaults.set(5, forKey: SafeAreaGuideSetting.actionKey)
        XCTAssertEqual(SafeAreaGuideSetting(defaults: defaults).actionPercent, 80, "a bad stored value is clamped")
        XCTAssertEqual(SafeAreaGuideSetting.allKeys, ["settings.visualizer.guides", "settings.visualizer.guides.actionSafe",
                                                       "settings.visualizer.guides.titleSafe", "settings.visualizer.guides.centreCross"])
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

    /// The real guides layer's hosting view, laid over `root` (guides on); removing it is guides off.
    private func addGuides(to root: UIViewController, setting: SafeAreaGuideSetting, external: ExternalDisplayCoordinator) -> UIHostingController<GuidesUnderTest> {
        let overlay = UIHostingController(rootView: GuidesUnderTest(setting: setting, external: external))
        overlay.view.backgroundColor = .clear
        root.addChild(overlay)
        overlay.view.frame = root.view.bounds
        root.view.addSubview(overlay.view)
        overlay.didMove(toParent: root)
        root.view.layoutIfNeeded()
        return overlay
    }

    private func removeGuides(_ overlay: UIHostingController<GuidesUnderTest>) {
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

    // MARK: - T06, T07: external output (S1) and its shape (R4)

    func testExternalDisplayNeverShowsTheGuidesAndTheyFollowItsShape() throws {
        let scene = try scene()
        let external = ExternalDisplayCoordinator()
        let setting = try guidesOn()
        // The device window: its slot below, the guides above (as in VisualizerView's backdrop).
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
        XCTAssertNil(external.externalScreenAspect, "the visual on the device: the device's own shape")
        external.externalConnected(id: "tv", slot: controller.slot, geometry: controller.slot.geometry, foreground: true)
        XCTAssertTrue(visual.superview === controller.slot, "the visual is on the external display")
        controller.slot.layoutIfNeeded()

        // T07 (R4): the guides frame the display's 16:9 shape, fitted in the portrait device view.
        let aspect: Double = try XCTUnwrap(external.externalScreenAspect)
        XCTAssertEqual(aspect, 16.0 / 9.0, accuracy: 0.001)
        let geometry = try XCTUnwrap(SafeAreaGuideGeometry.make(viewWidth: 240, viewHeight: 320, outputAspect: aspect, choice: setting.choice))
        XCTAssertEqual(geometry.output.width, 240, accuracy: 0.01)
        XCTAssertEqual(geometry.output.height, 135, accuracy: 0.01)

        let off: [UInt8] = snapshot(externalWindow)
        let deviceOff: [UInt8] = snapshot(deviceWindow)
        let guides = addGuides(to: deviceRoot, setting: setting, external: external)
        let deviceShot: [UInt8] = snapshot(deviceWindow)
        let probe: [UInt8] = pixel(deviceShot, width: 240, x: 20, y: 15)
        XCTAssertTrue(Self.isProbeGreen(Int(probe[0]), Int(probe[1]), Int(probe[2])), "the overlay is on the device screen: \(probe)")
        // The cross's horizontal stroke at the output's centre (y = 160) is drawn on the device.
        let cross: [UInt8] = pixel(deviceShot, width: 240, x: 120, y: 160)
        XCTAssertGreaterThan(Int(cross[0]) + Int(cross[1]) + Int(cross[2]), 150, "the guides are drawn on the device: \(cross)")
        XCTAssertNotEqual(deviceShot, deviceOff)
        let on: [UInt8] = snapshot(externalWindow)
        removeGuides(guides)

        XCTAssertFalse(off.isEmpty)
        XCTAssertEqual(on.count, off.count)
        XCTAssertTrue(on == off, "S1: the external display's picture is byte-identical with the guides on and off")
        let centre: [UInt8] = pixel(on, width: 320, x: 160, y: 90)
        XCTAssertEqual(Array(centre.prefix(3)), [0, 0, 255], "the external picture is the visual (no cross)")
        let externalViews: [UIView] = descendants(externalWindow)
        XCTAssertFalse(externalViews.contains { (v: UIView) -> Bool in String(describing: type(of: v)).contains("Hosting") },
                       "no SwiftUI hosting view on the external display")
        XCTAssertEqual(controller.slot.subviews, [visual], "the external slot holds the visual and nothing else (OUT-001-R1)")
    }

    // MARK: - T06: recording and Save Frame (S1)

    private func redPicture(width: Int, height: Int) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { (c: UIGraphicsImageRendererContext) in
            UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("out005-\(UUID().uuidString).png")
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
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("out005-out-\(UUID().uuidString)", isDirectory: true)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("out005-work-\(UUID().uuidString)", isDirectory: true)
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

    func testRecordingAndSavedFrameAreIdenticalWithTheGuidesOn() async throws {
        let scene = try scene()
        let external = ExternalDisplayCoordinator()
        let setting = try guidesOn()
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

        // Guides off.
        let stillOff = FrameColorConversion.rgba8(try await captureFrame(photo), policy: .opaqueOverBlack)
        let fileOff = try await record(photo, frames: 12)
        // Guides on (the real layer with the cross, and the green probe, over the visual in the same window).
        let guides = addGuides(to: root, setting: setting, external: external)
        let shown: [UInt8] = snapshot(window)
        let probe: [UInt8] = pixel(shown, width: 240, x: 20, y: 15)
        XCTAssertTrue(Self.isProbeGreen(Int(probe[0]), Int(probe[1]), Int(probe[2])), "the overlay is on screen: \(probe)")
        let stillOn = FrameColorConversion.rgba8(try await captureFrame(photo), policy: .opaqueOverBlack)
        let fileOn = try await record(photo, frames: 12)
        removeGuides(guides)

        XCTAssertEqual(stillOn.width, stillOff.width)
        XCTAssertEqual(stillOn.height, stillOff.height)
        XCTAssertTrue(stillOn.rgba == stillOff.rgba, "S1: the saved frame is pixel-identical with the guides on and off")
        let centre = stillOn.pixel(x: stillOn.width / 2, y: stillOn.height / 2)
        XCTAssertEqual([Int(centre.r), Int(centre.g), Int(centre.b)], [255, 0, 0], "the still's centre is the red visual, no cross")

        let framesOff = try await decodedFrames(fileOff)
        let framesOn = try await decodedFrames(fileOn)
        XCTAssertGreaterThanOrEqual(framesOn.count, 10)
        var green = 0
        for frame in framesOn {
            for i in stride(from: 0, to: frame.count, by: 4) where Self.isProbeGreen(Int(frame[i + 2]), Int(frame[i + 1]), Int(frame[i])) {
                green += 1
            }
        }
        XCTAssertEqual(green, 0, "no probe pixel in any recorded frame")
        let compared: Int = min(framesOn.count, framesOff.count)
        var differing = 0
        for index in 0..<compared where framesOn[index] != framesOff[index] { differing += 1 }
        print("OUT-005 acceptance: frames on=\(framesOn.count) off=\(framesOff.count) differing=\(differing) still=\(stillOn.width)x\(stillOn.height)")
        XCTAssertEqual(differing, 0, "S1: each recorded frame is pixel-identical to the guides-off recording's frame")
        try? FileManager.default.removeItem(at: fileOn.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: fileOff.deletingLastPathComponent())
    }
}
