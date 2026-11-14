// CameraCropTests.swift — CAM-007-T10, T12: the camera crop in the app with the stand-in camera
// (CAM-007-R1, R5, R6, R8; S4, S5). Settings persistence goes through a new `AppSettings` on the same
// defaults (a relaunch). The acceptance (T12) composites the real Camera visual host offscreen at a
// portrait and then a landscape size, asks the compositor for that frame's REC-001 capture, and reads
// pixels at points near the edges (clear of the spectrum ring): each must be the class (marker red,
// background blue or bar black) the camera picture geometry predicts, in the composite and in the
// saved frame alike. Simulator results are never device evidence. Host tests need a Metal device and
// skip without one.
import CameraLayer
import FrameCapture
import Metal
import os
import UIKit
import XCTest
@testable import projectM_iOS

/// The REC-001 capture handler's result, delivered on any thread.
private final class CropCaptureBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<CapturedPixels??>(initialState: nil)
    func set(_ pixels: CapturedPixels?) { lock.withLock { $0 = .some(pixels) } }
    var value: CapturedPixels?? { lock.withLock { $0 } }
}

@MainActor
final class CameraCropTests: XCTestCase {
    private typealias Color = StubCameraFrameProvider.Color
    private static let red = Color(red: 255, green: 0, blue: 0)
    private static let blue = Color(red: 0, green: 0, blue: 255)
    private static let stubWidth = 64
    private static let stubHeight = 48

