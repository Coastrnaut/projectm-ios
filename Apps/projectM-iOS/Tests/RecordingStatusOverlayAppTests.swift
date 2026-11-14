// RecordingStatusOverlayAppTests.swift — REC-009-T06, T08: the recording status overlay's wiring (dropped
// slots from the recorder, storage readings, throttled X9f/X9g) with a hand-fed source, and the acceptance:
// a solid red Photo visual recorded through the app's real recording path while a green probe and the real
// status lines are on screen in the same window; every frame read back is red with no probe pixel.
// Simulator results are never device evidence (Constitution X).
import AVFoundation
import FrameRecording
import Metal
import SwiftUI
import UIKit
import XCTest
@testable import projectM_iOS

/// A source the test feeds by hand (offscreen 64 × 48 frames at chosen times).
@MainActor
private final class HandFedSource: VideoRecordingSource {
    let recordingDevice: MTLDevice
    let queue: MTLCommandQueue
    var recordingDrawableSize = CGSize(width: 64, height: 48)
    var isPresentingFrames = true
    var videoRecording: VideoRecordingTap?

    init(device: MTLDevice) throws {
        recordingDevice = device
        queue = try XCTUnwrap(device.makeCommandQueue())
    }

    /// One gray frame at `seconds` of the frame clock, committed and appended.
    func feed(at seconds: Double) throws {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 64, height: 48, mipmapped: false)
        d.usage = [.renderTarget]
        let drawable = try XCTUnwrap(recordingDevice.makeTexture(descriptor: d))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        videoRecording?.record(commandBuffer: commands, presentationNanoseconds: UInt64(seconds * 1e9),
                               drawable: drawable) { (texture: MTLTexture) -> Bool in
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
            encoder.endEncoding()
            return true
        }
        commands.commit()
        commands.waitUntilCompleted()
        videoRecording?.recorder.waitForPendingFrames()
    }
}

/// A free-storage value the test sets.
private final class SetStorageProbe: StorageProbe, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64?
    init(_ value: Int64?) { self.value = value }
    var available: Int64? {
        get { lock.withLock { () -> Int64? in value } }
        set { lock.withLock { () -> Void in value = newValue } }
    }
    func availableBytes(at directory: URL) -> Int64? { available }
}

@MainActor
private final class ContextBox {
    var value: VideoRecordingCoordinator.Context
    init(_ value: VideoRecordingCoordinator.Context) { self.value = value }
}

/// The acceptance probe: a pure green block with text in the top-left corner, then the real status lines.
private struct ProbeOverlay: View {
    let recording: VideoRecordingCoordinator
    static let green = Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            VStack(alignment: .leading, spacing: 2) {
                Rectangle().fill(Self.green).frame(width: 40, height: 30)
                Text("PROBE REC-009").font(.caption.bold()).foregroundStyle(Self.green)
                RecordingStatusLines(recording: recording)
            }
        }
        .ignoresSafeArea()
    }
}

@MainActor
final class RecordingStatusOverlayAppTests: XCTestCase {
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

    /// Async tests: polls on the main actor without blocking it (the finish runs there).
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

