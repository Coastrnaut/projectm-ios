// VideoRecordingAppTests.swift — REC-003-T20: Record's coordinator (refusals, every stop reason,
// leftover cleanup) with a fake source fed offscreen frames, and a real Photo visual recording on the
// simulator GPU. Files go to a DEBUG folder and are read back with AVFoundation. Simulator results are
// never device evidence (Constitution X).
import FrameRecording
import Metal
import UIKit
import XCTest
@testable import projectM_iOS

/// A source the test feeds by hand (offscreen 64 × 48 frames).
@MainActor
private final class FakeRecordingSource: VideoRecordingSource {
    let recordingDevice: MTLDevice
    let queue: MTLCommandQueue
    var recordingDrawableSize = CGSize(width: 64, height: 48)
    var isPresentingFrames = true
    var videoRecording: VideoRecordingTap?
    private var frame = 0

    init(device: MTLDevice) throws {
        recordingDevice = device
        queue = try XCTUnwrap(device.makeCommandQueue())
    }

    /// One frame at 30 fps of the frame clock, cleared to a gray level, committed and appended.
    func feed(width: Int = 64, height: Int = 48) throws {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget]
        let drawable = try XCTUnwrap(recordingDevice.makeTexture(descriptor: d))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let level = Double(frame % 10) / 10
        videoRecording?.record(commandBuffer: commands, presentationNanoseconds: UInt64(frame) * 1_000_000_000 / 30,
                               drawable: drawable) { (texture: MTLTexture) -> Bool in
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
        frame += 1
    }
}

@MainActor
private final class RecordingContextBox {
    var value: VideoRecordingCoordinator.Context
    init(_ value: VideoRecordingCoordinator.Context) { self.value = value }
}

@MainActor
final class VideoRecordingAppTests: XCTestCase {
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

