// LinearSpectrumRenderTests.swift — VIS-002-T05: the real Metal pipeline renders a reference spectrum
// offscreen at 128 × 128, once per orientation; pixels are read back and lit pixels must fall inside
// the predicted bar and cap rectangles (VIS-002-S4). No golden-image byte comparison: GPUs differ.
// Without a Metal device the tests skip (RenderRig); they never fail for that reason.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class LinearSpectrumRenderTests: XCTestCase {
    private let size = 128
    private let format: MTLPixelFormat = .bgra8Unorm_srgb

    /// A ramp (k + 1)/16 with band 5 silent.
    private static var reference: [Float] {
        var v = (0..<16).map { Float($0 + 1) / 16 }
        v[5] = 0
        return v
    }

    private func render(_ rig: RenderRig, _ generator: LinearSpectrumGenerator, _ bands: [Float]) throws -> [UInt8] {
        let texture = try rig.makeTexture(width: size, height: size, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let drawn = bands.withUnsafeBufferPointer {
            generator.encode(into: texture, commandBuffer: commands, bands: $0,
                             context: VisualFrameContext(timeNanoseconds: 0, frameDuration: 1.0 / 60, reduceFlashing: false))
        }
        XCTAssertTrue(drawn)
        let buffer = try rig.encodeReadBack(texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        return RenderRig.bytes(of: buffer)
    }

    func testReferenceSpectrumLightsOnlyThePredictedRectanglesInBothOrientations() throws {
        let rig = try RenderRig()
        var report: [String] = []
        for orientation in LinearSpectrumOrientation.allCases {
            let configuration = LinearSpectrumConfiguration(barCount: .b16, orientation: orientation)
            let generator = try rig.build { try LinearSpectrumGenerator(device: rig.device, pixelFormat: format, configuration: configuration) }
            let bytes = try render(rig, generator, Self.reference)
            func lit(_ x: Int, _ y: Int) -> Bool {
                let i = (y * size + x) * 4
                return max(bytes[i], bytes[i + 1], bytes[i + 2]) > 32
            }
            var rects: [PixelRect] = []
            for k in 0..<16 {
                let r = generator.layout.rectangles(ofBar: k)
                if let bar = r.bar { rects.append(bar) }
                if let cap = r.cap { rects.append(cap) }
            }
            XCTAssertEqual(rects.count, 30, "15 lit bars, each with its cap")
            // Every lit pixel's centre lies in a predicted rectangle grown by 1 px; nothing outside.
            var litPixels = 0
            for y in 0..<size {
                for x in 0..<size where lit(x, y) {
                    litPixels += 1
                    let cx = Double(x) + 0.5, cy = Double(y) + 0.5
                    let inside = rects.contains { cx >= $0.minX - 1 && cx <= $0.maxX + 1 && cy >= $0.minY - 1 && cy <= $0.maxY + 1 }
                    XCTAssertTrue(inside, "\(orientation): lit pixel (\(x), \(y)) outside every bar and cap")
                }
            }
            // Each lit bar is lit at its centre with its palette color; the silent band is dark.
            for k in 0..<16 {
                let bar = generator.layout.rectangles(ofBar: k).bar
                let geometry = generator.layout.bar(k)
                let crossMid = (geometry.crossStart + geometry.crossEnd) / 2
                if k == 5 {
                    XCTAssertNil(bar)
                    let x = orientation == .vertical ? Int(crossMid) : 2
                    let y = orientation == .vertical ? size - 3 : Int(crossMid)
                    XCTAssertFalse(lit(x, y), "\(orientation): silent band 5 is dark")
                    continue
                }
                let r = try XCTUnwrap(bar)
                let x = Int((r.minX + r.maxX) / 2), y = Int((r.minY + r.maxY) / 2)
                XCTAssertTrue(lit(x, y), "\(orientation): bar \(k) lit at its centre")
                let i = (y * size + x) * 4
                let expected = configuration.palette.color(bar: k, of: 16)
                for (got, linear) in [(bytes[i + 2], expected.red), (bytes[i + 1], expected.green), (bytes[i], expected.blue)] {
                    XCTAssertEqual(Double(got), Double(SRGB.encode(linear) * 255), accuracy: 2, "\(orientation) bar \(k) color")
                }
            }
            // Bounded: nothing beyond λ·L + t·L along the length axis (the outer 10 % of the output).
            let limit = Int(((configuration.lengthScale + configuration.capThickness) * Double(size)).rounded(.up)) + 1
            for a in limit..<size {
                for c in 0..<size {
                    let (x, y) = orientation == .vertical ? (c, size - 1 - a) : (a, c)
                    XCTAssertFalse(lit(x, y), "\(orientation): lit beyond the maximum length at (\(x), \(y))")
                }
            }
            report.append("\(orientation): \(litPixels) lit pixels, all inside the 30 predicted rectangles")
        }
        print("VIS-002 render (\(rig.device.name), \(size) × \(size)): " + report.joined(separator: "; "))
    }

    func testSilenceIsBackgroundAndAWrongFormatIsRefused() throws {
        let rig = try RenderRig()
        let generator = try rig.build { try LinearSpectrumGenerator(device: rig.device, pixelFormat: format) }
        let bytes = try render(rig, generator, [Float](repeating: 0, count: 64))
        XCTAssertFalse(stride(from: 0, to: bytes.count, by: 4).contains { max(bytes[$0], bytes[$0 + 1], bytes[$0 + 2]) > 0 })
        let wrong = try rig.makeTexture(width: 8, height: 8, format: .rgba16Float)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let drawn = [Float](repeating: 1, count: 64).withUnsafeBufferPointer {
            generator.encode(into: wrong, commandBuffer: commands, bands: $0,
                             context: VisualFrameContext(timeNanoseconds: 0, frameDuration: 1.0 / 60, reduceFlashing: false))
        }
        XCTAssertFalse(drawn, "a target of another pixel format is refused")
        XCTAssertThrowsError(try LinearSpectrumGenerator(device: rig.device, pixelFormat: .r8Unorm))
    }
}
#endif
