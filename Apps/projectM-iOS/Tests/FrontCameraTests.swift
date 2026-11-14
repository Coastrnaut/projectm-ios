// FrontCameraTests.swift — CAM-002-T15 to T17: the front camera and mirror in the app with the
// stand-in camera (CAM-002-R1, R3 to R8, R10, R11; S2 to S4). The acceptance test (T16) composites one
// frame of the real Camera visual host offscreen, asks the compositor for that frame's REC-001 capture
// and encodes REC-003's output pass in the same command buffer, then reads pixels from all three: the
// red marker in the stand-in picture's top-left quarter must be on the same side in each, for mirror
// on and off and for both cameras. Simulator results are never device evidence. Host tests need a
// Metal device and skip without one.
import CameraLayer
import FrameCapture
import Metal
import os
import UIKit
import XCTest
@testable import projectM_iOS

/// The REC-001 capture handler's result, delivered on any thread.
private final class CaptureBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<CapturedPixels??>(initialState: nil)
    func set(_ pixels: CapturedPixels?) { lock.withLock { $0 = .some(pixels) } }
    var value: CapturedPixels?? { lock.withLock { $0 } }
}

@MainActor
final class FrontCameraTests: XCTestCase {
    private typealias Color = StubCameraFrameProvider.Color
    private static let red = Color(red: 255, green: 0, blue: 0)
    private static let blue = Color(red: 0, green: 0, blue: 255)
    private static let side = 128