    private func tempDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rec003-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func device() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return device
    }

    /// A coordinator writing into temporary folders, without the periodic check (tests call it).
    private func makeCoordinator(_ context: RecordingContextBox) -> VideoRecordingCoordinator {
        VideoRecordingCoordinator(directory: tempDirectory("work"), debugDirectory: tempDirectory("out"), checkInterval: nil) {
            context.value
        }
    }

    // MARK: - Refusals (REC-003-R12)

    func testRefusalsRecordNothing() throws {
        let source = try FakeRecordingSource(device: try device())
        let context = RecordingContextBox(.init(source: source, visualShown: true, outputLive: false, paused: false))
        let recording = makeCoordinator(context)
        recording.toggle()
        XCTAssertEqual(recording.state, .idle)
        XCTAssertEqual(recording.notice, "Restore the output to record.")
        XCTAssertNil(source.videoRecording)
        context.value.outputLive = true
        context.value.paused = true
        recording.toggle()
        XCTAssertEqual(recording.notice, "Resume to record.")
        context.value.paused = false
        context.value.source = nil   // projectM: a visual is shown but it is not recordable
        XCTAssertFalse(recording.isRecordable)
        recording.toggle()
        XCTAssertEqual(recording.probe, "refused: notRecordable")
        XCTAssertEqual(recording.notice, RecordingRefusal.notRecordable.notice)
        context.value.visualShown = false
        recording.toggle()
        XCTAssertEqual(recording.probe, "refused: noVisual")
        XCTAssertEqual(recording.state, .idle)
    }

    // MARK: - Stops (REC-003-R11, S4)

    /// Starts, feeds three frames, applies `interrupt`, and checks the stop reason, the notice and the
    /// file read back (3 frames, no audio).
    private func assertStop(_ expected: RecordingStopReason, file: StaticString = #filePath, line: UInt = #line,
                            interrupt: (VideoRecordingCoordinator, RecordingContextBox, FakeRecordingSource) throws -> Void) throws {
        let source = try FakeRecordingSource(device: try device())
        let context = RecordingContextBox(.init(source: source, visualShown: true, outputLive: true, paused: false))
        let recording = makeCoordinator(context)
        recording.toggle()
        XCTAssertEqual(recording.state, .recording, file: file, line: line)
        XCTAssertNotNil(source.videoRecording, file: file, line: line)
        for _ in 0..<3 { try source.feed() }
        try interrupt(recording, context, source)
        waitUntil("\(expected) finished") { recording.state == .idle && recording.probe.hasPrefix("video") }
        XCTAssertEqual(recording.lastStopReason, expected, file: file, line: line)
        XCTAssertEqual(recording.notice, expected.notice ?? "Recording saved.", file: file, line: line)
        XCTAssertNil(source.videoRecording, "the tap is detached", file: file, line: line)
        XCTAssertTrue(recording.probe.hasSuffix("64x48 frames=3 duration=0.10 audio=0"), "probe: \(recording.probe)", file: file, line: line)
    }

    func testUserStop() throws {
        try assertStop(.user) { (recording: VideoRecordingCoordinator, _: RecordingContextBox, _: FakeRecordingSource) in recording.toggle() }
    }

    func testPauseStops() throws {
        try assertStop(.paused) { (recording: VideoRecordingCoordinator, context: RecordingContextBox, _: FakeRecordingSource) in
            context.value.paused = true
            recording.checkContext()
        }
    }

    func testBlackoutStops() throws {
        try assertStop(.blackedOut) { (recording: VideoRecordingCoordinator, context: RecordingContextBox, _: FakeRecordingSource) in
            context.value.outputLive = false
            recording.checkContext()
        }
    }

    func testVisualChangeStops() throws {
        let other = try FakeRecordingSource(device: try device())
        try assertStop(.visualChanged) { (recording: VideoRecordingCoordinator, context: RecordingContextBox, _: FakeRecordingSource) in
            context.value.source = other
            recording.checkContext()
        }
    }

    func testPresentationLossStops() throws {
        try assertStop(.presentationLost) { (recording: VideoRecordingCoordinator, _: RecordingContextBox, source: FakeRecordingSource) in
            source.isPresentingFrames = false
            recording.checkContext()
        }
    }

    func testBackgroundStopsAndFinishes() throws {
        try assertStop(.background) { (recording: VideoRecordingCoordinator, _: RecordingContextBox, _: FakeRecordingSource) in
            recording.appEnteredBackground()
        }
    }

    func testSizeChangeStops() throws {
        try assertStop(.sizeChanged) { (_: VideoRecordingCoordinator, _: RecordingContextBox, source: FakeRecordingSource) in
            try source.feed(width: 48, height: 64)   // the device rotated
        }
    }

    /// One frame is not a recording: no file, a notice.
    func testTooFewFramesOffersNothing() throws {
        let source = try FakeRecordingSource(device: try device())
        let context = RecordingContextBox(.init(source: source, visualShown: true, outputLive: true, paused: false))
        let recording = makeCoordinator(context)
        recording.toggle()
        try source.feed()
        recording.toggle()
        waitUntil("finished") { recording.state == .idle }
        XCTAssertEqual(recording.notice, "Nothing was recorded.")
        XCTAssertEqual(recording.probe, "failed: tooFewFrames")
        XCTAssertNil(recording.fileToMove)
        XCTAssertNil(recording.offered)
    }

    /// REC-003-R13: leftovers from an earlier run are deleted when the coordinator starts.
    func testLeftoversAreDeletedAtLaunch() throws {
        let directory = tempDirectory("leftovers")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["a.mp4", "b.mp4"] { try Data([1, 2, 3]).write(to: directory.appendingPathComponent(name)) }
        _ = VideoRecordingCoordinator(directory: directory, debugDirectory: nil, checkInterval: nil) {
            VideoRecordingCoordinator.Context(source: nil, visualShown: false, outputLive: true, paused: false)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    /// REC-012-R1, R8-R10: the finished recording is offered (nothing opens by itself); a cancelled
    /// Save… keeps the file offered; Record refuses while it is offered; Discard deletes the file.
    func testOfferedRecordingSurvivesAMoverCancelAndDiscardDeletesIt() throws {
        let source = try FakeRecordingSource(device: try device())
        let context = RecordingContextBox(.init(source: source, visualShown: true, outputLive: true, paused: false))
        let recording = VideoRecordingCoordinator(directory: tempDirectory("work"), debugDirectory: nil, checkInterval: nil) {
            context.value
        }
        recording.toggle()
        for _ in 0..<3 { try source.feed() }
        recording.toggle()
        waitUntil("offered") { recording.offered != nil }
        XCTAssertFalse(recording.showMover, "nothing opens by itself (REC-012-R1)")
        let file = try XCTUnwrap(recording.offered)
        XCTAssertTrue(file.lastPathComponent.hasPrefix("Visualizer Recording "))
        XCTAssertEqual(file.pathExtension, "mp4")
        recording.requestSave()
        XCTAssertTrue(recording.showMover)
        XCTAssertEqual(recording.fileToMove, file)
        recording.moverCancelled()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "a cancelled Save… keeps the file (REC-012-R8)")
        XCTAssertEqual(recording.offered, file)
        XCTAssertNil(recording.fileToMove)
        recording.requestSave()
        recording.moverFinished(.failure(CocoaError(.userCancelled)))
        XCTAssertEqual(recording.offered, file)
        recording.toggle()
        XCTAssertEqual(recording.state, .idle, "Record refuses while a recording is offered (REC-012-R10)")
        XCTAssertEqual(recording.notice, "Save, share or discard the last recording first.")
        XCTAssertEqual(recording.probe, "refused: resultOffered")
        recording.discardOffered()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "Discard deletes the file (REC-012-R9)")
        XCTAssertNil(recording.offered)
    }

    /// REC-012-R8: a successful Save… ends the offer (the mover moved the file).
    func testSuccessfulSaveEndsTheOffer() throws {
        let source = try FakeRecordingSource(device: try device())
        let context = RecordingContextBox(.init(source: source, visualShown: true, outputLive: true, paused: false))
        let recording = VideoRecordingCoordinator(directory: tempDirectory("work"), debugDirectory: nil, checkInterval: nil) {
            context.value
        }
        recording.toggle()
        for _ in 0..<3 { try source.feed() }
        recording.toggle()
        waitUntil("offered") { recording.offered != nil }
        let file = try XCTUnwrap(recording.offered)
        defer { try? FileManager.default.removeItem(at: file) }
        recording.requestSave()
        recording.moverFinished(.success(URL(fileURLWithPath: "/tmp/moved.mp4")))
        XCTAssertNil(recording.offered)
        XCTAssertFalse(recording.showMover)
        XCTAssertEqual(recording.notice, "Recording saved.")
    }

    func testElapsedText() {
        XCTAssertEqual(VideoRecordingCoordinator.elapsedText(0), "0:00")
        XCTAssertEqual(VideoRecordingCoordinator.elapsedText(5.9), "0:05")
        XCTAssertEqual(VideoRecordingCoordinator.elapsedText(600), "10:00")
    }

    // MARK: - A real host (simulator GPU)

    /// The Photo visual (compositor) records its own frames through `encodeOutput`; the background stop
    /// finishes a readable file at the drawable's even size.
    func testPhotoVisualRecordsItsFrames() throws {
        let device = try device()
        let photo = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 121, height: 80)
        photo.view.frame = window.bounds
        window.addSubview(photo.view)
        window.isHidden = false
        photo.view.layoutIfNeeded()
        photo.resume()
        defer { photo.pause(); photo.view.removeFromSuperview(); window.isHidden = true }
        waitUntil("frames shown") { photo.framesComposited > 2 }
        let context = RecordingContextBox(.init(source: photo, visualShown: true, outputLive: true, paused: false))
        let recording = makeCoordinator(context)
        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
        let tap = try XCTUnwrap(photo.videoRecording)
        waitUntil("frames recorded") { tap.recorder.statistics.written >= 3 }
        recording.appEnteredBackground()
        waitUntil("finished") { recording.state == .idle && recording.probe.hasPrefix("video") }
        let size = photo.view.metalLayer.drawableSize
        let even = "\(Int(size.width) - Int(size.width) % 2)x\(Int(size.height) - Int(size.height) % 2)"
        XCTAssertTrue(recording.probe.contains(" \(even) "), "probe: \(recording.probe), drawable \(size)")
        XCTAssertTrue(recording.probe.hasSuffix("audio=0"), recording.probe)
        XCTAssertEqual(recording.lastStopReason, .background)
        XCTAssertNil(photo.videoRecording)
    }
}
