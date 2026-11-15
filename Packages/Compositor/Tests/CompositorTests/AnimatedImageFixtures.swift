// MED-008-T06, T07: generated animated fixtures (no binary assets; research MED-008-D9).
//
// * `gif`: a small animated GIF written by ImageIO's `CGImageDestination` (solid frames, stated delays, a loop count).
// * `apng`: an animated PNG written chunk by chunk (signature, IHDR, acTL, fcTL/IDAT for the full first frame,
//   fcTL/fdAT patches for the others, IEND): zlib = `NSData.compressed(.zlib)` raw deflate with a zlib header and
//   Adler-32, CRC-32 from MediaSniffing. A 200-frame 2048 × 2048 animation is about 60 KB and generated in a fraction
//   of a second, while CGImageDestination would hold every frame until Finalize.
#if canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import MediaSniffing
import UniformTypeIdentifiers

enum AnimatedImageFixtures {
    /// An animated GIF of solid `width` × `height` frames with the given delays (seconds) and loop count.
    static func gif(colors: [ImageFixtures.RGBA], delays: [Double], width: Int = 32, height: Int = 32, loopCount: Int = 0) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString, colors.count, nil)!
        let container: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount]]
        CGImageDestinationSetProperties(destination, container as CFDictionary)
        for (index, color) in colors.enumerated() {
            let frame: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delays[index],
                                                                          kCGImagePropertyGIFUnclampedDelayTime: delays[index]]]
            CGImageDestinationAddImage(destination, ImageFixtures.solid(color, width: width, height: height), frame as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// An APNG `width` × `height` of `frames` frames, each `delayMilliseconds` long: frame 0 solid `base`, then frame i
    /// adds a `patch` × `patch` square of `ink` at a moving position (dispose none, blend source).
    static func apng(width: Int, height: Int, frames: Int, delayMilliseconds: Int = 100, patch: Int = 64,
                     base: [UInt8] = [40, 40, 40, 255], ink: [UInt8] = [200, 60, 60, 255]) -> Data {
        var out: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        out += chunk("IHDR", be32(width) + be32(height) + [8, 6, 0, 0, 0])
        out += chunk("acTL", be32(frames) + be32(0))
        var sequence = 0
        func control(_ w: Int, _ h: Int, _ x: Int, _ y: Int) -> [UInt8] {
            defer { sequence += 1 }
            return chunk("fcTL", be32(sequence) + be32(w) + be32(h) + be32(x) + be32(y)
                         + [UInt8(delayMilliseconds >> 8), UInt8(delayMilliseconds & 0xFF), 0x03, 0xE8, 0, 0])
        }
        out += control(width, height, 0, 0)
        out += chunk("IDAT", zlib(solidRows(width: width, height: height, color: base)))
        let square: [UInt8] = zlib(solidRows(width: patch, height: patch, color: ink))
        for i in 1..<max(frames, 1) {
            out += control(patch, patch, (i * 37) % max(width - patch, 1), (i * 53) % max(height - patch, 1))
            out += chunk("fdAT", be32(sequence) + square)
            sequence += 1
        }
        out += chunk("IEND", [])
        return Data(out)
    }

    private static func be32(_ v: Int) -> [UInt8] {
        let u = UInt32(truncatingIfNeeded: v)
        return [UInt8(u >> 24), UInt8(u >> 16 & 0xFF), UInt8(u >> 8 & 0xFF), UInt8(u & 0xFF)]
    }

    private static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let t: [UInt8] = Array(type.utf8)
        return be32(data.count) + t + data + be32(Int(CRC32.checksum(t + data)))
    }

    private static func solidRows(width: Int, height: Int, color: [UInt8]) -> Data {
        var row = [UInt8](repeating: 0, count: 1 + width * 4)
        for x in 0..<width { for c in 0..<4 { row[1 + x * 4 + c] = color[c] } }
        var data = Data()
        data.reserveCapacity(row.count * height)
        for _ in 0..<height { data.append(contentsOf: row) }
        return data
    }

    private static func zlib(_ raw: Data) -> [UInt8] {
        let deflated = try! (raw as NSData).compressed(using: .zlib) as Data
        var a: UInt32 = 1, b: UInt32 = 0
        raw.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            var i = 0
            while i < p.count {
                let end = min(i + 5552, p.count)
                while i < end { a += UInt32(p[i]); b += a; i += 1 }
                a %= 65521
                b %= 65521
            }
        }
        return [0x78, 0x9C] + [UInt8](deflated) + be32(Int((b << 16) | a))
    }
}
#endif
