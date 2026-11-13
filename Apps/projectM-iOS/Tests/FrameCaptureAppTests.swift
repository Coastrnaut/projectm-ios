// FrameCaptureAppTests.swift — REC-001-T14, T16: Save Frame's coordinator (refusals, timeout,
// cancellation, exporter document) with a fake source, and real captures from the native spectrum
// and the Camera visual (stub camera) on the simulator GPU. Simulator results are never device evidence.
import CameraLayer
import FrameCapture
import Metal
import UIKit
import XCTest
@testable import projectM_iOS

/// Delivers what the test says, when the test says.
@MainActor
private final class FakeCaptureSource: FrameCaptureSource {
    var pending: (@MainActor (CapturedPixels?) -> Void)?
    var requests = 0
    var cancels = 0
    func captureFrame(_ handler: @escaping @MainActor (CapturedPixels?) -> Void) {
        requests += 1
        pending = handler
    }
    func cancelCapture() {
        cancels += 1
        let handler = pending
        pending = nil
        handler?(nil)
    }
    func deliver(_ pixels: CapturedPixels?) {
        let handler = pending
        pending = nil
        handler?(pixels)
    }
}

/// A mutable context the coordinator reads (a reference, so the closure sees changes).
@MainActor
private final class ContextBox {
    var value: FrameCaptureCoordinator.Context
    init(_ value: FrameCaptureCoordinator.Context) { self.value = value }
}

@MainActor
final class FrameCaptureAppTests: XCTestCase {
    private static let opaquePixels = CapturedPixels(width: 2, height: 1, layout: .sRGBBGRA8TopDown([0, 0, 255, 0, 255, 0, 0, 0]))!

