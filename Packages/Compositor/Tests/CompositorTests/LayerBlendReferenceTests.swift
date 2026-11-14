// CMP-004-T04: the plain-Swift reference of the blend modes (CMP-004-S3, R2-R5, R10). CPU only;
// runs on Linux and on the Mac in the Linux shape (-DCOMPOSITOR_NO_METAL).
import Compositor
import XCTest

final class LayerBlendReferenceTests: XCTestCase {
    private let levels: [Double] = [0, 0.25, 0.5, 0.75, 1]

    func testModeNamesAreStable() {
        XCTAssertEqual(LayerBlendMode.allCases.map(\.rawValue), ["normal", "add", "screen", "multiply", "overlay", "difference"])
        XCTAssertEqual(LayerBlendMode(rawValue: "screen"), .screen)
        XCTAssertNil(LayerBlendMode(rawValue: "Screen"), "names are exact and lower case")
        XCTAssertNil(LayerBlendMode(rawValue: "softLight"))
    }

    func testHandCheckedValues() {
        let f: (LayerBlendMode, Double, Double) -> Double = LayerBlend.function(_:backdrop:source:)
        XCTAssertEqual(f(.multiply, 0.5, 0.5), 0.25, accuracy: 1e-12)
        XCTAssertEqual(f(.screen, 0.5, 0.5), 0.75, accuracy: 1e-12)
        XCTAssertEqual(f(.add, 0.5, 0.5), 1, accuracy: 1e-12)
        XCTAssertEqual(f(.add, 0.75, 0.75), 1, accuracy: 1e-12, "add saturates at 1")
        XCTAssertEqual(f(.add, 0.25, 0.5), 0.75, accuracy: 1e-12)
        XCTAssertEqual(f(.difference, 0.5, 0.5), 0, accuracy: 1e-12)
        XCTAssertEqual(f(.difference, 1, 0.25), 0.75, accuracy: 1e-12)
        XCTAssertEqual(f(.normal, 0.25, 0.75), 0.75, accuracy: 1e-12)
        // Overlay: at the threshold Cb = 0.5 both branches give Cs.
        for cs in levels {
            XCTAssertEqual(f(.overlay, 0.5, cs), cs, accuracy: 1e-12, "overlay(0.5, \(cs))")
        }
        XCTAssertEqual(f(.overlay, 0.25, 0.5), 0.25, accuracy: 1e-12, "dark backdrop: 2·Cb·Cs")
        XCTAssertEqual(f(.overlay, 0.75, 0.5), 0.75, accuracy: 1e-12, "light backdrop: screen(Cs, 2·Cb − 1)")
        XCTAssertEqual(f(.overlay, 1, 0), 1, accuracy: 1e-12)
        XCTAssertEqual(f(.overlay, 0, 1), 0, accuracy: 1e-12)
    }

    func testFunctionsOnTheGrid() {
        for cb in levels {
            for cs in levels {
                let mul: Double = cb * cs
                XCTAssertEqual(LayerBlend.function(.multiply, backdrop: cb, source: cs), mul, accuracy: 1e-12)
                let inverse: Double = (1 - cb) * (1 - cs)
                XCTAssertEqual(LayerBlend.function(.screen, backdrop: cb, source: cs), 1 - inverse, accuracy: 1e-12)
                XCTAssertEqual(LayerBlend.function(.difference, backdrop: cb, source: cs),
                               LayerBlend.function(.difference, backdrop: cs, source: cb), accuracy: 1e-12, "difference is symmetric")
                XCTAssertEqual(LayerBlend.function(.screen, backdrop: cb, source: cs),
                               LayerBlend.function(.screen, backdrop: cs, source: cb), accuracy: 1e-12, "screen is symmetric")
                for mode in LayerBlendMode.allCases {
                    let v = LayerBlend.function(mode, backdrop: cb, source: cs)
                    XCTAssertTrue(v >= 0 && v <= 1, "\(mode)(\(cb), \(cs)) = \(v) stays in 0…1")
                }
            }
        }
    }

