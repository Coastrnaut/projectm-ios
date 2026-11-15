// CameraPersonMaskTests.swift — CAM-008-T14: the person mask in the app with the stand-in camera and a
// fixture segmenter (CAM-008-R1, R5, R8, R9). Settings persistence goes through a new `AppSettings` on
// the same defaults (a relaunch). The host tests composite the real Camera visual offscreen and read a
// corner pixel (outside the fixture person, clear of the spectrum ring): Person makes it black (the
// camera layer is transparent there), Background and an unavailable segmenter keep the camera's red.
// The pixel-exact acceptance is the package's PersonMaskLayerTests. Simulator results are never device
// evidence. Host tests need a Metal device and skip without one.
import CameraLayer
import Metal
import XCTest
@testable import projectM_iOS

@MainActor
final class CameraPersonMaskTests: XCTestCase {
    private static let red = StubCameraFrameProvider.Color(red: 255, green: 0, blue: 0)
    /// The middle half of the stand-in's 64 × 48 picture.
    private static let person = PersonMaskBitmap.rectangle(width: 64, height: 48, x0: 16, y0: 12, x1: 48, y1: 36)

    // MARK: - Settings (R9)

    func testChoiceDefaultsPersistsAndIsBackedUp() throws {
        let suite = "CameraPersonMaskTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.cameraPersonMask, .off, "Off by default")
        settings.cameraPersonMask = .background
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).cameraPersonMask, .background, "kept after a relaunch")
        defaults.set("silhouette", forKey: AppSettings.cameraPersonMaskKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).cameraPersonMask, .off, "unknown values → Off")
        XCTAssertTrue(AppSettings.allKeys.contains(AppSettings.cameraPersonMaskKey), "reset with the other settings")
        XCTAssertEqual(AppSettings.cameraPersonMaskKey, "settings.camera.personMask")
    }

    // MARK: - Row (R5, R8)

    func testNotesNameEveryReasonTheMaskCannotBeDrawn() {
        XCTAssertNil(CameraPersonMaskRow.note(for: .available))
        XCTAssertEqual(CameraPersonMaskRow.note(for: .unsupported), "Person mask isn't supported on this device.")
        XCTAssertEqual(CameraPersonMaskRow.note(for: .failed), "Person mask stopped after an error. The camera picture is shown in full.")
        XCTAssertEqual(CameraPersonMaskRow.note(for: .paused), "Person mask is paused while the device is warm.")
    }

    func testPlanFollowsHeatAndPower() {
        XCTAssertEqual(CameraVisualHost.personMaskPlan(thermal: .nominal, lowPower: false, profile: .standard),
                       .run(quality: .balanced, stride: 2))
        XCTAssertEqual(CameraVisualHost.personMaskPlan(thermal: .fair, lowPower: false, profile: .batterySaver),
                       .run(quality: .fast, stride: 3), "PERF-008 battery saver")
        XCTAssertEqual(CameraVisualHost.personMaskPlan(thermal: .nominal, lowPower: true, profile: .standard),
                       .run(quality: .fast, stride: 3), "Low Power Mode")
        XCTAssertEqual(CameraVisualHost.personMaskPlan(thermal: .serious, lowPower: false, profile: .standard), .paused)
    }

    // MARK: - Host (R1, R5)

    private func makeHost(mode: CameraPersonMaskMode, segmenter: any PersonSegmenting) throws -> (CameraVisualHost, StubCameraFrameProvider) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        var stub: StubCameraFrameProvider?
        let host = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32, provider: { (device: MTLDevice) -> any CameraFrameProvider in
            let made = StubCameraFrameProvider(device: device, scenario: .granted, pattern: .solid(Self.red), width: 64, height: 48)
            stub = made
            return made
        }, personMask: mode, segmenter: segmenter)
        return (host, try XCTUnwrap(stub))
    }

    private func waitUntil(_ description: String, _ condition: @escaping @MainActor () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(condition(), "timed out: \(description)")
    }

    /// The composite's top-left corner pixel (r, g, b), 160 × 120 (the picture's own 4:3, so Fill crops nothing).
    private func corner(_ host: CameraVisualHost) throws -> (r: Int, g: Int, b: Int) {
        let device = host.compositor.device
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 160, height: 120, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let output = try XCTUnwrap(device.makeTexture(descriptor: d))
        host.compositor.resetFlashHistory()
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertTrue(host.compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: 1_000_000_000,
                                                contentScale: 2, reduceFlashing: false, audio: .empty))
        let buffer = try XCTUnwrap(device.makeBuffer(length: 4, options: .storageModeShared))
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: output, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 8, y: 8, z: 0),
                  sourceSize: MTLSize(width: 1, height: 1, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: 4, destinationBytesPerImage: 4)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let bytes = buffer.contents().bindMemory(to: UInt8.self, capacity: 4)
        return (Int(bytes[2]), Int(bytes[1]), Int(bytes[0]))
    }

    func testPersonAndBackgroundMaskTheCameraWithoutARestart() throws {
        let (host, stub) = try makeHost(mode: .person, segmenter: FixturePersonSegmenter(mask: Self.person))
        defer { host.pause() }
        XCTAssertEqual(host.personMask, .person, "created with the stored choice")
        XCTAssertEqual(stub.state, .idle, "the choice never starts the camera")
        host.resume()
        waitUntil("first mask") { host.camera.personMasker?.latestMask() != nil }
        let person = try corner(host)
        XCTAssertLessThan(person.r, 30, "Person: outside the person the camera layer is transparent (black composite)")
        XCTAssertGreaterThan(host.camera.framesMasked, 0)
        host.personMask = .background
        stub.deliverNextPicture()
        waitUntil("mask after the change") { host.camera.personMasker?.latestMask() != nil }
        let background = try corner(host)
        XCTAssertGreaterThan(background.r, 200, "Background: outside the person the camera picture is drawn")
        XCTAssertEqual(stub.startCount, 1, "changing the choice is not a stop and start")
        XCTAssertEqual(host.personMaskAvailability, .available)
    }

    func testUnsupportedAndFailingSegmentationDrawTheFullPicture() throws {
        let cases: [(String, FixturePersonSegmenter, PersonMaskAvailability)] = [
            ("unsupported", FixturePersonSegmenter(mask: Self.person, supported: false), .unsupported),
            ("failing", FixturePersonSegmenter(mask: Self.person, fails: true), .failed),
        ]
        for (name, segmenter, expected) in cases {
            let (host, _) = try makeHost(mode: .person, segmenter: segmenter)
            var reported: [PersonMaskAvailability] = []
            host.onPersonMaskAvailabilityChange = { (a: PersonMaskAvailability) -> Void in reported.append(a) }
            host.resume()
            waitUntil(name + " availability") { host.personMaskAvailability == expected }
            let pixel = try corner(host)
            XCTAssertGreaterThan(pixel.r, 200, name + ": the camera picture is drawn in full")
            XCTAssertEqual(host.camera.framesMasked, 0, name + ": no frame drawn with a mask")
            if expected == .failed {
                waitUntil("failure reported on the main thread") { reported == [.failed] }
            }
            host.pause()
        }
    }
}
