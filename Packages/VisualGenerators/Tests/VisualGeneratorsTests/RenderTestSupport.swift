// RenderTestSupport.swift — FX-001-T09: offscreen textures, synthetic inputs and pixel read-back for
// the effect GPU tests. Textures are private and filled or read through blits to shared buffers
// (works on the Mac host and the simulator). Half floats are converted here, not with `Float16`, so
// the code builds on every Mac. Without a Metal device every GPU test throws `XCTSkip`.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

/// Linear premultiplied RGBA.
typealias Pixel = SIMD4<Float>

struct PixelImage: Equatable {
    var width: Int
    var height: Int
    var pixels: [Pixel]

    init(width: Int, height: Int, fill: Pixel = .zero) {
        self.width = width
        self.height = height
        pixels = Array(repeating: fill, count: width * height)
    }

    subscript(x: Int, y: Int) -> Pixel {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    /// A filled rectangle.
    static func patch(width: Int, height: Int, x0: Int, y0: Int, size: Int, color: Pixel) -> PixelImage {
        var image = PixelImage(width: width, height: height, fill: Pixel(0, 0, 0, 0))
        for y in y0..<(y0 + size) { for x in x0..<(x0 + size) { image[x, y] = color } }
        return image
    }
}

enum Half {
    static func toFloat(_ h: UInt16) -> Float {
        let sign: UInt32 = UInt32(h & 0x8000) << 16
        let exponent = Int((h >> 10) & 0x1F)
        let mantissa = UInt32(h & 0x3FF)
        if exponent == 0 {
            let value = Float(mantissa) * powf(2, -24)
            return sign == 0 ? value : -value
        }
        if exponent == 31 { return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13)) }
        return Float(bitPattern: sign | (UInt32(exponent - 15 + 127) << 23) | (mantissa << 13))
    }

    /// Round to nearest even; finite inputs in half range only (tests use 0…64).
    static func fromFloat(_ f: Float) -> UInt16 {
        let bits = f.bitPattern
        let sign = UInt16((bits >> 16) & 0x8000)
        let value = abs(f)
        if value == 0 { return sign }
        if value < powf(2, -14) {   // subnormal
            return sign | UInt16((value / powf(2, -24)).rounded(.toNearestOrEven))
        }
        var exponent = Int((bits >> 23) & 0xFF) - 127
        var mantissa = (bits & 0x7F_FFFF) | 0x80_0000
        let shift = 13
        let remainder = mantissa & ((1 << shift) - 1)
        mantissa >>= shift
        let half = UInt32(1 << (shift - 1))
        if remainder > half || (remainder == half && mantissa & 1 == 1) { mantissa += 1 }
        if mantissa == 0x800 { mantissa = 0x400; exponent += 1 }
        if exponent > 15 { return sign | 0x7C00 }
        return sign | UInt16(exponent + 15) << 10 | UInt16(mantissa & 0x3FF)
    }
}

final class RenderRig {
    let device: MTLDevice
    let queue: MTLCommandQueue

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this environment (CI simulator or Linux); the CPU tests cover the model.")
        }
        self.device = device
        self.queue = queue
    }

    /// Builds a pipeline-owning object; on a CI device without a usable GPU a failure is a skip,
    /// elsewhere it is rethrown (a real failure).
    func build<T>(_ make: () throws -> T) throws -> T {
        do {
            return try make()
        } catch {
            let env = ProcessInfo.processInfo.environment
            if env["CI"] != nil || env["GITHUB_ACTIONS"] != nil {
                throw XCTSkip("Metal pipeline unavailable on this CI device (\(device.name)): \(error)")
            }
            throw error
        }
    }

    static func bytesPerPixel(_ format: MTLPixelFormat) -> Int { format == .rgba16Float ? 8 : 4 }

    func makeTexture(width: Int, height: Int, format: MTLPixelFormat) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .renderTarget]
        d.storageMode = .private
        return try XCTUnwrap(device.makeTexture(descriptor: d))
    }

    /// Encodes the image in the texture's format (sRGB-encoded BGRA bytes or half floats).
    func bytes(of image: PixelImage, format: MTLPixelFormat) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(image.pixels.count * Self.bytesPerPixel(format))
        for p in image.pixels {
            if format == .rgba16Float {
                for k in 0..<4 {
                    let h = Half.fromFloat(p[k])
                    out.append(UInt8(h & 0xFF)); out.append(UInt8(h >> 8))
                }
            } else {
                func enc(_ v: Float) -> UInt8 { UInt8((SRGB.encode(v) * 255).rounded()) }
                out.append(enc(p.z)); out.append(enc(p.y)); out.append(enc(p.x))
                out.append(UInt8((min(max(p.w, 0), 1) * 255).rounded()))
            }
        }
        return out
    }

    func decode(_ bytes: [UInt8], width: Int, height: Int, format: MTLPixelFormat) -> PixelImage {
        var image = PixelImage(width: width, height: height)
        for i in 0..<(width * height) {
            if format == .rgba16Float {
                func h(_ k: Int) -> Float { Half.toFloat(UInt16(bytes[i * 8 + k * 2]) | UInt16(bytes[i * 8 + k * 2 + 1]) << 8) }
                image.pixels[i] = Pixel(h(0), h(1), h(2), h(3))
            } else {
                func dec(_ b: UInt8) -> Float { SRGB.decode(Float(b) / 255) }
                image.pixels[i] = Pixel(dec(bytes[i * 4 + 2]), dec(bytes[i * 4 + 1]), dec(bytes[i * 4]), Float(bytes[i * 4 + 3]) / 255)
            }
        }
        return image
    }

    func upload(_ image: PixelImage, format: MTLPixelFormat) throws -> MTLTexture {
        let texture = try makeTexture(width: image.width, height: image.height, format: format)
        let data = bytes(of: image, format: format)
        let rowBytes = image.width * Self.bytesPerPixel(format)
        let buffer = try XCTUnwrap(device.makeBuffer(bytes: data, length: data.count, options: .storageModeShared))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: buffer, sourceOffset: 0, sourceBytesPerRow: rowBytes, sourceBytesPerImage: data.count,
                  sourceSize: MTLSize(width: image.width, height: image.height, depth: 1),
                  to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return texture
    }

    /// Encodes a blit of `texture` into a new shared buffer on `commands`; read it after completion.
    func encodeReadBack(_ texture: MTLTexture, commands: MTLCommandBuffer) throws -> MTLBuffer {
        let rowBytes = texture.width * Self.bytesPerPixel(texture.pixelFormat)
        let buffer = try XCTUnwrap(device.makeBuffer(length: rowBytes * texture.height, options: .storageModeShared))
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * texture.height)
        blit.endEncoding()
        return buffer
    }

    static func bytes(of buffer: MTLBuffer) -> [UInt8] {
        Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: buffer.length))
    }

    func readBack(_ texture: MTLTexture) throws -> [UInt8] {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let buffer = try encodeReadBack(texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        return Self.bytes(of: buffer)
    }
}

/// Relative luminance of a linear pixel.
func luminance(_ p: Pixel) -> Double { 0.2126 * Double(p.x) + 0.7152 * Double(p.y) + 0.0722 * Double(p.z) }
#endif