    func testTransferFunctionsRoundTrip() {
        XCTAssertEqual(LayerBlend.encode(0), 0)
        XCTAssertEqual(LayerBlend.encode(1), 1, accuracy: 1e-12)
        XCTAssertEqual(LayerBlend.decode(0.5), 0.214041, accuracy: 1e-6, "sRGB 50 % grey")
        for x in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(LayerBlend.decode(LayerBlend.encode(x)), x, accuracy: 1e-12)
        }
    }

    func testOpaqueResultsEqualTheEncodedFunction() {
        // Opaque layers: the shown (encoded) pixel is exactly B of the encoded colours.
        for mode in LayerBlendMode.allCases {
            for cb in levels {
                for cs in levels {
                    let b = LayerBlend.premultipliedLinear(encoded: cb, cb, cb, alpha: 1)
                    let s = LayerBlend.premultipliedLinear(encoded: cs, cs, cs, alpha: 1)
                    let out = LayerBlend.composite(mode, backdrop: b, source: s)
                    XCTAssertEqual(out[3], 1, accuracy: 1e-12)
                    XCTAssertEqual(LayerBlend.encode(out[0]), LayerBlend.function(mode, backdrop: cb, source: cs), accuracy: 1e-9,
                                   "\(mode)(\(cb), \(cs))")
                }
            }
        }
    }

    func testAcceptanceGreys() {
        let grey = LayerBlend.premultipliedLinear(encoded: 0.5, 0.5, 0.5, alpha: 1)
        let expected: [LayerBlendMode: Double] = [.multiply: 0.25, .screen: 0.75, .overlay: 0.5, .difference: 0, .add: 1, .normal: 0.5]
        for (mode, value) in expected {
            let out = LayerBlend.composite(mode, backdrop: grey, source: grey)
            XCTAssertEqual(LayerBlend.encode(out[1]), value, accuracy: 1e-9, "\(mode) of two 50 % greys")
        }
    }

    func testAlphaCases() {
        let s = LayerBlend.premultipliedLinear(encoded: 0.75, 0.25, 0.5, alpha: 0.5)
        let b = LayerBlend.premultipliedLinear(encoded: 0.25, 1, 0.5, alpha: 0.5)
        for mode in LayerBlendMode.allCases {
            // Over a transparent backdrop every mode is normal "over".
            let alone = LayerBlend.composite(mode, backdrop: .zero, source: s)
            for i in 0..<4 { XCTAssertEqual(alone[i], s[i], accuracy: 1e-12, "\(mode) over transparent, channel \(i)") }
            // A transparent source (or opacity 0) leaves the backdrop.
            let none = LayerBlend.composite(mode, backdrop: b, source: s, opacity: 0)
            for i in 0..<4 { XCTAssertEqual(none[i], b[i], accuracy: 1e-12, "\(mode) at opacity 0, channel \(i)") }
            // Opacity scales the premultiplied source before the formula.
            let half = LayerBlend.composite(mode, backdrop: b, source: s, opacity: 0.5)
            let scaled = LayerBlend.composite(mode, backdrop: b, source: s * 0.5)
            for i in 0..<4 { XCTAssertEqual(half[i], scaled[i], accuracy: 1e-12) }
            XCTAssertEqual(half[3], 0.25 + 0.5 * 0.75, accuracy: 1e-12, "source-over alpha for \(mode)")
        }
        // Normal through the formula is plain premultiplied "over".
        let over = LayerBlend.composite(.normal, backdrop: b, source: s)
        for i in 0..<4 { XCTAssertEqual(over[i], s[i] + b[i] * 0.5, accuracy: 1e-12) }
        // Hand check, multiply at half alpha on both sides, red channel: Cs = 0.75, Cb = 0.25 (encoded).
        let mul = LayerBlend.composite(.multiply, backdrop: b, source: s)
        let fromSource: Double = 0.5 * LayerBlend.decode(0.75) * 0.5
        let fromBackdrop: Double = 0.5 * LayerBlend.decode(0.25) * 0.5
        let blended: Double = 0.25 * LayerBlend.decode(0.1875)
        let expectedRed: Double = fromSource + fromBackdrop + blended
        XCTAssertEqual(mul[0], expectedRed, accuracy: 1e-12)
    }

    func testSanitizingAndOutOfRangeValues() {
        let b = LayerBlend.premultipliedLinear(encoded: 0.5, 0.5, 0.5, alpha: 1)
        let broken = LayerBlend.Pixel(.nan, -1, .infinity, 1)
        let out = LayerBlend.composite(.screen, backdrop: b, source: broken)
        let black = LayerBlend.composite(.screen, backdrop: b, source: LayerBlend.Pixel(0, 0, 0, 1))
        for i in 0..<4 { XCTAssertEqual(out[i], black[i], accuracy: 1e-12, "non-finite and negative read 0") }
        // A linear value above 1 is clamped for B only: over a transparent backdrop it is kept.
        let bright = LayerBlend.Pixel(3, 0, 0, 1)
        XCTAssertEqual(LayerBlend.composite(.multiply, backdrop: .zero, source: bright)[0], 3, accuracy: 1e-12)
        XCTAssertEqual(LayerBlend.composite(.multiply, backdrop: b, source: bright)[0], b[0], accuracy: 1e-12, "clamped to 1, × backdrop")
    }
}