    private func waitUntil(_ description: String, timeout: TimeInterval = 10, _ condition: @escaping @MainActor () -> Bool) {
        let done = expectation(description: description)
        var fulfilled = false
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { (_: Timer) in
            MainActor.assumeIsolated {
                if !fulfilled, condition() {
                    fulfilled = true
                    done.fulfill()
                }
            }
        }
        wait(for: [done], timeout: timeout)
        timer.invalidate()
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rec001-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Coordinator (T16)

    func testRefusalsCaptureNothing() {
        let source = FakeCaptureSource()
        let context = ContextBox(FrameCaptureCoordinator.Context(source: source, outputLive: false, paused: false))
        let capture = FrameCaptureCoordinator(debugDirectory: tempDirectory(), formats: [.png]) { context.value }
        capture.requestSave()
        XCTAssertFalse(capture.showFormatChoice)
        XCTAssertEqual(capture.notice, "Restore the output to save a frame.")
        XCTAssertEqual(capture.save(.png), .outputBlackedOut)
        context.value.outputLive = true
        context.value.paused = true
        XCTAssertEqual(capture.save(.png), .paused)
        XCTAssertEqual(capture.notice, "Resume to save a frame.")
        context.value.paused = false
        context.value.source = nil
        XCTAssertEqual(capture.save(.png), .noVisual)
        XCTAssertEqual(source.requests, 0, "no refusal reaches the visual (REC-001-R12, R13)")
        XCTAssertFalse(capture.isCapturing)
        XCTAssertNil(capture.document)
    }

    func testSuccessWritesThePNGAndOneRequestAtATime() throws {
        let source = FakeCaptureSource()
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = FrameCaptureCoordinator(debugDirectory: directory, formats: [.png]) {
            FrameCaptureCoordinator.Context(source: source, outputLive: true, paused: false)
        }
        capture.requestSave()
        XCTAssertTrue(capture.showFormatChoice)
        XCTAssertNil(capture.save(.png))
        XCTAssertTrue(capture.isCapturing)
        XCTAssertEqual(capture.save(.png), .inProgress, "one request at a time")
        XCTAssertEqual(source.requests, 1)
        source.deliver(Self.opaquePixels)
        waitUntil("encoded") { !capture.isCapturing }
        XCTAssertEqual(capture.probe, "png 2x1 opaque")
        XCTAssertEqual(capture.notice, "Frame saved.")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].hasPrefix("Visualizer Frame ") && files[0].hasSuffix(".png"), files[0])
    }

    func testExporterGetsTheDocumentAndReleasesIt() {
        let source = FakeCaptureSource()
        let capture = FrameCaptureCoordinator(debugDirectory: nil, formats: [.png]) {
            FrameCaptureCoordinator.Context(source: source, outputLive: true, paused: false)
        }
        capture.save(.png)
        source.deliver(Self.opaquePixels)
        waitUntil("exporter") { capture.showExporter }
        XCTAssertEqual(capture.document?.frame.summary, "png 2x1 opaque")
        XCTAssertEqual(capture.document?.contentType, .png)
        capture.exportDismissed()
        XCTAssertNil(capture.document, "no copy is kept after a cancel (REC-001-R10)")
        capture.save(.png)
        source.deliver(Self.opaquePixels)
        waitUntil("exporter again") { capture.showExporter }
        capture.exportFinished(.success(URL(fileURLWithPath: "/tmp/x.png")))
        XCTAssertNil(capture.document)
        XCTAssertEqual(capture.notice, "Frame saved.")
    }

    func testNoFrameTimesOutAndALateFrameIsDropped() {
        let source = FakeCaptureSource()
        let capture = FrameCaptureCoordinator(timeout: .milliseconds(50), debugDirectory: tempDirectory(), formats: [.png]) {
            FrameCaptureCoordinator.Context(source: source, outputLive: true, paused: false)
        }
        capture.save(.png)
        waitUntil("timed out") { !capture.isCapturing }
        XCTAssertEqual(capture.probe, "failed: noFrame")
        XCTAssertEqual(source.cancels, 1, "the source's pending request is dropped")
    }

    func testAVisualChangeOrBlackoutCancelsThePendingCapture() {
        let source = FakeCaptureSource()
        let other = FakeCaptureSource()
        let context = ContextBox(FrameCaptureCoordinator.Context(source: source, outputLive: true, paused: false))
        let capture = FrameCaptureCoordinator(debugDirectory: tempDirectory(), formats: [.png]) { context.value }
        capture.save(.png)
        context.value.source = other   // the visual changed before its frame
        source.deliver(Self.opaquePixels)
        XCTAssertFalse(capture.isCapturing)
        XCTAssertEqual(capture.probe, "failed: cancelled")
        context.value.source = source
        capture.save(.png)
        context.value.outputLive = false   // blacked out before the frame
        source.deliver(Self.opaquePixels)
        XCTAssertEqual(capture.probe, "failed: cancelled")
        XCTAssertNil(capture.document)
    }

    // MARK: - Real hosts on the simulator GPU (T14)

    private func host(_ view: UIView, run: () -> Void) throws -> UIWindow {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 120, height: 80)
        view.frame = window.bounds
        window.addSubview(view)
        window.isHidden = false
        view.setNeedsLayout()
        view.layoutIfNeeded()
        run()
        return window
    }

    private func capture(_ source: any FrameCaptureSource) throws -> CapturedPixels {
        var result: CapturedPixels??
        source.captureFrame { (pixels: CapturedPixels?) in result = .some(pixels) }
        waitUntil("captured") { result != nil }
        return try XCTUnwrap(result ?? nil)
    }

    func testNativeSpectrumCaptureIsOpaqueAtTheDrawableSize() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let native = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32)
        let window = try host(native.view) { native.resume() }
        defer { native.pause(); native.view.removeFromSuperview(); window.isHidden = true }
        let drawable = native.view.metalLayer.drawableSize
        let pixels = try capture(native)
        XCTAssertEqual(pixels.width, Int(drawable.width))
        XCTAssertEqual(pixels.height, Int(drawable.height))
        XCTAssertFalse(pixels.mayHaveCoverage)
        XCTAssertTrue(native.view.metalLayer.framebufferOnly, "display-only again after the capture")
        let png = try FrameImageEncoder.encode(pixels, as: .png)
        XCTAssertEqual(png.summary, "png \(Int(drawable.width))x\(Int(drawable.height)) opaque")
    }

    func testCameraVisualCaptureIsTheCompositeAtTheDrawableSize() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let camera = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32) { (device: MTLDevice) -> any CameraFrameProvider in
            StubCameraFrameProvider(device: device, scenario: .granted)   // solid sRGB (188, 188, 188)
        }
        let window = try host(camera.view) { camera.resume() }
        defer { camera.pause(); camera.view.removeFromSuperview(); window.isHidden = true }
        waitUntil("camera picture shown") { camera.framesShown > 1 }
        let drawable = camera.view.metalLayer.drawableSize
        let pixels = try capture(camera)
        XCTAssertEqual(pixels.width, Int(drawable.width))
        XCTAssertEqual(pixels.height, Int(drawable.height))
        XCTAssertTrue(pixels.mayHaveCoverage, "the compositor's linear premultiplied composite")
        let image = FrameColorConversion.rgba8(pixels, policy: .opaqueOverBlack)
        let corner = image.pixel(x: 1, y: 1)   // the camera picture; the spectrum is drawn around the center
        for value in [corner.r, corner.g, corner.b] { XCTAssertEqual(Int(value), 188, accuracy: 2) }
    }
}