    private func tempDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rec009-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func device() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return device
    }

    private func makeCoordinator(_ context: ContextBox, storage: StorageProbe) -> VideoRecordingCoordinator {
        VideoRecordingCoordinator(directory: tempDirectory("work"), debugDirectory: tempDirectory("out"), checkInterval: nil,
                                  storageProbe: storage, storageCheckInterval: nil) { context.value }
    }

    /// The guard's policy for the running recording (what the coordinator built at Record).
    private func policy(_ recorder: MetalFrameRecorder) -> RecordingStoragePolicy {
        RecordingStoragePolicy(estimate: RecordingStorageEstimate(geometry: recorder.geometry, settings: recorder.settings))
    }

    // MARK: - T06: wiring

    func testDroppedCountIsTheRecordersDroppedSlots() throws {
        let source = try HandFedSource(device: try device())
        let context = ContextBox(.init(source: source, visualShown: true, outputLive: true, paused: false))
        let recording = makeCoordinator(context, storage: SetStorageProbe(64_000_000_000))
        XCTAssertNil(recording.statusSummary, "idle: no overlay")
        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
        let recorder = try XCTUnwrap(source.videoRecording?.recorder)
        XCTAssertEqual(recording.statusSummary?.droppedText, "Dropped frames: 0", "shown from the start")
        for i in 0..<5 { try source.feed(at: Double(i) / 30) }
        try source.feed(at: 0.5)   // a stall: the slots between 4/30 s and 0.5 s get no frame
        recording.checkContext()
        let dropped: Int = recorder.statistics.droppedSlots
        XCTAssertGreaterThan(dropped, 0)
        XCTAssertEqual(recording.statusSummary?.droppedSlots, dropped, "REC-009-S2: the recorder's live count")
        XCTAssertEqual(recording.statusSummary?.writtenFrames, recorder.statistics.written)
        XCTAssertEqual(recording.statusSummary?.droppedText,
                       RecordingStatusSummary(statistics: recorder.statistics, policy: nil, availableBytes: nil, fileBytes: nil,
                                              recordedSeconds: 0).droppedText)
        recording.stop(.user)
        XCTAssertNil(recording.statusSummary, "finishing: no overlay")
        waitUntil("finished") { recording.state == .idle }
        XCTAssertNil(recording.statusSummary)
    }

    func testStorageReadingsDriveTheLineAndRisingWarningsPostOnce() async throws {
        let source = try HandFedSource(device: try device())
        let context = ContextBox(.init(source: source, visualShown: true, outputLive: true, paused: false))
        let storage = SetStorageProbe(64_000_000_000)
        let recording = makeCoordinator(context, storage: storage)
        var clock: Double = 100
        let announcer = AccessibilityAnnouncer(post: { (_: String) in }, now: { () -> Double in clock },
                                               schedule: { (_: Double, _: @escaping @MainActor () -> Void) in })
        let router = StatusEventRouter(announcer: announcer, schedule: { (_: Double, _: @escaping @MainActor () -> Void) in })
        var lastSequence = 0
        /// What `RecordingStatusEventChanges` does: post each new warning through the router.
        func postNewWarning() {
            guard let warning = recording.statusWarning, warning.sequence != lastSequence else { return }
            lastSequence = warning.sequence
            router.post(StatusEventCatalog.recordingWarning(warning))
            clock += 5   // past the lane's window
        }

        recording.toggle()
        let recorder = try XCTUnwrap(source.videoRecording?.recorder)
        let rules = policy(recorder)
        let rate: Int64 = rules.estimate.bytesPerSecond
        let threshold: Int64 = rules.stopThreshold(fileBytes: nil, recordedSeconds: 0)
        try source.feed(at: 0)
        try source.feed(at: 1.0 / 30)
        XCTAssertEqual(recording.statusSummary?.storageLevel, .ok, "the Record-time reading")
        XCTAssertEqual(recording.statusSummary?.storageText.hasPrefix("64.0 GB free, about "), true,
                       recording.statusSummary?.storageText ?? "nil")
        postNewWarning()
        XCTAssertTrue(router.log.isEmpty, "nothing to announce while ok")

        storage.available = threshold + 200 * rate   // 200 s left: low
        await recording.checkStorage()
        XCTAssertEqual(recording.state, .recording, "above the guard's threshold: still recording")
        XCTAssertEqual(recording.statusSummary?.storageLevel, .low)
        XCTAssertEqual(recording.statusSummary?.storageText.hasSuffix("about 3 min left"), true,
                       recording.statusSummary?.storageText ?? "nil")
        postNewWarning()
        XCTAssertEqual(router.log, ["X9g"])
        XCTAssertEqual(announcer.spoken.last, "recording|Storage low: about 3 min of recording left")

        await recording.checkStorage()   // the same level again: nothing more
        recording.checkContext()
        postNewWarning()
        XCTAssertEqual(router.log, ["X9g"])

        storage.available = threshold + 30 * rate   // critical, but within 30 s of recording since the low warning
        await recording.checkStorage()
        XCTAssertEqual(recording.statusSummary?.storageLevel, .critical)
        XCTAssertEqual(recording.statusSummary?.storageText.hasSuffix("under 1 min left"), true)
        postNewWarning()
        XCTAssertEqual(router.log, ["X9g"], "throttled: 30 s of recording between two storage announcements")

        // 31 s of recorded time later (a long stall: also heavy dropped slots), both warnings rise.
        try source.feed(at: 31.5)
        await recording.checkStorage()
        let dropped: Int = recorder.statistics.droppedSlots
        XCTAssertEqual(recording.statusSummary?.droppedSlots, dropped)
        XCTAssertEqual(recording.statusSummary?.droppedWarning, true)
        XCTAssertEqual(recording.statusSummary?.droppedText.hasPrefix("Dropping frames: \(dropped) ("), true)
        // Each refresh raises at most one new warning per kind; post the dropped one, then the storage one.
        var posted: [String] = []
        for _ in 0..<3 {
            postNewWarning()
            posted = router.log
            recording.checkContext()
        }
        XCTAssertEqual(Set(posted), Set(["X9g", "X9f"]), "\(posted)")
        XCTAssertEqual(posted.filter { (id: String) -> Bool in id == "X9g" }.count, 2, "low, then critical: \(posted)")
        XCTAssertTrue(announcer.spoken.contains("recording|Storage almost full: under 1 min of recording left"), "\(announcer.spoken)")
        XCTAssertTrue(announcer.spoken.contains("recording|Recording is dropping frames"), "\(announcer.spoken)")
        recording.stop(.user)
        try await poll("finished") { recording.state == .idle }
    }

    func testUnknownStorageNeverWarns() throws {
        let source = try HandFedSource(device: try device())
        let context = ContextBox(.init(source: source, visualShown: true, outputLive: true, paused: false))
        let recording = makeCoordinator(context, storage: SetStorageProbe(nil))
        recording.toggle()
        try source.feed(at: 0)
        recording.checkContext()
        XCTAssertEqual(recording.statusSummary?.storageText, "Free storage unknown")
        XCTAssertNil(recording.statusSummary?.storageLevel)
        XCTAssertNil(recording.statusWarning)
        recording.stop(.user)
        waitUntil("finished") { recording.state == .idle }
    }

    func testWarningRowsAndTexts() {
        let dropped = RecordingStatusWarning(kind: .droppedFrames, storageLevel: .ok, secondsLeft: 900, sequence: 1)
        let low = RecordingStatusWarning(kind: .storage, storageLevel: .low, secondsLeft: 299, sequence: 2)
        let critical = RecordingStatusWarning(kind: .storage, storageLevel: .critical, secondsLeft: 12, sequence: 3)
        let rows: [StatusEvent] = [dropped, low, critical].map(StatusEventCatalog.recordingWarning)
        XCTAssertEqual(rows.map(\.id), ["X9f", "X9g", "X9g"])
        XCTAssertEqual(rows.map(\.announcement), ["Recording is dropping frames", "Storage low: about 4 min of recording left",
                                                  "Storage almost full: under 1 min of recording left"])
        XCTAssertTrue(rows.allSatisfy { (row: StatusEvent) -> Bool in row.kind == .recording && row.cause == .system })
        XCTAssertTrue(rows.allSatisfy { (row: StatusEvent) -> Bool in row.presentation == .persistent && row.visibleText == row.announcement })
    }

    // MARK: - T08: acceptance (REC-009-R6, S1)

    /// A solid red picture of the window's aspect, written as a PNG.
    private func redPicture(width: Int, height: Int) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { (c: UIGraphicsImageRendererContext) in
            UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let url = tempDirectory("picture").appendingPathExtension("png")
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }

    /// The probe's centre in a snapshot of the window (what was on screen), as RGBA bytes.
    private func snapshotPixel(_ window: UIWindow, at point: CGPoint) -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { (_: UIGraphicsImageRendererContext) in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cg = image.cgImage else { return [] }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let space = CGColorSpaceCreateDeviceRGB()
        pixel.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Void in
            guard let ctx = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(cg, in: CGRect(x: -point.x, y: point.y - CGFloat(cg.height) + 1, width: CGFloat(cg.width), height: CGFloat(cg.height)))
        }
        return pixel
    }

    /// Per frame: green-dominant pixels anywhere, and pixels outside the central disc that differ from the corner colour.
    private struct FrameCheck {
        var frames = 0
        var greenPixels = 0
        var offColourPixels = 0
        var reference: [Int] = []
        var worst = 0
    }

    /// The probe's colour after encoding (green-dominant), never the red visual or the spectrum's neutral tones.
    nonisolated static func isProbeGreen(_ r: Int, _ g: Int, _ b: Int) -> Bool { g > 150 && g > r + 60 && g > b + 60 }

    private func checkFrames(_ url: URL) async throws -> FrameCheck {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack] = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var check = FrameCheck()
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            check.frames += 1
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let width: Int = CVPixelBufferGetWidth(buffer)
            let height: Int = CVPixelBufferGetHeight(buffer)
            let row: Int = CVPixelBufferGetBytesPerRow(buffer)
            guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { continue }
            func bgr(_ x: Int, _ y: Int) -> (Int, Int, Int) {
                let p = base + y * row + x * 4
                return (Int(p[2]), Int(p[1]), Int(p[0]))
            }
            let corner = bgr(width / 20, height - 1 - height / 20)   // bottom-left: far from the probe and the disc
            check.reference = [corner.0, corner.1, corner.2]
            let cx = Double(width) / 2, cy = Double(height) / 2
            let disc = 0.45 * Double(min(width, height))
            for y in stride(from: 0, to: height, by: 2) {
                for x in stride(from: 0, to: width, by: 2) {
                    let (r, g, b) = bgr(x, y)
                    if Self.isProbeGreen(r, g, b) { check.greenPixels += 1 }
                    let dx = Double(x) - cx, dy = Double(y) - cy
                    if dx * dx + dy * dy <= disc * disc { continue }
                    let diff: Int = max(abs(r - corner.0), abs(g - corner.1), abs(b - corner.2))
                    check.worst = max(check.worst, diff)
                    if diff > 24 { check.offColourPixels += 1 }
                }
            }
        }
        XCTAssertEqual(reader.status, .completed)
        return check
    }

    func testOverlayIsNeverInTheRecording() async throws {
        let device = try device()
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        let photo = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        photo.content = .file(try redPicture(width: 240, height: 160))
        let context = ContextBox(.init(source: photo, visualShown: true, outputLive: true, paused: false))
        let outDirectory = tempDirectory("out")
        let recording = VideoRecordingCoordinator(directory: tempDirectory("work"), debugDirectory: outDirectory, checkInterval: nil,
                                                  storageProbe: SetStorageProbe(64_000_000_000), storageCheckInterval: nil) {
            context.value
        }
        // The window: the visual below, the app's SwiftUI overlay (green probe + the real status lines) above it.
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 240, height: 160)
        let root = UIViewController()
        window.rootViewController = root
        photo.view.frame = root.view.bounds
        photo.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(photo.view)
        let overlay = UIHostingController(rootView: ProbeOverlay(recording: recording))
        overlay.view.backgroundColor = .clear
        root.addChild(overlay)
        overlay.view.frame = root.view.bounds
        root.view.addSubview(overlay.view)
        overlay.didMove(toParent: root)
        window.isHidden = false
        window.layoutIfNeeded()
        photo.view.layoutIfNeeded()
        photo.resume()
        defer { photo.pause(); window.isHidden = true }
        try await poll("the picture is shown") { photo.framesShown > 2 }

        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
        let tap = try XCTUnwrap(photo.videoRecording)
        try await poll("frames recorded") { tap.recorder.statistics.written >= 12 }
        recording.checkContext()   // the status lines show while recording
        try await poll("the overlay is on screen") { recording.statusSummary != nil }
        let shown: [UInt8] = snapshotPixel(window, at: CGPoint(x: 20, y: 15))
        XCTAssertEqual(shown.count, 4)
        XCTAssertTrue(shown.count == 4 && shown[1] > 200 && shown[0] < 60 && shown[2] < 60,
                      "the probe was on screen during the recording: \(shown)")
        try await poll("more frames with the overlay up") { tap.recorder.statistics.written >= 24 }
        recording.stop(.user)
        try await poll("finished", timeout: 15) { recording.state == .idle && recording.probe.hasPrefix("video") }

        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: outDirectory.path).first { $0.hasSuffix(".mp4") })
        XCTAssertTrue(Self.isProbeGreen(Int(shown[0]), Int(shown[1]), Int(shown[2])), "the detector sees the on-screen probe")
        XCTAssertFalse(Self.isProbeGreen(255, 0, 0), "and not the visual's red")
        let check = try await checkFrames(outDirectory.appendingPathComponent(name))
        print("REC-009 acceptance: frames=\(check.frames) reference=\(check.reference) worst=\(check.worst) green=\(check.greenPixels) off=\(check.offColourPixels) probe=\(recording.probe)")
        XCTAssertGreaterThanOrEqual(check.frames, 20, recording.probe)
        XCTAssertGreaterThan(check.reference.first ?? 0, 150, "the visual is red: \(check.reference)")
        XCTAssertLessThan(check.reference.dropFirst().max() ?? 255, 80, "the visual is red: \(check.reference)")
        XCTAssertEqual(check.greenPixels, 0, "no probe pixel in any frame")
        XCTAssertEqual(check.offColourPixels, 0, "every frame is the visual's colour outside the spectrum disc (worst \(check.worst))")
        try? FileManager.default.removeItem(at: outDirectory)
    }
}
