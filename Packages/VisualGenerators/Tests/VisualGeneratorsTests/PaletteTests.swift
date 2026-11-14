// PaletteTests.swift — VIS-001-T03: the minimal palette set and the color math (VIS-001-R6,
// research VIS-001-D4, D7).
import XCTest
@testable import VisualGenerators

final class PaletteTests: XCTestCase {
    func testSRGBRoundTrip() {
        for i in 0...255 {
            let v = Float(i) / 255
            XCTAssertEqual(SRGB.encode(SRGB.decode(v)), v, accuracy: 1e-6)
        }
        XCTAssertEqual(SRGB.decode(0), 0)
        XCTAssertEqual(SRGB.decode(1), 1, accuracy: 1e-7)
        XCTAssertEqual(SRGB.decode(0.5), 0.21404, accuracy: 1e-4, "sRGB 0.5 ≈ 21.4 % linear")
    }

    func testMonoIsWhite() {
        for n in [16, 128] {
            for k in [0, n / 2, n - 1] {
                let c = VisualPalette.mono.color(bar: k, of: n)
                XCTAssertEqual(c, LinearColor(red: 1, green: 1, blue: 1, alpha: 1))
                XCTAssertEqual(c.relativeLuminance, 1, accuracy: 1e-6)
            }
        }
    }

    func testSpectrumRunsFromRedToViolet() {
        let first = VisualPalette.spectrum.color(bar: 0, of: 64)
        XCTAssertEqual(first.red, 1, accuracy: 1e-6)
        XCTAssertEqual(first.green, 0, accuracy: 1e-6)
        XCTAssertEqual(first.blue, 0, accuracy: 1e-6)
        // Hue 270°: sRGB (0.5, 0, 1).
        let last = VisualPalette.spectrum.color(bar: 63, of: 64)
        XCTAssertEqual(last.red, SRGB.decode(0.5), accuracy: 1e-5)
        XCTAssertEqual(last.green, 0, accuracy: 1e-6)
        XCTAssertEqual(last.blue, 1, accuracy: 1e-6)
    }

    func testIceEndpoints() {
        let a = VisualPalette.ice.color(bar: 0, of: 32)
        let b = VisualPalette.ice.color(bar: 31, of: 32)
        XCTAssertEqual(a, LinearColor.fromSRGB(red: 0x2E, green: 0xC4, blue: 0xFF))
        XCTAssertEqual(b, LinearColor.fromSRGB(red: 0xE8, green: 0xF7, blue: 0xFF))
    }

    /// ACC-003-R13: luminance rises strictly bar by bar (the order survives grayscale and every colour
    /// vision deficiency), and the first bar has at least 3:1 against black.
    func testColorBlindSafeRampRisesInLuminanceAndStartsVisible() {
        for n in [16, 64, 128] {
            var previous: Float = -1
            for k in 0..<n {
                let y = VisualPalette.colorBlindSafe.color(bar: k, of: n).relativeLuminance
                XCTAssertGreaterThan(y, previous, "bar \(k)/\(n)")
                previous = y
            }
        }
        let first = VisualPalette.colorBlindSafe.color(bar: 0, of: 64).relativeLuminance
        XCTAssertGreaterThanOrEqual((first + 0.05) / 0.05, 3, "first bar against black")
        XCTAssertEqual(VisualPalette.colorBlindSafe.color(bar: 63, of: 64), LinearColor.fromSRGB(red: 0xFD, green: 0xE7, blue: 0x38))
    }

    func testEveryColorIsInRangeAndOpaque() {
        for palette in VisualPalette.allCases {
            for n in [16, 32, 64, 128] {
                for k in 0..<n {
                    let c = palette.color(bar: k, of: n)
                    for v in [c.red, c.green, c.blue] { XCTAssertTrue((0...1).contains(v), "\(palette) \(k)/\(n)") }
                    XCTAssertEqual(c.alpha, 1)
                    XCTAssertTrue((0...1).contains(c.relativeLuminance))
                }
            }
        }
    }

    func testRelativeLuminanceWeights() {
        XCTAssertEqual(LinearColor(red: 1, green: 0, blue: 0, alpha: 1).relativeLuminance, 0.2126, accuracy: 1e-6)
        XCTAssertEqual(LinearColor(red: 0, green: 1, blue: 0, alpha: 1).relativeLuminance, 0.7152, accuracy: 1e-6)
        XCTAssertEqual(LinearColor(red: 0, green: 0, blue: 1, alpha: 1).relativeLuminance, 0.0722, accuracy: 1e-6)
        XCTAssertEqual(LinearColor.opaqueBlack.relativeLuminance, 0)
    }
}