    private func makeHost(_ scenario: CameraScenario = .granted, position: CameraPosition = .back, mirrored: Bool = false,
                          available: Set<CameraPosition> = [.back, .front]) throws -> (CameraVisualHost, StubCameraFrameProvider) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        var stub: StubCameraFrameProvider?
        let host = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32, position: position, mirrored: mirrored) {
            (device: MTLDevice) -> any CameraFrameProvider in
            let made = StubCameraFrameProvider(device: device, scenario: scenario,
                                               pattern: .marker(background: Self.blue, marker: Self.red),
                                               width: 64, height: 48, availablePositions: available)
            stub = made
            return made
        }
        return (host, try XCTUnwrap(stub))
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 10, _ condition: @escaping @MainActor () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "timed out: \(description)")
    }

    // MARK: - Settings (T15; R1, R3, R6)

    func testCameraSettingsDefaultPerPositionMirrorAndPersistence() throws {
        let suite = "FrontCameraTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.cameraPosition, .back, "Back by default")
        XCTAssertFalse(settings.cameraMirrored, "the rear camera is not mirrored by default")
        settings.cameraPosition = .front
        XCTAssertTrue(settings.cameraMirrored, "the front camera is mirrored by default")
        settings.cameraMirrored = false
        XCTAssertFalse(settings.cameraMirrorFront)
        XCTAssertFalse(settings.cameraMirrorBack, "each camera keeps its own setting")
        settings.cameraPosition = .back
        settings.cameraMirrored = true
        settings.cameraPosition = .front
        XCTAssertFalse(settings.cameraMirrored, "the front keeps its own (off)")

        let relaunched = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(relaunched.cameraPosition, .front, "remembered")
        XCTAssertFalse(relaunched.cameraMirrorFront)
        XCTAssertTrue(relaunched.cameraMirrorBack)
        XCTAssertEqual(relaunched.visual, .projectM, "the camera settings never choose or start the Camera visual")

        defaults.set("sideways", forKey: AppSettings.cameraPositionKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).cameraPosition, .back, "unknown → back")
        for key in [AppSettings.cameraPositionKey, AppSettings.cameraMirrorFrontKey, AppSettings.cameraMirrorBackKey] {
            XCTAssertTrue(AppSettings.allKeys.contains(key), "\(key) is cleared by -uitestResetNotice")
        }
    }

    func testCameraIsNeverRecordedInScenesOrCues() {
        XCTAssertEqual(SceneAutosaveCapture.recordedVisual(.camera, beforeCamera: .linearSpectrum), .linearSpectrum)
        XCTAssertEqual(ShowSceneSnapshot.recordedVisual(.camera, beforeCamera: .photo), .photo)
    }

    // MARK: - Badge, notices, status bar (T15, T17; R8, R10, R11)

    func testBadgeNamesTheFrontCamera() {
        XCTAssertEqual(CameraIndicator(state: .running, position: .front).label, "Front camera on")
        XCTAssertEqual(CameraIndicator(state: .starting, position: .front).accessibilityValue, "Starting")
        XCTAssertEqual(CameraIndicator(state: .running, position: .back).label, "Camera on")
        XCTAssertFalse(CameraIndicator(state: .idle, position: .front).isShown)
        XCTAssertFalse(AppCoordinator.systemOverlaysHidden(onVisualizer: true, controlsVisible: false, mode: .inAppPlayback, cameraShown: true),
                       "R8: the status bar stays whichever camera is shown")
    }

    func testNoticesForTheFrontCamera() throws {
        let missing = try XCTUnwrap(PermissionCatalog.cameraNotice(for: .unavailable, position: .front))
        XCTAssertEqual(missing.text, "No front camera is available. Showing the spectrum only.")
        XCTAssertFalse(missing.offersSettings)
        for state in [CameraFeedState.denied, .restricted] {
            XCTAssertEqual(PermissionCatalog.cameraNotice(for: state, position: .front), PermissionCatalog.cameraNotice(for: state, position: .back),
                           "\(state): FILE-013's catalog notice for both cameras")
            XCTAssertEqual(PermissionCatalog.cameraNotice(for: state, position: .front)?.offersSettings, true)
        }
        XCTAssertNil(PermissionCatalog.cameraNotice(for: .running, position: .front))
    }

    // MARK: - Host (T15, T17; R5, R7, R10)

    func testHostStartsTheChosenCameraAndSwitchesWithoutARestart() throws {
        let (host, stub) = try makeHost(position: .front, mirrored: true)
        defer { host.pause() }
        XCTAssertEqual(stub.state, .idle, "choosing a camera never starts it")
        XCTAssertEqual(host.cameraPosition, .front)
        XCTAssertTrue(host.mirrored)
        host.resume()
        XCTAssertEqual(stub.state, .running)
        XCTAssertEqual(stub.latestFrame()?.position, .front, "only the front camera ever ran")
        XCTAssertEqual(stub.startCount, 1)

        host.cameraPosition = .back
        XCTAssertTrue(host.isRunning, "the frame loop keeps running")
        XCTAssertEqual(stub.state, .running)
        XCTAssertEqual(stub.latestFrame()?.position, .back, "no picture of the front camera after the switch")
        XCTAssertEqual(stub.startCount, 1, "a switch is not a stop and start")
        XCTAssertEqual(host.view.accessibilityValue, "Live")
        host.mirrored = false
        XCTAssertEqual(stub.startCount, 1, "the mirror never touches the camera")
        XCTAssertEqual(stub.accessRequests, 0)
    }

    func testMissingFrontCameraShowsItsNoticeAndBackRecovers() throws {
        let (host, stub) = try makeHost(position: .front, available: [.back])
        defer { host.pause() }
        var reported: [CameraFeedState] = []
        host.onFeedStateChange = { (state: CameraFeedState) in reported.append(state) }
        host.resume()
        XCTAssertTrue(host.isRunning, "the spectrum keeps drawing")
        XCTAssertEqual(host.feedState, .unavailable)
        XCTAssertEqual(host.view.accessibilityValue, "No front camera")
        XCTAssertEqual(stub.accessRequests, 0)
        host.cameraPosition = .back
        XCTAssertEqual(host.feedState, .running, "the rear camera starts")
        XCTAssertEqual(reported, [.unavailable, .starting, .running])
    }

    // MARK: - The acceptance (T16; R4, S2, S3)

    /// One frame of the host composited offscreen; returns the marker side in the composite, the
    /// REC-001 capture and the REC-003 output, each "left", "right" or "none".
    private func markerSides(_ host: CameraVisualHost, time: UInt64) throws -> (composite: String, capture: String, recording: String) {
        let device = host.compositor.device
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let output = try texture(device, usage: [.renderTarget, .shaderRead])
        let recording = try texture(device, usage: [.renderTarget, .shaderRead])
        let box = CaptureBox()
        host.compositor.requestFrameCapture { (pixels: CapturedPixels?) in box.set(pixels) }
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertTrue(host.compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: time,
                                                contentScale: 2, reduceFlashing: false, audio: .empty))
        XCTAssertTrue(host.compositor.encodeOutput(into: recording, commandBuffer: commands), "REC-003's output pass")
        commands.commit()
        commands.waitUntilCompleted()
        waitUntil("REC-001 capture delivered") { box.value != nil }
        let captured = try XCTUnwrap(box.value ?? nil)
        XCTAssertEqual(captured.width, Self.side)
        let image = FrameColorConversion.rgba8(captured, policy: .opaqueOverBlack)
        let captureSide = side(left: rgb(image.pixel(x: 6, y: 6)), right: rgb(image.pixel(x: Self.side - 7, y: 6)))
        return (try side(of: output, queue: queue), captureSide, try side(of: recording, queue: queue))
    }

    private func texture(_ device: MTLDevice, usage: MTLTextureUsage) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: Self.side, height: Self.side, mipmapped: false)
        d.usage = usage
        d.storageMode = .private
        return try XCTUnwrap(device.makeTexture(descriptor: d))
    }

    private func rgb(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> (r: Int, g: Int, b: Int) {
        (Int(p.r), Int(p.g), Int(p.b))
    }

    private func side(left: (r: Int, g: Int, b: Int), right: (r: Int, g: Int, b: Int)) -> String {
        let leftRed: Bool = left.r > 200 && left.b < 60
        let rightRed: Bool = right.r > 200 && right.b < 60
        let leftBlue: Bool = left.b > 200 && left.r < 60
        let rightBlue: Bool = right.b > 200 && right.r < 60
        if leftRed && rightBlue { return "left" }
        if rightRed && leftBlue { return "right" }
        return "none (\(left), \(right))"
    }

    /// Reads a BGRA texture's top corners (6 px in from the edges, clear of the spectrum ring).
    private func side(of texture: MTLTexture, queue: MTLCommandQueue) throws -> String {
        let rowBytes: Int = texture.width * 4
        let length: Int = rowBytes * texture.height
        let buffer = try XCTUnwrap(queue.device.makeBuffer(length: length, options: .storageModeShared))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: length)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let bytes = buffer.contents().bindMemory(to: UInt8.self, capacity: length)
        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i: Int = y * rowBytes + x * 4
            return (Int(bytes[i + 2]), Int(bytes[i + 1]), Int(bytes[i]))
        }
        return side(left: pixel(6, 6), right: pixel(texture.width - 7, 6))
    }

    /// The roadmap acceptance: "Mirror toggle changes preview and saved output consistently."
    func testMirrorTogglesPreviewSavedFrameAndRecordingTheSameWay() throws {
        let (host, stub) = try makeHost()
        defer { host.pause() }
        host.resume()
        var time: UInt64 = 1_000_000_000
        var rows: [String] = []
        for position in [CameraPosition.front, .back] {
            host.cameraPosition = position
            for mirror in [true, false] {
                host.mirrored = mirror
                time += 16_666_667
                let sides = try markerSides(host, time: time)
                let expected: String = mirror ? "right" : "left"
                let label = "\(position) mirror \(mirror ? "on" : "off")"
                XCTAssertEqual(sides.composite, expected, "\(label): screen")
                XCTAssertEqual(sides.capture, expected, "\(label): REC-001 saved frame")
                XCTAssertEqual(sides.recording, expected, "\(label): REC-003 recorded frame")
                rows.append("\(label): screen \(sides.composite), saved frame \(sides.capture), recording \(sides.recording)")
            }
        }
        XCTAssertEqual(stub.startCount, 1, "neither the mirror nor the switch restarted the camera")
        print("CAM-002 mirror consistency:\n" + rows.joined(separator: "\n"))
    }
}