    private func makeHost(crop: CameraCrop = .fill) throws -> (CameraVisualHost, StubCameraFrameProvider) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        var stub: StubCameraFrameProvider?
        let host = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32, crop: crop) {
            (device: MTLDevice) -> any CameraFrameProvider in
            let made = StubCameraFrameProvider(device: device, scenario: .granted,
                                               pattern: .marker(background: Self.blue, marker: Self.red),
                                               width: Self.stubWidth, height: Self.stubHeight)
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

    // MARK: - Settings (T10; R1, R6, S4)

    func testCropSettingsDefaultsPersistenceAndReset() throws {
        let suite = "CameraCropTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.cameraCrop, .fill, "Fill, Center, 1× by default")
        settings.cameraCropMode = .fit
        settings.cameraCropAnchor = .top
        settings.cameraZoom = 2
        settings.cameraPosition = .front
        XCTAssertEqual(settings.cameraCrop, CameraCrop(mode: .fit, anchor: .top, zoom: 2), "one framing for both cameras")
        settings.cameraPosition = .back
        XCTAssertEqual(settings.cameraCrop, CameraCrop(mode: .fit, anchor: .top, zoom: 2))

        let relaunched = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(relaunched.cameraCrop, CameraCrop(mode: .fit, anchor: .top, zoom: 2), "remembered through a relaunch")
        XCTAssertEqual(relaunched.visual, .projectM, "the crop never chooses or starts the Camera visual")

        relaunched.cameraZoom = 2.5
        XCTAssertEqual(relaunched.cameraZoom, 1, "not a step → 1")
        defaults.set("sideways", forKey: AppSettings.cameraCropModeKey)
        defaults.set("left", forKey: AppSettings.cameraCropAnchorKey)
        defaults.set(7.0, forKey: AppSettings.cameraZoomKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).cameraCrop, .fill, "unknown values → defaults")
        for key in [AppSettings.cameraCropModeKey, AppSettings.cameraCropAnchorKey, AppSettings.cameraZoomKey] {
            XCTAssertTrue(AppSettings.allKeys.contains(key), "\(key) is cleared by -uitestResetNotice")
        }
    }

    func testCameraIsNeverRecordedInScenesOrCues() {
        XCTAssertEqual(SceneAutosaveCapture.recordedVisual(.camera, beforeCamera: .oscilloscope), .oscilloscope)
        XCTAssertEqual(ShowSceneSnapshot.recordedVisual(.camera, beforeCamera: .linearSpectrum), .linearSpectrum)
    }

    // MARK: - Host (T10; R5, S5)

    func testHostForwardsTheCropWithoutARestart() throws {
        let crop = CameraCrop(mode: .fit, anchor: .bottom, zoom: 1.5)
        let (host, stub) = try makeHost(crop: crop)
        defer { host.pause() }
        XCTAssertEqual(host.crop, crop, "created with the stored crop")
        XCTAssertEqual(stub.state, .idle, "a crop never starts the camera")
        host.resume()
        XCTAssertEqual(stub.startCount, 1)
        host.crop = .fill
        XCTAssertEqual(host.camera.crop, .fill, "forwarded to the camera layer")
        XCTAssertTrue(host.isRunning)
        XCTAssertEqual(stub.startCount, 1, "a crop change is not a stop and start")
        XCTAssertEqual(stub.accessRequests, 0)
    }

    // MARK: - The acceptance (T12; R3, R4, R8)

    private enum Kind: String {
        case red, blue, black, mixed
    }

    private func kind(_ p: (r: Int, g: Int, b: Int)) -> Kind {
        if p.r > 200 && p.b < 60 && p.g < 60 { return .red }
        if p.b > 200 && p.r < 60 && p.g < 60 { return .blue }
        if p.r < 30 && p.g < 30 && p.b < 30 { return .black }
        return .mixed
    }

    /// Sample points (0…1) near the edges, clear of the central spectrum ring.
    private let samples: [(x: Float, y: Float)] = [(0.06, 0.06), (0.94, 0.06), (0.06, 0.94), (0.94, 0.94), (0.5, 0.04), (0.5, 0.96),
                                                   (0.04, 0.5), (0.96, 0.5), (0.25, 0.04), (0.75, 0.96)]

    /// The kind the geometry predicts at a sample, or nil within reach of a marker or picture edge.
    private func predicted(_ g: CameraPictureGeometry, x: Float, y: Float) -> Kind? {
        let a: Float = g.offsetX + x * g.visibleWidth
        let b: Float = g.offsetY + y * g.visibleHeight
        let margin: Float = 0.04
        let nearPictureEdge: Bool = abs(a) < margin || abs(a - 1) < margin || abs(b) < margin || abs(b - 1) < margin
        if nearPictureEdge { return nil }
        guard g.contains(x: x, y: y) else { return .black }
        let t = g.textureCoordinate(x: x, y: y)
        if abs(t.x - 0.5) < margin || abs(t.y - 0.5) < margin { return nil }
        return t.x < 0.5 && t.y < 0.5 ? .red : .blue
    }

    private func texture(_ device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return try XCTUnwrap(device.makeTexture(descriptor: d))
    }

    /// Reads a BGRA texture into (r, g, b) rows.
    private func read(_ texture: MTLTexture, queue: MTLCommandQueue) throws -> [(r: Int, g: Int, b: Int)] {
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
        var pixels: [(r: Int, g: Int, b: Int)] = []
        pixels.reserveCapacity(texture.width * texture.height)
        for i in 0..<(texture.width * texture.height) {
            let o: Int = i * 4
            pixels.append((Int(bytes[o + 2]), Int(bytes[o + 1]), Int(bytes[o])))
        }
        return pixels
    }

    /// The roadmap acceptance: "Portrait-to-landscape rotation preserves chosen crop behavior", on the
    /// screen's composite and the saved frame (REC-001), mirror on and off.
    func testPortraitToLandscapeKeepsTheCropOnScreenAndInTheSavedFrame() throws {
        let (host, stub) = try makeHost()
        defer { host.pause() }
        host.resume()
        let device = host.compositor.device
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let sizes: [(name: String, width: Int, height: Int)] = [("portrait", 90, 160), ("landscape", 160, 90)]
        let crops: [CameraCrop] = [.fill, CameraCrop(mode: .fill, anchor: .top, zoom: 2), CameraCrop(mode: .fit, anchor: .top, zoom: 1)]
        var time: UInt64 = 1_000_000_000
        var rows: [String] = []
        var checked: Int = 0
        for crop in crops {
            for mirror in [false, true] {
                host.crop = crop
                host.mirrored = mirror
                for size in sizes {
                    time += 16_666_667
                    host.compositor.resetFlashHistory()   // each case is a new picture, not a flash
                    let output = try texture(device, width: size.width, height: size.height)
                    let box = CropCaptureBox()
                    host.compositor.requestFrameCapture { (pixels: CapturedPixels?) in box.set(pixels) }
                    let commands = try XCTUnwrap(queue.makeCommandBuffer())
                    XCTAssertTrue(host.compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: time,
                                                            contentScale: 2, reduceFlashing: false, audio: .empty))
                    commands.commit()
                    commands.waitUntilCompleted()
                    waitUntil("REC-001 capture delivered") { box.value != nil }
                    let captured = try XCTUnwrap(box.value ?? nil)
                    let image = FrameColorConversion.rgba8(captured, policy: .opaqueOverBlack)
                    let screen = try read(output, queue: queue)
                    let g = CameraPictureGeometry(pictureWidth: Self.stubWidth, pictureHeight: Self.stubHeight, rotation: .none,
                                                  outputWidth: size.width, outputHeight: size.height, mirrored: mirror, crop: crop)
                    let label: String = "\(crop.mode.rawValue)/\(crop.anchor.rawValue)/\(crop.zoom) mirror \(mirror) \(size.name)"
                    var kinds: [String] = []
                    for sample in samples {
                        guard let expected = predicted(g, x: sample.x, y: sample.y) else { continue }
                        let px: Int = min(Int(sample.x * Float(size.width)), size.width - 1)
                        let py: Int = min(Int(sample.y * Float(size.height)), size.height - 1)
                        let onScreen: Kind = kind(screen[py * size.width + px])
                        let p = image.pixel(x: px, y: py)
                        let saved: Kind = kind((Int(p.r), Int(p.g), Int(p.b)))
                        XCTAssertEqual(onScreen, expected, "\(label): screen at (\(sample.x), \(sample.y))")
                        XCTAssertEqual(saved, expected, "\(label): saved frame at (\(sample.x), \(sample.y))")
                        kinds.append(expected.rawValue)
                        checked += 1
                    }
                    rows.append(label + ": " + kinds.joined(separator: ","))
                }
            }
        }
        XCTAssertGreaterThan(checked, 60, "enough unambiguous sample points")
        XCTAssertEqual(stub.startCount, 1, "neither crop, mirror nor size changes restarted the camera")
        print("CAM-007 crop consistency (screen = saved frame = geometry):\n" + rows.joined(separator: "\n"))
    }
}
