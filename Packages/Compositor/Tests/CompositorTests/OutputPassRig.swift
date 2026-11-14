// FX-002-T01, T06: runs the compositor's real output pass (`cmp_output`, compiled from `CompositorShaders.source`)
// on a hand-filled `rgba16Float` composite, so values the layer passes never produce (NaN, ±Inf, negatives)
// reach it. Reads the target back raw: half floats, or 8-bit bytes (sRGB-encoded for `bgra8Unorm_srgb`).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import Metal
import XCTest

final class OutputPassRig {
    let rig: GPURig
    private let library: MTLLibrary
    private let fullScreen: MTLFunction
    /// Non-finite pixels counted by the last `output` call (FX-002-R7).
    private(set) var lastNonFiniteCount: UInt32 = 0

    init() throws {
        rig = try GPURig()
        library = try CompositorShaders.library(device: rig.device, source: CompositorShaders.source)
        fullScreen = try CompositorShaders.function(library, "cmp_fullscreen")
    }

    /// A one-row `rgba16Float` composite holding `pixels` (linear premultiplied, any values).
    func composite(_ pixels: [SIMD4<Float>]) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: pixels.count, height: 1, mipmapped: false)
        d.usage = [.shaderRead, .renderTarget]
        d.storageMode = .shared
        let texture = try XCTUnwrap(rig.device.makeTexture(descriptor: d))
        var halves: [UInt16] = []
        halves.reserveCapacity(pixels.count * 4)
        for p in pixels {
            for c in 0..<4 { halves.append(Float16(p[c]).bitPattern) }
        }
        halves.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if let base = raw.baseAddress {
                texture.replace(region: MTLRegionMake2D(0, 0, pixels.count, 1), mipmapLevel: 0, withBytes: base,
                                bytesPerRow: pixels.count * 8)
            }
        }
        return texture
    }

    /// `cmp_output` from `composite` × `gain` into a new target of `format`; returns the raw channel values:
    /// floats for `rgba16Float`, bytes / 255 (still encoded) for 8-bit formats, RGBA order.
    /// FX-003: `grade` is bound at fragment buffer 2 (neutral: bypass; a custom library's shader may ignore it).
    func output(_ composite: MTLTexture, format: MTLPixelFormat, gain: Float = 1, shader: String = "cmp_output",
                library custom: MTLLibrary? = nil, grade: ColorGrade = .neutral) throws -> [SIMD4<Float>] {
        let fragment = try CompositorShaders.function(custom ?? library, shader)
        let pipeline = try CompositorShaders.pipeline(device: rig.device, vertex: fullScreen, fragment: fragment, format: format,
                                                      blendOver: false, label: "FX-002 test output")
        var g = gain
        let gainBuffer = try XCTUnwrap(rig.device.makeBuffer(bytes: &g, length: MemoryLayout<Float>.size, options: .storageModeShared))
        let target = try self.target(format, width: composite.width, height: composite.height)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        let encoder = try XCTUnwrap(commands.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(composite, index: 0)
        encoder.setFragmentBuffer(gainBuffer, offset: 0, index: 0)
        var zero: UInt32 = 0
        let counter = try XCTUnwrap(rig.device.makeBuffer(bytes: &zero, length: 4, options: .storageModeShared))
        encoder.setFragmentBuffer(counter, offset: 0, index: 1)
        Compositor.bindGrade(CompositorShaders.GradeBlock(grade.coefficients), encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
        lastNonFiniteCount = counter.contents().load(as: UInt32.self)
        return readRaw(target)
    }

    /// A shared render target (readable with `readRaw`).
    func target(_ format: MTLPixelFormat, width: Int, height: Int) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        return try XCTUnwrap(rig.device.makeTexture(descriptor: d))
    }

    /// Every pixel, rows top first: floats for `rgba16Float`, bytes / 255 (still encoded) for 8-bit formats, RGBA.
    func readRaw(_ target: MTLTexture) -> [SIMD4<Float>] {
        let n = target.width * target.height
        let region = MTLRegionMake2D(0, 0, target.width, target.height)
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(n)
        if target.pixelFormat == .rgba16Float {
            var halves = [UInt16](repeating: 0, count: n * 4)
            halves.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                if let base = raw.baseAddress { target.getBytes(base, bytesPerRow: target.width * 8, from: region, mipmapLevel: 0) }
            }
            for i in 0..<n {
                out.append(SIMD4<Float>(Half.toFloat(halves[i * 4]), Half.toFloat(halves[i * 4 + 1]),
                                        Half.toFloat(halves[i * 4 + 2]), Half.toFloat(halves[i * 4 + 3])))
            }
            return out
        }
        var bytes = [UInt8](repeating: 0, count: n * 4)
        bytes.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            if let base = raw.baseAddress { target.getBytes(base, bytesPerRow: target.width * 4, from: region, mipmapLevel: 0) }
        }
        let bgra: Bool = target.pixelFormat == .bgra8Unorm || target.pixelFormat == .bgra8Unorm_srgb
        for i in 0..<n {
            let b0: Float = Float(bytes[i * 4]) / 255
            let b1: Float = Float(bytes[i * 4 + 1]) / 255
            let b2: Float = Float(bytes[i * 4 + 2]) / 255
            let a: Float = Float(bytes[i * 4 + 3]) / 255
            out.append(bgra ? SIMD4<Float>(b2, b1, b0, a) : SIMD4<Float>(b0, b1, b2, a))
        }
        return out
    }
}
#endif
