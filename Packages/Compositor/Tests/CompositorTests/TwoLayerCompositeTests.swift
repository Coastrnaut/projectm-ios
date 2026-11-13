// CMP-001-T06 (US1, the roadmap acceptance "Two dummy sources composite without direct engine
// coupling"; CMP-001-S1) and T08 (US2, the explicit clock and music; CMP-001-S2). GPU tests at
// 64 × 64 through the real Metal compositor; skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import AnalysisFeatures
import Compositor
import Metal
import XCTest

final class TwoLayerCompositeTests: XCTestCase {
    private let blue = Pixel(0, 0, 1, 1)
    private let halfRed = Pixel(0.5, 0, 0, 0.5)   // premultiplied: red at 50 % alpha

    func testHalfRedOverOpaqueBlueIsTheOverResult() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue), SolidLayer("red", color: halfRed)])
        for format in [MTLPixelFormat.rgba16Float, .bgra8Unorm] {
            let output = try rig.output(format)
            XCTAssertTrue(try rig.frame(compositor, into: output, time: 1_000_000_000))
            // over: src + dst × (1 − src.a) = (0.5, 0, 0, 0.5) + (0, 0, 1, 1) × 0.5
            assertAll(try rig.read(output), equal: Pixel(0.5, 0, 0.5, 1), "half red over blue (\(format.rawValue))")
            XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
            XCTAssertEqual(compositor.outcome(ofLayer: 1), .rendered)
        }
    }

    func testReversedOrderShowsOpaqueBlue() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("red", color: halfRed), SolidLayer("blue", color: blue)])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        assertAll(try rig.read(output), equal: blue, "opaque blue covers red")
    }

    func testNoLayersIsTransparent() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        assertAll(try rig.read(output), equal: .zero, "no layers")
    }

    func testDuplicateLayersAreRejectedAndTransformsAccepted() throws {
        let rig = try GPURig()
        let layer = SolidLayer("blue", color: blue)
        XCTAssertThrowsError(try Compositor(device: rig.device, layers: [layer, layer])) {
            XCTAssertEqual($0 as? CompositorError, .duplicateLayer(index: 1))
        }
        // CMP-005: transforms are accepted (only blend modes other than normal will be refused, CMP-004).
        let moved = SolidLayer("moved", color: blue)
        moved.settings = LayerCompositeSettings(transform: try LayerTransform(uniformScale: 2))
        XCTAssertNoThrow(try Compositor(device: rig.device, layers: [layer, moved]))
    }

    /// The acceptance's "without direct engine coupling": the test layers' source imports nothing but
    /// the contract, Metal and the analysis value types.
    func testLayersImportNoEngine() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("TestLayers.swift")
        let imports = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
            .filter { $0.hasPrefix("import ") }.map { String($0.dropFirst(7)) }
        XCTAssertEqual(Set(imports), ["AnalysisFeatures", "Compositor", "Metal", "XCTest"])
    }

    // MARK: - US2 (CMP-001-T08)

    func testLayersSeeExactlyTheGivenClockAndMusic() throws {
        let rig = try GPURig()
        let probe = ProbeLayer()
        let compositor = try Compositor(device: rig.device, layers: [probe])
        let output = try rig.output()
        let audio = LayerAudioBuffer()
        let bands = (0..<32).map { Float($0) / 31 }
        let events = [testEvent(1), testEvent(2)]
        let analysis = testFrame(id: 5, bands: 32)
        audio.set(frame: analysis, bands: bands, events: events)
        try rig.frame(compositor, into: output, time: 1_000_000_000, reduceFlashing: true, scale: 3, audio: audio.context)
        audio.set(frame: analysis, bands: bands, events: [])
        try rig.frame(compositor, into: output, time: 1_016_666_667, reduceFlashing: true, scale: 3, audio: audio.context)
        try rig.frame(compositor, into: output, time: 900_000_000, reduceFlashing: false, scale: 3, audio: .empty)

        XCTAssertEqual(probe.frames.map(\.frameIndex), [0, 1, 2])
        XCTAssertEqual(probe.frames.map(\.presentationTimeNanoseconds), [1_000_000_000, 1_016_666_667, 1_016_666_667])
        XCTAssertEqual(probe.frames[0].frameDuration, 0)
        XCTAssertEqual(probe.frames[1].frameDuration, 0.016666667, accuracy: 1e-12)
        XCTAssertEqual(probe.frames[2].frameDuration, 0, "a time earlier than the previous one does not run backwards")
        XCTAssertEqual(probe.frames.map(\.reduceFlashing), [true, true, false])
        for f in probe.frames {
            XCTAssertEqual(f.outputWidth, 64)
            XCTAssertEqual(f.outputHeight, 64)
            XCTAssertEqual(f.contentScale, 3)
        }
        XCTAssertEqual(probe.bands, [bands, bands, []])
        XCTAssertEqual(probe.events, [events, [], []])
        XCTAssertEqual(probe.analysisFrames, [analysis, analysis, nil])
    }
}
#endif
