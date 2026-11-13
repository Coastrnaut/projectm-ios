// SHD-002-T21 (research SHD-002-D2): host GPU cost of the interpreter for a 12-node graph against
// SHD-001's Noise Flow material at the iPhone 15's 1179 × 2556. Runs only with SHD002_BENCH=1 (an
// on-demand measurement, not a test: nothing is asserted about time). The 12-node graph is also the
// one the device stage measures (SHD-002-T24).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import GeneratorGraph
import Metal
import ProceduralMaterials
import XCTest

enum GraphBenchGraphs {
    static let twelveNodes = GeneratorGraphDocument(name: "Bench 12", speed: 0.1, nodes: [
        GraphNode("t", .time),
        GraphNode("d", .drift, inputs: ["phase": "t"], values: ["velocityX": 0.2, "velocityY": 0.1]),
        GraphNode("n", .noise, inputs: ["point": "d"], values: ["scale": 3, "octaves": 4]),
        GraphNode("s", .spin, inputs: ["phase": "t"], values: ["rate": 0.1]),
        GraphNode("r", .ring, inputs: ["point": "s"], values: ["radius": 0.3, "width": 0.05, "softness": 0.05]),
        GraphNode("b", .box, inputs: ["point": "s"], values: ["width": 0.6, "height": 0.3, "softness": 0.05]),
        GraphNode("m", .multiply, inputs: ["a": "r", "b": "n"]),
        GraphNode("a", .add, inputs: ["a": "m", "b": "b"]),
        GraphNode("h", .hsv, inputs: ["hue": "n", "value": "a"]),
        GraphNode("o", .oscillate, inputs: ["phase": "t"], values: ["rate": 0.2]),
        GraphNode("x", .mixColor, inputs: ["a": "h", "t": "o"], values: ["b": [0.1, 0.2, 0.5]]),
        GraphNode("out", .output, inputs: ["color": "x"]),
    ])
}

final class GraphCostBench: XCTestCase {
    func testTwelveNodeGraphCompiles() throws {
        let plan = try GeneratorGraphCompiler.compile(GraphBenchGraphs.twelveNodes)
        XCTAssertEqual(plan.order.count, 12)
    }

    func testGraphCostAgainstNoiseFlow() throws {
        guard ProcessInfo.processInfo.environment["SHD002_BENCH"] == "1" else {
            throw XCTSkip("on-demand bench: set SHD002_BENCH=1")
        }
        let rig = try GraphGPURig()
        let graph = try rig.layer(GraphBenchGraphs.twelveNodes)
        let material = ProceduralMaterialCatalog.makeLayer(.noiseFlow)
        let picture = try rig.picture(width: 1179, height: 2556)
        let descriptor = try XCTUnwrap(LayerPictureDescriptor(width: 1179, height: 2556))
        try material.prepare(picture: descriptor, device: rig.device)
        try graph.prepare(picture: descriptor, device: rig.device)
        var clock = LayerFrameClock()
        let audio = LayerAudioBuffer()
        func time(_ draw: (MTLCommandBuffer, LayerFrameContext) throws -> Void) throws -> [Double] {
            var samples: [Double] = []
            for i in 0..<70 {
                let frame = clock.next(presentationTimeNanoseconds: UInt64(i) * GraphGPURig.frameNanoseconds, outputWidth: 1179,
                                       outputHeight: 2556, contentScale: 3, reduceFlashing: false)
                let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
                try draw(commands, frame)
                commands.commit()
                commands.waitUntilCompleted()
                if i >= 10 { samples.append((commands.gpuEndTime - commands.gpuStartTime) * 1000) }
            }
            return samples.sorted()
        }
        audio.set(frame: nil, bands: [], events: [])
        let graphTimes = try time { (commands: MTLCommandBuffer, frame: LayerFrameContext) in
            try graph.render(into: picture, commandBuffer: commands, frame: frame, audio: audio.context)
        }
        let materialTimes = try time { (commands: MTLCommandBuffer, frame: LayerFrameContext) in
            try material.render(into: picture, commandBuffer: commands, frame: frame, audio: audio.context)
        }
        print("SHD002_BENCH device \(rig.device.name): 12-node graph median \(graphTimes[30]) ms, max \(graphTimes.last ?? 0) ms; "
              + "Noise Flow median \(materialTimes[30]) ms, max \(materialTimes.last ?? 0) ms (GPU time per frame, 1179 x 2556, 60 frames)")
    }
}
#endif
