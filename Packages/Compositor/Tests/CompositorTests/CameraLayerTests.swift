// CAM-001-T09, T16, T20: the camera layer through the real Metal compositor with the stand-in camera
// (CAM-001-R2, R3, R4-R8, R13, S1, S5). 64 × 64 outputs; skipped without a Metal device. No test asks
// for real camera access.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import CameraLayer
import Compositor
import Metal
import SpectrumLayers
import VisualEffects
import VisualGenerators
import XCTest

final class CameraLayerTests: XCTestCase {
    private typealias Color = StubCameraFrameProvider.Color
    private let red = Color(red: 255, green: 0, blue: 0)
    private let green = Color(red: 0, green: 255, blue: 0)
    private let blue = Color(red: 0, green: 0, blue: 255)

    /// The sRGB transfer function (display code → linear light).
    private func linear(_ code: UInt8) -> Float {
        let c = Float(code) / 255
        return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    private func make(_ rig: GPURig, _ scenario: CameraScenario, pattern: StubCameraFrameProvider.Pattern? = nil,
                      width: Int = 64, height: Int = 48, rotation: CameraRotation = .none)
        throws -> (StubCameraFrameProvider, CameraLayerSource, Compositor) {
        let stub = StubCameraFrameProvider(device: rig.device, scenario: scenario, pattern: pattern ?? .solid(Color(red: 188, green: 188, blue: 188)),
                                           width: width, height: height, rotation: rotation)
        let layer = CameraLayerSource(provider: stub)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        return (stub, layer, compositor)
    }

    /// Pixels of row `y`, columns `xs`.
    private func pixels(_ all: [Pixel], y: Int, xs: Range<Int>, width: Int = 64) -> [Pixel] {
        xs.map { all[y * width + $0] }
    }

    // MARK: - US1: grant shows frames (S1, R2, R3)

    func testSolidCameraColorReadsBackAsItsLinearValue() throws {
        let rig = try GPURig()
        let (stub, layer, compositor) = try make(rig, .granted)
        XCTAssertEqual(layer.fallback, .transparent)
        layer.start()
        XCTAssertEqual(stub.state, .running)
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
        let v = linear(188)
        XCTAssertEqual(v, 0.5029, accuracy: 0.001)
        assertAll(try rig.read(output), equal: Pixel(v, v, v, 1), "sRGB 188 reads back linear")
        try rig.frame(compositor, into: output, time: 16_666_667)
        XCTAssertEqual(layer.framesShown, 2, "every frame shows the camera picture")
    }

    func testWidePictureFillsASquareWithItsMiddleStripe() throws {
        let rig = try GPURig()
        let (_, layer, compositor) = try make(rig, .granted, pattern: .columns([red, green, blue]), width: 30, height: 10)
        layer.start()
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        let all = try rig.read(output)
        for y in [0, 31, 63] {   // the filtered edge columns blend with the neighbouring stripes
            assertAll(pixels(all, y: y, xs: 3..<61), equal: Pixel(0, 1, 0, 1), "row \(y): only the middle (green) stripe")
        }
    }

    func testQuarterTurnPutsTheTopOfThePictureOnTheRight() throws {
        let rig = try GPURig()
        let (_, layer, compositor) = try make(rig, .granted, pattern: .rows([red, blue]), width: 16, height: 16, rotation: .clockwise90)
        layer.start()
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        let all = try rig.read(output)
        for y in [2, 32, 61] {
            assertAll(pixels(all, y: y, xs: 2..<30), equal: Pixel(0, 0, 1, 1), "left half is the picture's bottom (blue)")
            assertAll(pixels(all, y: y, xs: 34..<62), equal: Pixel(1, 0, 0, 1), "right half is the picture's top (red)")
        }
    }

    func testSpectrumLayerCompositesOverTheCamera() throws {
        let rig = try GPURig()
        let stub = StubCameraFrameProvider(device: rig.device, scenario: .granted, pattern: .solid(blue))
        let camera = CameraLayerSource(provider: stub)
        let transparent = LinearColor(red: 0, green: 0, blue: 0, alpha: 0)
        let generator = try CircularSpectrumGenerator(device: rig.device, pixelFormat: .rgba16Float,
                                                      configuration: CircularSpectrumConfiguration(barCount: .b16, background: transparent))
        let spectrum = try SpectrumLayerSource(device: rig.device, generator: generator)
        let compositor = try Compositor(device: rig.device, layers: [camera, spectrum])
        camera.start()
        let audio = LayerAudioBuffer()
        audio.set(frame: nil, bands: [Float](repeating: 1, count: 16), events: [])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1, audio: audio.context)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .rendered)
        let all = try rig.read(output)
        XCTAssertEqual(all.filter { $0.w < 0.999 }.count, 0, "the camera makes the whole picture opaque")
        XCTAssertEqual(all[0], Pixel(0, 0, 1, 1), "a corner outside the ring shows the camera")
        XCTAssertGreaterThan(all.filter { $0.x > 0.05 || $0.y > 0.05 }.count, 20, "the spectrum's bars are drawn over it")
    }

    // MARK: - US2: denial and no camera fall back (R4-R6)

    func testRefusedOrMissingCameraShowsTheTransparentFallback() throws {
        let rig = try GPURig()
        let expected: [CameraScenario: CameraFeedState] = [.denied: .denied, .restricted: .restricted, .unavailable: .unavailable,
                                                           .notDeterminedDeny: .denied]
        for (scenario, state) in expected {
            let (stub, layer, compositor) = try make(rig, scenario)
            layer.start()
            XCTAssertEqual(stub.state, state, "\(scenario)")
            XCTAssertEqual(stub.accessRequests, scenario == .notDeterminedDeny ? 1 : 0, "\(scenario): asked only when never decided")
            let output = try rig.output()
            try rig.frame(compositor, into: output, time: 1)
            XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady), "\(scenario)")
            assertAll(try rig.read(output), equal: .zero, "\(scenario): nothing of the camera")
            XCTAssertEqual(layer.framesShown, 0)
        }
    }

    func testPromptAnsweredAllowShowsFramesAndIsNotAskedAgain() throws {
        let rig = try GPURig()
        let (stub, layer, compositor) = try make(rig, .notDeterminedGrant)
        var seen: [CameraFeedState] = []
        stub.onStateChange = { seen.append($0) }
        layer.start()
        XCTAssertEqual(seen, [.requestingAccess, .starting, .running])
        try rig.frame(compositor, into: try rig.output(), time: 1)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
        layer.stop()
        layer.start()
        XCTAssertEqual(stub.accessRequests, 1, "the answer is kept: no second prompt")
        XCTAssertEqual(stub.state, .running)
    }

    func testNoPictureBeforeStart() throws {
        let rig = try GPURig()
        let (stub, _, compositor) = try make(rig, .granted)
        XCTAssertEqual(stub.state, .idle)
        XCTAssertNil(stub.latestFrame())
        try rig.frame(compositor, into: try rig.output(), time: 1)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady), "the camera never starts by itself")
        XCTAssertEqual(stub.startCount, 0)
    }

    // MARK: - US3: stop, interruption, failure (R7-R9, S5)

    func testStopDropsThePictureAtOnce() throws {
        let rig = try GPURig()
        let (stub, layer, compositor) = try make(rig, .granted)
        layer.start()
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertNotNil(stub.latestFrame())
        layer.stop()
        XCTAssertEqual(stub.state, .idle)
        XCTAssertNil(stub.latestFrame(), "no picture is kept after stop (R9)")
        try rig.frame(compositor, into: output, time: 2)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady))
        assertAll(try rig.read(output), equal: .zero, "nothing shown after stop")
        layer.stop()
        XCTAssertEqual(stub.stopCount, 1, "stop is idempotent")
    }

    func testInterruptionFallsBackAndItsEndBringsThePictureBack() throws {
        let rig = try GPURig()
        let (stub, layer, compositor) = try make(rig, .granted, pattern: .solid(red))
        layer.start()
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        stub.interrupt()
        XCTAssertEqual(stub.state, .interrupted)
        XCTAssertNotNil(stub.state.notice)
        try rig.frame(compositor, into: output, time: 2)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady), "the next frame already falls back (S5)")
        assertAll(try rig.read(output), equal: .zero, "no frozen picture while interrupted")
        stub.endInterruption()
        try rig.frame(compositor, into: output, time: 3)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
        assertAll(try rig.read(output), equal: Pixel(1, 0, 0, 1), "the picture is back")
        stub.fail()
        XCTAssertEqual(stub.state, .failed)
        try rig.frame(compositor, into: output, time: 4)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady), "a runtime error falls back")
    }

    func testClosedSlotRefusesLatePictures() throws {
        let rig = try GPURig()
        let slot = LatestCameraFrame()
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 2, height: 2, mipmapped: false)
        let texture = try XCTUnwrap(rig.device.makeTexture(descriptor: d))
        XCTAssertFalse(slot.store(texture), "closed until opened")
        slot.open()
        slot.setRotation(.clockwise270)
        XCTAssertTrue(slot.store(texture))
        XCTAssertEqual(slot.read()?.rotation, .clockwise270)
        XCTAssertEqual(slot.read()?.sequence, 1)
        slot.close()
        XCTAssertNil(slot.read())
        XCTAssertFalse(slot.store(texture), "a picture arriving after stop is dropped")
    }

    // MARK: - CAM-002-T08: mirror and camera switch (CAM-002-R3, R5, R7, R10; S1, S3, S4)

    /// Red marker in the camera picture's top-left quarter, blue elsewhere.
    private var marker: StubCameraFrameProvider.Pattern { .marker(background: blue, marker: red) }

    /// Which side of the output's top half shows the marker: "left", "right" or "none".
    private func markerSide(_ all: [Pixel]) -> String {
        let left: Pixel = all[16 * 64 + 8]
        let right: Pixel = all[16 * 64 + 56]
        if left.x > 0.9 && right.z > 0.9 { return "left" }
        if right.x > 0.9 && left.z > 0.9 { return "right" }
        return "none"
    }

    func testMirrorFlipsTheMarkerFromTheNextFrameWithoutARestart() throws {
        let rig = try GPURig()
        let (stub, layer, compositor) = try make(rig, .granted, pattern: marker, width: 16, height: 16)
        layer.start()
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertEqual(markerSide(try rig.read(output)), "left", "unmirrored: the picture's left is on the left")
        layer.mirrored = true
        try rig.frame(compositor, into: output, time: 2)
        XCTAssertEqual(markerSide(try rig.read(output)), "right", "mirrored from the next frame")
        layer.mirrored = false
        try rig.frame(compositor, into: output, time: 3)
        XCTAssertEqual(markerSide(try rig.read(output)), "left")
        XCTAssertEqual(stub.startCount, 1, "the mirror never restarts the camera")
        XCTAssertEqual(stub.accessRequests, 0)
    }

    func testMirrorAppliesAfterTheQuarterTurn() throws {
        let rig = try GPURig()
        // Rows red (top) / blue (bottom), turned 90°: red on the right. Mirrored: red on the left.
        let (_, layer, compositor) = try make(rig, .granted, pattern: .rows([red, blue]), width: 16, height: 16, rotation: .clockwise90)
        layer.start()
        layer.mirrored = true
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        let all = try rig.read(output)
        assertAll(pixels(all, y: 32, xs: 2..<30), equal: Pixel(1, 0, 0, 1), "mirrored upright picture: its top (red) on the left")
        assertAll(pixels(all, y: 32, xs: 34..<62), equal: Pixel(0, 0, 1, 1), "and its bottom (blue) on the right")
    }

    func testSwitchingToTheFrontCameraShowsOnlyFrontPictures() throws {
        let rig = try GPURig()
        let (stub, layer, compositor) = try make(rig, .granted, pattern: marker, width: 16, height: 16)
        var seen: [CameraFeedState] = []
        stub.onStateChange = { seen.append($0) }
        layer.start()
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertEqual(stub.latestFrame()?.position, .back)
        stub.select(.front)
        XCTAssertEqual(stub.position, .front)
        XCTAssertEqual(stub.latestFrame()?.position, .front, "after the switch only front pictures")
        XCTAssertFalse(seen.contains(.idle), "a switch never passes through idle (the badge stays): \(seen)")
        try rig.frame(compositor, into: output, time: 2)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
        XCTAssertEqual(stub.selectCount, 1)
        stub.select(.front)
        XCTAssertEqual(stub.selectCount, 1, "same position: no-op")
    }

    func testAPictureOfThePreviousCameraIsNeverDrawn() throws {
        let rig = try GPURig()
        let provider = StaleFrameProvider(device: rig.device)
        let layer = CameraLayerSource(provider: provider)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered, "a back picture while the back camera is chosen")
        provider.position = .front   // the slot still holds the back camera's picture
        try rig.frame(compositor, into: output, time: 2)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady), "the old camera's picture is not drawn")
        assertAll(try rig.read(output), equal: .zero, "nothing of the previous camera")
    }

    func testMissingFrontCameraIsUnavailableWithoutAskingAndBackStillWorks() throws {
        let rig = try GPURig()
        let stub = StubCameraFrameProvider(device: rig.device, scenario: .notDeterminedGrant, position: .front, availablePositions: [.back])
        let layer = CameraLayerSource(provider: stub)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        layer.start()
        XCTAssertEqual(stub.state, .unavailable)
        XCTAssertEqual(stub.accessRequests, 0, "no camera at this position: nothing asked")
        try rig.frame(compositor, into: try rig.output(), time: 1)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady))
        stub.select(.back)
        XCTAssertEqual(stub.state, .running, "the rear camera starts")
        XCTAssertEqual(stub.accessRequests, 1)
    }

    func testFrontChosenBeforeTheFirstPromptStartsTheFrontCamera() throws {
        let rig = try GPURig()
        let (stub, layer, _) = try make(rig, .notDeterminedGrant)
        stub.select(.front)
        XCTAssertEqual(stub.state, .idle, "choosing a camera never starts it")
        layer.start()
        XCTAssertEqual(stub.state, .running)
        XCTAssertEqual(stub.latestFrame()?.position, .front)
        XCTAssertEqual(stub.accessRequests, 1, "one permission for every camera")
    }
}

/// Holds one back-camera picture whatever position is chosen (the slot race CAM-002-R7 guards against).
private final class StaleFrameProvider: CameraFrameProvider {
    let state: CameraFeedState = .running
    var onStateChange: ((CameraFeedState) -> Void)?
    var position: CameraPosition = .back
    private let slot = LatestCameraFrame()

    init(device: MTLDevice) {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 2, height: 2, mipmapped: false)
        d.usage = [.shaderRead]
        if let texture = device.makeTexture(descriptor: d) {
            let white = [UInt8](repeating: 255, count: 16)
            white.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                texture.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: 8)
            }
            slot.open()
            slot.store(texture, position: .back)
        }
    }

    func start() {}
    func stop() {}
    func latestFrame() -> CameraFrame? { slot.read() }
    func select(_ position: CameraPosition) { self.position = position }
}
#endif
