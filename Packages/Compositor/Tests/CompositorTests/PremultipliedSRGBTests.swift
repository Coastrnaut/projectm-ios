// The photo layer's CPU premultiply (dark-fringe fix): straight-alpha sRGB bytes → the sRGB encoding of
// linear colour × alpha. Plain Swift: runs on the host, the simulator and in the Linux shape.
import ImageLayer
import XCTest

final class PremultipliedSRGBTests: XCTestCase {
    /// Opaque texels upload the same bytes as before the fix, so opaque photos render unchanged.
    func testOpaqueRowIsTheIdentityAndAnOpaqueImageIsUnchanged() {
        for c in 0..<256 {
            XCTAssertEqual(PremultipliedSRGB.table[255 << 8 | c], UInt8(c), "a = 255, c = \(c)")
            XCTAssertEqual(PremultipliedSRGB.encode(PremultipliedSRGB.decode(c)), UInt8(c), "sRGB round trip of \(c)")
        }
        let pixels: [UInt8] = [10, 128, 250, 255, 0, 0, 0, 255, 255, 255, 255, 255]
        let image = DecodedImage(width: 3, height: 1, pixels: pixels)
        XCTAssertFalse(image.hasAlpha)
        XCTAssertEqual(PremultipliedSRGB.pixels(image), pixels)
    }

    /// Transparent texels become (0, 0, 0, 0) whatever colour they stored; alpha bytes are kept.
    func testTransparentTexelsBecomeZero() {
        let image = DecodedImage(width: 2, height: 1, pixels: [200, 100, 50, 0, 220, 40, 200, 255])
        XCTAssertEqual(PremultipliedSRGB.pixels(image), [0, 0, 0, 0, 220, 40, 200, 255])
    }

    /// Partial alpha: the stored byte decodes to linear colour × alpha within half an sRGB step.
    func testPartialAlphaStoresTheEncodedPremultipliedLinearColour() {
        let image = DecodedImage(width: 2, height: 1, pixels: [220, 40, 200, 128, 255, 255, 255, 1])
        let out: [UInt8] = PremultipliedSRGB.pixels(image)
        XCTAssertEqual(out[3], 128)
        XCTAssertEqual(out[7], 1)
        for (i, (c, a)) in [(220, 128), (40, 128), (200, 128), (255, 1), (255, 1), (255, 1)].enumerated() {
            let index: Int = i < 3 ? i : i + 1
            let expected: Double = PremultipliedSRGB.decode(c) * Double(a) / 255
            let stored: Int = Int(out[index])
            let low: Double = PremultipliedSRGB.decode(Swift.max(stored - 1, 0))
            let high: Double = PremultipliedSRGB.decode(Swift.min(stored + 1, 255))
            XCTAssertTrue(expected >= low && expected <= high, "c \(c), a \(a): stored \(stored)")
        }
        // Never brighter than alpha allows, beyond half an sRGB step of rounding (the shader clamps that).
        for a in stride(from: 1, to: 255, by: 17) {
            for c in stride(from: 0, to: 256, by: 15) {
                let v: Double = PremultipliedSRGB.decode(Int(PremultipliedSRGB.table[a << 8 | c]))
                XCTAssertLessThanOrEqual(v, Double(a) / 255 + 0.005, "a \(a), c \(c)")
            }
        }
    }

    /// On-demand bench (PHOTO_FRINGE_BENCH=1): the CPU cost of a 4096 × 4096 photo with transparency.
    func testBenchFullSizePhoto() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PHOTO_FRINGE_BENCH"] == "1", "bench only")
        let side = 4096
        var pixels = [UInt8](repeating: 128, count: side * side * 4)
        var i = 3
        while i < pixels.count { pixels[i] = UInt8(i / 4 % 256); i += 4 }
        let image = DecodedImage(width: side, height: side, pixels: pixels)
        _ = PremultipliedSRGB.table
        let start = Date()
        let out: [UInt8] = PremultipliedSRGB.pixels(image)
        print("PremultipliedSRGB bench: \(side) x \(side) in \(Date().timeIntervalSince(start) * 1000) ms, \(out.count) bytes")
    }
}
