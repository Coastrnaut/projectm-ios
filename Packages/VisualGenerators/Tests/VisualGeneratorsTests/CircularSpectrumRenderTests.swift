// CircularSpectrumRenderTests.swift — VIS-001-T12, T18: the real Metal pipeline renders offscreen,
// pixels are read back, and lit pixels must fall inside the predicted angular sector (VIS-001-S3),
// in portrait and landscape. No golden-image byte comparison: GPUs differ. Where no Metal device
// exists (Linux, some CI simulators) the tests skip with a message; they never fail for that reason.
#if canImport(Metal) && !VISUAL_NO_METAL
import Foundation
import Metal
import XCTest
@testable import VisualGenerators

final class CircularSpectrumRenderTests: XCTestCase {
    private static let sizes: [(width: Int, height: Int)] = [(600, 1200), (1200, 600)]

    private struct Rig {
        let device: MTLDevice
        let queue: MTLCommandQueue
    }

    private func rig() throws -> Rig {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this environment (CI simulator or Linux); the CPU geometry tests cover the acceptance.")
        }
        return Rig(device: device, queue: queue)
    }

    private func generator(_ rig: Rig, _ configuration: CircularSpectrumConfiguration) throws -> CircularSpectrumGenerator {
        do {
            return try CircularSpectrumGenerator(device: rig.device, configuration: configuration)
        } catch {
            let env = ProcessInfo.processInfo.environment
            if env["CI"] != nil || env["GITHUB_ACTIONS"] != nil {
                throw XCTSkip("Metal pipeline unavailable on this CI device (\(rig.device.name)): \(error)")
            }
            throw error
        }
    }

    /// Renders one frame and returns BGRA bytes (sRGB-encoded).
    private func render(_ rig: Rig, _ generator: CircularSpectrumGenerator, bands: [Float], width: Int, height: Int) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = try XCTUnwrap(rig.device.makeTexture(descriptor: descriptor))
        let bytesPerRow = width * 4
        let buffer = try XCTUnwrap(rig.device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared))
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let drawn = bands.withUnsafeBufferPointer {
            generator.encode(into: texture, commandBuffer: commands, bands: $0,
                             context: VisualFrameContext(timeNanoseconds: 0, frameDuration: 1.0 / 60, reduceFlashing: false))
        }
        XCTAssertTrue(drawn)
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: bytesPerRow * height))
    }

    private func pixel(_ bytes: [UInt8], width: Int, height: Int, x: Double, y: Double) -> (b: UInt8, g: UInt8, r: UInt8)? {
        let ix = Int(x.rounded(.down)), iy = Int(y.rounded(.down))
        guard ix >= 0, iy >= 0, ix < width, iy < height else { return nil }
        let i = (iy * width + ix) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2])
    }

    private func isLit(_ p: (b: UInt8, g: UInt8, r: UInt8)?) -> Bool {
        guard let p else { return false }
        return max(p.b, p.g, p.r) > 32
    }

    private func point(angle: Double, radius: Double, width: Int, height: Int) -> (x: Double, y: Double) {
        let t = angle * .pi / 180
        return (Double(width) / 2 + radius * sin(t), Double(height) / 2 - radius * cos(t))
    }

    func testImpulseLightsOnlyItsSectorInPortraitAndLandscape() throws {
        let rig = try rig()
        var renders = 0, litSamples = 0
        var worstExcess = 0.0
        for size in Self.sizes {
            let unit = Double(min(size.width, size.height)) / 2
            for n in GeometryOracle.barCounts {
                let config = CircularSpectrumConfiguration(barCount: SpectrumBarCount(rawValue: n)!)
                let gen = try generator(rig, config)
                let inner = config.innerRadius * unit
                let outer = (config.innerRadius + config.lengthScale) * unit
                for k in Set([0, n / 4, n / 2, n - 1]).sorted() {
                    let bytes = try render(rig, gen, bands: GeometryOracle.impulse(at: k, count: n), width: size.width, height: size.height)
                    renders += 1
                    let theta = GeometryOracle.angle(bar: k, count: n)
                    let half = config.halfWidthDegrees
                    // Every lit sample on rays every 0.25° lies within the bar's sector + 1.5 px.
                    var r = inner + 2
                    while r <= outer - 2 {
                        let tolerance = min(2, 1.5 / r * 180 / .pi)
                        for step in 0..<1440 {
                            let angle = Double(step) * 0.25
                            let p = point(angle: angle, radius: r, width: size.width, height: size.height)
                            guard isLit(pixel(bytes, width: size.width, height: size.height, x: p.x, y: p.y)) else { continue }
                            litSamples += 1
                            let excess = GeometryOracle.distance(angle, theta) - half
                            worstExcess = max(worstExcess, excess)
                            XCTAssertLessThanOrEqual(excess, tolerance, "N=\(n) k=\(k) \(size) lit at \(angle)° r=\(r)")
                        }
                        r += 3
                    }
                    // The centre ray is lit at three radii; the neighbours' centre rays are dark.
                    for fraction in [0.2, 0.5, 0.8] {
                        let radius = inner + fraction * (outer - inner)
                        let c = point(angle: theta, radius: radius, width: size.width, height: size.height)
                        XCTAssertTrue(isLit(pixel(bytes, width: size.width, height: size.height, x: c.x, y: c.y)), "N=\(n) k=\(k) centre r=\(radius)")
                        for neighbour in [(k + 1) % n, (k + n - 1) % n] {
                            let a = GeometryOracle.angle(bar: neighbour, count: n)
                            let q = point(angle: a, radius: radius, width: size.width, height: size.height)
                            XCTAssertFalse(isLit(pixel(bytes, width: size.width, height: size.height, x: q.x, y: q.y)), "N=\(n) neighbour \(neighbour) of \(k)")
                        }
                    }
                    // The bar's color is the palette's, sRGB-encoded by the target format.
                    let mid = point(angle: theta, radius: (inner + outer) / 2, width: size.width, height: size.height)
                    let px = try XCTUnwrap(pixel(bytes, width: size.width, height: size.height, x: mid.x, y: mid.y))
                    let expected = config.palette.color(bar: k, of: n)
                    for (got, linear) in [(px.r, expected.red), (px.g, expected.green), (px.b, expected.blue)] {
                        XCTAssertEqual(Double(got), Double(SRGB.encode(linear) * 255), accuracy: 2, "N=\(n) k=\(k) color")
                    }
                }
            }
        }
        print("VIS-001 render: \(renders) renders on \(rig.device.name), \(litSamples) lit samples, worst excess beyond the half-width \(worstExcess)°")
    }

    func testSilenceIsEntirelyBackground() throws {
        let rig = try rig()
        let gen = try generator(rig, CircularSpectrumConfiguration(barCount: .b64))
        for size in Self.sizes {
            let bytes = try render(rig, gen, bands: [Float](repeating: 0, count: 64), width: size.width, height: size.height)
            XCTAssertFalse(stride(from: 0, to: bytes.count, by: 4).contains { max(bytes[$0], bytes[$0 + 1], bytes[$0 + 2]) > 0 },
                           "\(size): every pixel black")
            XCTAssertTrue(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 }, "opaque")
        }
    }

    func testRepeatedFramesReuseBuffersAndRejectAWrongFormat() throws {
        let rig = try rig()
        let gen = try generator(rig, CircularSpectrumConfiguration(barCount: .b16))
        XCTAssertEqual(gen.pixelFormat, .bgra8Unorm_srgb)
        for i in 0..<8 {
            let bytes = try render(rig, gen, bands: GeometryOracle.impulse(at: i, count: 16), width: 200, height: 200)
            XCTAssertTrue(bytes.contains { $0 > 32 })
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 8, height: 8, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        let wrong = try XCTUnwrap(rig.device.makeTexture(descriptor: descriptor))
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let drawn = [Float](repeating: 1, count: 16).withUnsafeBufferPointer {
            gen.encode(into: wrong, commandBuffer: commands, bands: $0,
                       context: VisualFrameContext(timeNanoseconds: 0, frameDuration: 1.0 / 60, reduceFlashing: false))
        }
        XCTAssertFalse(drawn, "a target of another pixel format is refused, not drawn")
        XCTAssertThrowsError(try CircularSpectrumGenerator(device: rig.device, pixelFormat: .r8Unorm))
    }
}
#endif
