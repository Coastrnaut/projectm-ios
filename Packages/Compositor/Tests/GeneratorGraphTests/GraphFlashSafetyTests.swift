// SHD-002-T20 (US4; SHD-002-R11, R12, R13; S6): no graph strobes. Raw pictures (before the composite
// guard) are read back for 2 s at 60 Hz at 64 × 64, their 17 FX-019 areas measured and the series
// analysed with FlashSafety's independent `FlashAnalysis`. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import FlashSafety
import GeneratorGraph
import Metal
import XCTest

final class GraphFlashSafetyTests: XCTestCase {
    private let frames = 120
    private let frameTime = 1.0 / 60

    /// The worst transitions per window over the 17 areas and both signals; `bands(i)` per frame.
    private func worstTransitions(_ driver: GraphGPURig.Driver, configuration: FlashEnvelopeConfiguration,
                                  bands: (Int) -> [Float]) throws -> Int {
        var luminance = [[Double]](repeating: [], count: FlashZones.count)
        var redness = [[Double]](repeating: [], count: FlashZones.count)
        for i in 0..<frames {
            try driver.step(bands: bands(i))
            let areas = GraphGPURig.areas(try driver.read())
            for z in 0..<FlashZones.count {
                luminance[z].append(areas[z].luminance)
                redness[z].append(areas[z].redness)
            }
        }
        let times = [Double](repeating: frameTime, count: frames)
        var worst = 0
        for z in 0..<FlashZones.count {
            worst = max(worst, FlashAnalysis.analyze(luminance[z], frameTimes: times, threshold: configuration.luminanceThreshold).maxTransitionsPerWindow)
            worst = max(worst, FlashAnalysis.analyze(redness[z], frameTimes: times, threshold: configuration.rednessThreshold).maxTransitionsPerWindow)
        }
        return worst
    }

    /// S6: examples at defaults, with no music and with steady music, under the Reduce flashing thresholds.
    func testExamplesStayInsideReduceFlashingEnvelope() throws {
        let rig = try GraphGPURig()
        for document in GeneratorGraphExamples.all {
            for level in [Float](arrayLiteral: 0, 0.6) {
                let driver = try GraphGPURig.Driver(rig: rig, layer: rig.layer(document))
                let worst = try worstTransitions(driver, configuration: .reduceFlashing) { (_: Int) -> [Float] in
                    level > 0 ? [Float](repeating: level, count: 32) : []
                }
                XCTAssertLessThanOrEqual(worst, 2, "\(document.name) (music \(level)): transitions per 1 s window")
            }
        }
    }

    /// S6: through the compositor with Reduce flashing on, the guard never has to dim an example.
    func testCompositeGuardNeverActsOnExamples() throws {
        let rig = try GraphGPURig()
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 64, height: 64, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let output = try XCTUnwrap(rig.device.makeTexture(descriptor: d))
        let audio = LayerAudioBuffer()
        for document in GeneratorGraphExamples.all {
            let compositor = try Compositor(device: rig.device, layers: [rig.layer(document)])
            var lowest: Float = 1
            for i in 0..<frames {
                audio.set(frame: nil, bands: [Float](repeating: 0.6, count: 32), events: [])
                let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
                _ = compositor.composite(into: output, commandBuffer: commands,
                                         presentationTimeNanoseconds: UInt64(i) * GraphGPURig.frameNanoseconds,
                                         contentScale: 2, reduceFlashing: true, audio: audio.context)
                commands.commit()
                commands.waitUntilCompleted()
                lowest = min(lowest, compositor.lastFlashGain)
            }
            XCTAssertGreaterThanOrEqual(lowest, 0.999, "\(document.name): the guard's gain stays 1")
        }
    }

    /// R12: a time strobe that compiles is slowed to the bound; at its highest speed with full music it
    /// stays within the always-on budget before the guard.
    func testSlowedTimeStrobeStaysInsideAlwaysOnBudget() throws {
        let rig = try GraphGPURig()
        let strobe = graphDoc([GraphNode("t", .time), GraphNode("o", .oscillate, inputs: ["phase": "t"], values: ["rate": 1]),
                               GraphNode("w", .wave, inputs: ["x": "o"], values: ["frequency": 2]),
                               GraphNode("c", .gradient, inputs: ["t": "w"]), GraphNode("out", .output, inputs: ["color": "c"])],
                              speed: 1)
        let layer = try rig.layer(strobe)
        XCTAssertLessThan(layer.speed, 0.2, "limited")
        layer.setSpeed(1)
        let driver = try GraphGPURig.Driver(rig: rig, layer: layer)
        let worst = try worstTransitions(driver, configuration: .alwaysOn) { (_: Int) -> [Float] in [1, 1, 1, 1] }
        XCTAssertLessThanOrEqual(worst, FlashEnvelopeConfiguration.alwaysOn.transitionBudget)
    }

    /// R11, R12: music alternating between silence and full level every frame cannot strobe a graph
    /// that maps the music level straight to black and white through a fast wave.
    func testAlternatingMusicCannotStrobe() throws {
        let rig = try GraphGPURig()
        let doc = graphDoc([GraphNode("l", .musicLevel), GraphNode("w", .wave, inputs: ["x": "l"], values: ["frequency": 16]),
                            GraphNode("c", .gradient, inputs: ["t": "w"]), GraphNode("out", .output, inputs: ["color": "c"])])
        let layer = try rig.layer(doc)
        XCTAssertLessThan(layer.compiled.musicRate, 0.1, "the follower is slowed")
        let driver = try GraphGPURig.Driver(rig: rig, layer: layer)
        let worst = try worstTransitions(driver, configuration: .alwaysOn) { (i: Int) -> [Float] in
            [Float](repeating: i % 2 == 0 ? 1 : 0, count: 8)
        }
        XCTAssertLessThanOrEqual(worst, FlashEnvelopeConfiguration.alwaysOn.transitionBudget)
        XCTAssertLessThanOrEqual(layer.motion.musicLevel, layer.compiled.musicRate * Double(frames) / 60 + 1e-9)
    }
}
#endif
