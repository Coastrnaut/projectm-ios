// TessellationRenderTests.swift — VIS-018-T07 (VIS-018-R1, R4, R8, R14; S2 to S4; contract C2 to C4): the tessellation
// on the real Metal pipeline. The test-only cell view (rgba32Float: exact integers) gives every pixel's lattice tile on
// the GPU; for every tiling × N 2, 5, 16 × 6 aspect ratios it equals the CPU lattice at every pixel more than 0.01 px
// from a seam (A6), and it does not change with loud bands, a huge time or any symmetry/palette setting. A render with
// extreme bands and time is finite and in 0…1; two renders are identical; tile colours deep inside tiles equal the CPU
// mirror's; settings change in place; entering the mode and a loop restart reset the drive. No byte-size assertion
// (the simulator misreports texture allocation sizes). Without a Metal device the tests skip.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class TessellationRenderTests: XCTestCase {
    /// Small outputs at the six supported aspect ratios.
    private static let sizes: [(Int, Int)] = [(90, 195), (195, 90), (120, 90), (160, 90), (210, 90), (120, 120)]

    private func context(_ nanoseconds: UInt64) -> VisualFrameContext {
        VisualFrameContext(timeNanoseconds: nanoseconds, frameDuration: 1.0 / 60, reduceFlashing: false)
    }

    private func make(_ rig: RenderRig, _ settings: TessellationSettings, format: MTLPixelFormat = .rgba16Float) throws -> NoiseFieldGenerator {
        try rig.build { try NoiseFieldGenerator(device: rig.device, pixelFormat: format, configuration: .tessellation(settings)) }
    }

    /// The cell view of `generator`'s current settings at `width × height`: (i, j, shape, edge px) per pixel.
    private func cells(_ rig: RenderRig, _ generator: NoiseFieldGenerator, state: MTLRenderPipelineState,
                       width: Int, height: Int) throws -> [SIMD4<Float>] {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let texture = try XCTUnwrap(rig.device.makeTexture(descriptor: d))
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(generator.encodeCells(into: texture, commandBuffer: commands, state: state))
        let rowBytes: Int = width * 16
        let buffer = try XCTUnwrap(rig.device.makeBuffer(length: rowBytes * height, options: .storageModeShared))
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        let floats = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: width * height)
        return Array(UnsafeBufferPointer(start: floats, count: width * height))
    }

    /// Draws `frames` 60 Hz frames of `bands` (optionally an extra frame at `lastTime`) and reads back the target.
    private func render(_ rig: RenderRig, _ generator: NoiseFieldGenerator, bands: [Float], frames: Int = 6, lastTime: UInt64? = nil,
                        width: Int = 96, height: Int = 72, format: MTLPixelFormat = .rgba16Float) throws -> PixelImage {
        let texture = try rig.makeTexture(width: width, height: height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        var times: [UInt64] = (0..<frames).map { (f: Int) -> UInt64 in UInt64(f) * 1_000_000_000 / 60 }
        if let lastTime { times.append(lastTime) }
        for t in times {
            let drawn: Bool = bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
                generator.encode(into: texture, commandBuffer: commands, bands: b, context: context(t))
            }
            XCTAssertTrue(drawn)
        }
        let buffer = try rig.encodeReadBack(texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        return rig.decode(RenderRig.bytes(of: buffer), width: width, height: height, format: format)
    }

    /// S2 / A6: the GPU's tile equals the CPU's at every pixel away from seams, every tiling × N × aspect ratio.
    func testGPUTilesMatchTheCPULatticeAtEveryAspectRatio() throws {
        let rig = try RenderRig()
        let generator = try make(rig, .default)
        let state = try generator.makeCellPipeline(format: .rgba32Float)
        var compared = 0, skipped = 0
        var worstEdge: Float = 0
        for tiling in TessellationTiling.allCases {
            for n in [2, 5, 16] {
                generator.configuration = .tessellation(TessellationSettings(tiling: tiling, tiles: n))
                for (w, h) in Self.sizes {
                    let gpu: [SIMD4<Float>] = try cells(rig, generator, state: state, width: w, height: h)
                    let placement = TessellationPlacement(width: w, height: h, tiles: n, tiling: tiling)
                    let s: Float = placement.tileSize
                    var mismatches = 0
                    for y in 0..<h {
                        for x in 0..<w {
                            let cpu: TessellationCell = placement.cell(pixel: SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5))
                            guard cpu.edge * s >= 0.01 else { skipped += 1; continue }
                            let g: SIMD4<Float> = gpu[y * w + x]
                            if Int(g.x) != cpu.i || Int(g.y) != cpu.j || Int(g.z) != cpu.shape {
                                mismatches += 1
                                if mismatches <= 3 { XCTFail("\(tiling) N=\(n) \(w)×\(h) pixel \(x),\(y): GPU \(g) CPU \(cpu)") }
                            }
                            worstEdge = max(worstEdge, abs(g.w - cpu.edge * s))
                            compared += 1
                        }
                    }
                    XCTAssertEqual(mismatches, 0, "\(tiling) N=\(n) \(w)×\(h)")
                }
            }
        }
        XCTAssertLessThan(worstEdge, 0.01, "GPU and CPU edge distances agree (px)")
        XCTAssertGreaterThan(compared, 1_000_000)
        print("VIS-018 GPU cell check: \(compared) pixels equal the CPU lattice (\(skipped) within 0.01 px of a seam skipped); worst edge difference \(worstEdge) px")
    }

    /// A6: the lattice never moves: the cell view is the same after loud frames, a huge time and every look setting.
    func testTheLatticeDependsOnlyOnSizeTilingAndCount() throws {
        let rig = try RenderRig()
        let base = TessellationSettings(tiling: .trihexagonal, tiles: 7)
        let generator = try make(rig, base)
        let state = try generator.makeCellPipeline(format: .rgba32Float)
        let before: [SIMD4<Float>] = try cells(rig, generator, state: state, width: 160, height: 90)
        _ = try render(rig, generator, bands: [Float](repeating: 1, count: 64), frames: 30, lastTime: 1_000_000_000 * 1_000_000_000)
        for symmetry in TessellationSettings.symmetries {
            for mirror in [false, true] {
                for palette in TessellationPalette.allCases {
                    generator.configuration = .tessellation(TessellationSettings(tiling: .trihexagonal, tiles: 7, symmetry: symmetry,
                                                                                 mirror: mirror, palette: palette), reduceMotion: true)
                    XCTAssertEqual(try cells(rig, generator, state: state, width: 160, height: 90), before,
                                   "symmetry \(symmetry) mirror \(mirror) \(palette)")
                }
            }
        }
    }

    /// S3: NaN, ±infinity and huge bands, a huge time and a time jump: every value finite and in 0…1.
    func testExtremeInputsRenderFinite() throws {
        let rig = try RenderRig()
        for tiling in TessellationTiling.allCases {
            let generator = try make(rig, TessellationSettings(tiling: tiling, tiles: 16, mirror: true))
            var bands = [Float](repeating: 1e6, count: 64)
            bands[0] = .nan; bands[1] = .infinity; bands[2] = -.infinity; bands[30] = -5
            let image = try render(rig, generator, bands: bands, lastTime: 1_000_000_000 * 1_000_000_000)
            for p in image.pixels {
                for k in 0..<4 { XCTAssertTrue(p[k].isFinite && p[k] >= 0 && p[k] <= 1, "\(tiling) \(p)") }
            }
            XCTAssertGreaterThan(image.pixels.map(luminance).max() ?? 0, 0.05, "\(tiling): tiles are lit")
            XCTAssertTrue(generator.tessellationUniforms.allSatisfy(\.isFinite))
        }
        let tiny = try make(rig, .default)
        let one = try render(rig, tiny, bands: [Float](repeating: 0.5, count: 64), width: 1, height: 1)
        XCTAssertTrue(one.pixels.allSatisfy { (p: Pixel) -> Bool in p.x.isFinite && p.x <= 1 })
    }

    /// S4: two renders from scratch are identical; tile colours deep inside tiles equal the CPU mirror's.
    func testRendersAreDeterministicAndAgreeWithTheCPUMirror() throws {
        let rig = try RenderRig()
        let settings = TessellationSettings(tiling: .hexagon, tiles: 4, symmetry: 6, mirror: false, palette: .ice)
        let bands = [Float](repeating: 0.4, count: 64)
        let first = try make(rig, settings)
        let a = try render(rig, first, bands: bands)
        XCTAssertEqual(a, try render(rig, try make(rig, settings), bands: bands))
        let frame: TessellationFrame = first.tessellationDrive.frame
        let placement = TessellationPlacement(width: 96, height: 72, tiles: 4, tiling: .hexagon)
        let stops: [LinearColor] = (0..<16).map { (k: Int) -> LinearColor in VisualPalette.ice.color(bar: k, of: 16).clamped }
        var compared = 0
        for y in Swift.stride(from: 3, to: 72, by: 7) {
            for x in Swift.stride(from: 3, to: 96, by: 7) {
                let cell: TessellationCell = placement.cell(pixel: SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5))
                let insetPx: Float = frame.inset * TessellationLattice.inradius(tiling: .hexagon, shape: 0) * placement.tileSize
                guard cell.edge * placement.tileSize > insetPx + 1 else { continue }
                let look = TessellationLattice.tileLook(offset: cell.centre - placement.origin, order: 6, mirror: false,
                                                        drift: frame.drift, light: frame.light)
                let base: LinearColor = stops.withUnsafeBufferPointer { (p: UnsafeBufferPointer<LinearColor>) -> LinearColor in
                    SignedDistanceScene.paletteColor(look.t, stops: p.baseAddress!)
                }
                let scale: Float = look.light * frame.brightness * first.lastGain
                let gpu: Pixel = a[x, y]
                XCTAssertEqual(gpu.x, base.red * scale, accuracy: 3e-3, "pixel \(x), \(y)")
                XCTAssertEqual(gpu.z, base.blue * scale, accuracy: 3e-3, "pixel \(x), \(y)")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 40)
        let seamPixels = a.pixels.filter { (p: Pixel) -> Bool in luminance(p) < 0.001 }.count
        XCTAssertGreaterThan(seamPixels, 50, "dark seams between the tiles")
    }

    /// Settings change in place (drive kept); entering the mode and a loop restart reset the drive (contract C2).
    func testSettingsChangeInPlaceAndReentryResetsTheDrive() throws {
        let rig = try RenderRig()
        let generator = try make(rig, .default)
        let bands = [Float](repeating: 0.8, count: 64)
        _ = try render(rig, generator, bands: bands, frames: 30)
        let drift: Double = generator.tessellationDrive.drift
        XCTAssertGreaterThan(drift, 0)
        generator.configuration = .tessellation(TessellationSettings(tiling: .square, tiles: 11))
        _ = try render(rig, generator, bands: bands, frames: 1, lastTime: UInt64(31) * 1_000_000_000 / 60, width: 8, height: 8)
        XCTAssertEqual(generator.tessellationUniforms[0], Float(TessellationTiling.square.index))
        XCTAssertEqual(generator.tessellationUniforms[1], 11, "the new count from the next frame")
        XCTAssertEqual(generator.tessellationUniforms[7], 0.5, "squares, N odd: a tile centre at the frame centre")
        XCTAssertGreaterThan(generator.tessellationDrive.drift, drift, "the drift keeps going")
        generator.restartLoop()
        XCTAssertEqual(generator.tessellationDrive, TessellationDrive())
        generator.configuration = NoiseFieldConfiguration()
        _ = try render(rig, generator, bands: bands, frames: 2)
        generator.configuration = .tessellation(.default)
        let again = try render(rig, generator, bands: bands)
        XCTAssertEqual(again, try render(rig, try make(rig, .default), bands: bands), "re-entering draws a fresh generator's frames")
    }
}
#endif
