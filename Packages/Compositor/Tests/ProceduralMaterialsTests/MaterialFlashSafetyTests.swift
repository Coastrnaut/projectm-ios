// SHD-001-T15 (US3; SHD-001-R10, R11, R12; S5, S6): no material flashes on its own. Each material's
// raw picture (before the composite guard) is read back for 2 s at 60 Hz at 64 × 64, its 17 FX-019
// areas measured and the series analysed with FlashSafety's independent `FlashAnalysis`. Skipped
// without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import FlashSafety
import Metal
import ParameterGraph
import ProceduralMaterials
import XCTest

final class MaterialFlashSafetyTests: XCTestCase {
    private let frames = 120
    private let frameTime = 1.0 / 60

    /// The worst transitions per window over the 17 areas and both signals.
    private func worstTransitions(_ driver: MaterialGPURig.Driver, bands: [Float],
                                  configuration: FlashEnvelopeConfiguration) throws -> Int {
        var luminance = [[Double]](repeating: [], count: FlashZones.count)
        var redness = [[Double]](repeating: [], count: FlashZones.count)
        for _ in 0..<frames {
            try driver.step(bands: bands)
            let areas = MaterialGPURig.areas(try driver.read())
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

    /// S5: defaults, with no music and with steady music, under the Reduce flashing thresholds.
    func testDefaultsStayInsideReduceFlashingEnvelope() throws {
        let rig = try MaterialGPURig()
        for kind in MaterialKind.allCases {
            for bands in [[Float](), [Float](repeating: 0.6, count: 32)] {
                let driver = try MaterialGPURig.Driver(rig: rig, layer: ProceduralMaterialCatalog.makeLayer(kind))
                let worst = try worstTransitions(driver, bands: bands, configuration: .reduceFlashing)
                XCTAssertLessThanOrEqual(worst, 2, "\(kind.id) (music \(!bands.isEmpty)): transitions per 1 s window")
            }
        }
    }

    /// S5: through the compositor with Reduce flashing on, the guard never has to dim a default material.
    func testCompositeGuardNeverActsAtDefaults() throws {
        let rig = try MaterialGPURig()
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 64, height: 64, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let output = try XCTUnwrap(rig.device.makeTexture(descriptor: d))
        let audio = LayerAudioBuffer()
        for kind in MaterialKind.allCases {
            let compositor = try Compositor(device: rig.device, layers: [ProceduralMaterialCatalog.makeLayer(kind)])
            var lowest: Float = 1
            for i in 0..<frames {
                audio.set(frame: nil, bands: [Float](repeating: 0.6, count: 32), events: [])
                let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
                _ = compositor.composite(into: output, commandBuffer: commands,
                                         presentationTimeNanoseconds: UInt64(i) * MaterialGPURig.frameNanoseconds,
                                         contentScale: 2, reduceFlashing: true, audio: audio.context)
                commands.commit()
                commands.waitUntilCompleted()
                lowest = min(lowest, compositor.lastFlashGain)
            }
            XCTAssertGreaterThanOrEqual(lowest, 0.999, "\(kind.id): the guard's gain stays 1")
        }
    }

    /// S6: every speed at its largest magnitude (and the strongest look) with music at full level,
    /// before the composite guard: within the always-on budget.
    func testExtremesWithFullMusicStayInsideAlwaysOnBudget() throws {
        let rig = try MaterialGPURig()
        for kind in MaterialKind.allCases {
            let layer = ProceduralMaterialCatalog.makeLayer(kind)
            for d in layer.definition.parameters {
                let name = d.id.segments.last ?? ""
                if case let .continuous(_, maximum, _, _, _) = d.kind,
                   ["speed", "brightness", "contrast", "audioReactivity", "saturation"].contains(name) {
                    try layer.set(.continuous(maximum), for: d.id)
                }
            }
            let driver = try MaterialGPURig.Driver(rig: rig, layer: layer)
            let worst = try worstTransitions(driver, bands: [Float](repeating: 1, count: 32), configuration: .alwaysOn)
            XCTAssertLessThanOrEqual(worst, FlashEnvelopeConfiguration.alwaysOn.transitionBudget, "\(kind.id) at extremes")
        }
    }

    /// R10: music changes motion only; with speed 0 a frame with music equals one without.
    func testMusicChangesOnlyMotion() throws {
        let rig = try MaterialGPURig()
        for kind in MaterialKind.allCases {
            let quiet = ProceduralMaterialCatalog.makeLayer(kind)
            let loud = ProceduralMaterialCatalog.makeLayer(kind)
            for layer in [quiet, loud] {
                try layer.set(.continuous(0), for: layer.definition.speedParameter)
                try layer.set(.continuous(1), for: layer.definition.reactivityParameter)
            }
            let a = try MaterialGPURig.Driver(rig: rig, layer: quiet)
            let b = try MaterialGPURig.Driver(rig: rig, layer: loud)
            for _ in 0..<10 {
                try a.step()
                try b.step(bands: [1, 1, 1, 1])
            }
            XCTAssertGreaterThan(loud.motion.audioLevel, 0.5)
            XCTAssertEqual(try a.read(), try b.read(), "\(kind.id): music never changes brightness")
        }
    }
}
#endif
