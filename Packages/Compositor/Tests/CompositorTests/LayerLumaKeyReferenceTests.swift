// CMP-009-T04: the luma key's CPU reference (CMP-009-R1 to R3, R5; contracts/luma-key.md K1). Plain Swift, runs on
// Linux: the Rec. 709 luma of the displayed straight colour, the keep factor's range, ramp and invert, clamping.
import Compositor
import XCTest

final class LayerLumaKeyReferenceTests: XCTestCase {
    func testLumaUsesRec709WeightsOnDisplayedValues() {
        XCTAssertEqual(LayerLumaKey.luma(red: 0, green: 0, blue: 0, alpha: 1), 0)
        XCTAssertEqual(LayerLumaKey.luma(red: 1, green: 1, blue: 1, alpha: 1), 1, accuracy: 1e-12)
        XCTAssertEqual(LayerLumaKey.luma(red: 1, green: 0, blue: 0, alpha: 1), 0.2126, accuracy: 1e-12)
        XCTAssertEqual(LayerLumaKey.luma(red: 0, green: 1, blue: 0, alpha: 1), 0.7152, accuracy: 1e-12)
        XCTAssertEqual(LayerLumaKey.luma(red: 0, green: 0, blue: 1, alpha: 1), 0.0722, accuracy: 1e-12)
        // A grey whose displayed value is 0.5 has luma 0.5 (linear 0.214…).
        let grey: Double = LayerBlend.decode(0.5)
        XCTAssertEqual(LayerLumaKey.luma(red: grey, green: grey, blue: grey, alpha: 1), 0.5, accuracy: 1e-9)
    }

    func testLumaReadsTheStraightColourAndClampsIt() {
        let opaque: Double = LayerLumaKey.luma(red: 0.6, green: 0.3, blue: 0.1, alpha: 1)
        let half: Double = LayerLumaKey.luma(red: 0.3, green: 0.15, blue: 0.05, alpha: 0.5)
        XCTAssertEqual(half, opaque, accuracy: 1e-12, "premultiplied input: alpha does not change the luma")
        XCTAssertEqual(LayerLumaKey.luma(red: 1, green: 1, blue: 1, alpha: 0), 0, "alpha 0 reads 0")
        XCTAssertEqual(LayerLumaKey.luma(red: 4, green: 4, blue: 4, alpha: 1), 1, accuracy: 1e-12, "over-bright clamps to 1")
        XCTAssertEqual(LayerLumaKey.luma(red: .nan, green: -1, blue: .infinity, alpha: 1), 0, "non-finite and negative read 0")
    }

    func testKeepIsZeroInsideAndOneBeyondTheSoftness() {
        let key = LayerLumaKey(low: 0.2, high: 0.4, softness: 0.1)
        for y: Double in [0.2, 0.25, 0.3, 0.4] { XCTAssertEqual(key.keep(luma: y), 0, "inside at \(y)") }
        for y: Double in [0, 0.1, 0.5, 0.75, 1] { XCTAssertEqual(key.keep(luma: y), 1, accuracy: 1e-12, "outside at \(y)") }
        XCTAssertEqual(key.keep(luma: 0.15), 0.5, accuracy: 1e-12)
        XCTAssertEqual(key.keep(luma: 0.45), 0.5, accuracy: 1e-12)
    }

    func testTheRampIsMonotonicOnBothSides() {
        let key = LayerLumaKey(low: 0.3, high: 0.5, softness: 0.25)
        var violations = 0
        var previous: Double = key.keep(luma: 0)
        for i in 1...4096 {
            let y: Double = Double(i) / 4096
            let k: Double = key.keep(luma: y)
            let expectFalling: Bool = y <= 0.3
            let expectRising: Bool = y > 0.5
            if expectFalling && k > previous { violations += 1 }
            if expectRising && k < previous { violations += 1 }
            previous = k
        }
        XCTAssertEqual(violations, 0)
    }

    func testSoftnessZeroIsAHardCutAndInvertIsTheComplement() {
        let hard = LayerLumaKey(low: 0, high: 0.1)
        XCTAssertEqual(hard.keep(luma: 0.1), 0)
        XCTAssertEqual(hard.keep(luma: 0.1001), 1)
        let key = LayerLumaKey(low: 0.2, high: 0.4, softness: 0.1)
        let inverted = LayerLumaKey(low: 0.2, high: 0.4, softness: 0.1, inverted: true)
        for i in 0...20 {
            let y: Double = Double(i) / 20
            XCTAssertEqual(inverted.keep(luma: y), 1 - key.keep(luma: y), accuracy: 1e-12)
        }
    }

    func testBlackKeyRemovesBlackAndKeepsBrightColour() {
        let key = LayerLumaKey.blackKey
        XCTAssertEqual(key.keep(red: 0, green: 0, blue: 0, alpha: 1), 0)
        XCTAssertEqual(key.keep(red: 0.8, green: 0.6, blue: 0.4, alpha: 1), 1)
    }

    func testValuesAreClampedAndAReversedRangeSwapped() {
        let key = LayerLumaKey(low: 0.7, high: 0.2, softness: 2)
        XCTAssertEqual(key.low, 0.2)
        XCTAssertEqual(key.high, 0.7)
        XCTAssertEqual(key.softness, 0.5)
        let wild = LayerLumaKey(low: -1, high: .nan, softness: -0.0)
        XCTAssertEqual(wild.low, 0)
        XCTAssertEqual(wild.high, 0.1)
        XCTAssertEqual(wild.softness, 0)
        XCTAssertEqual(wild.softness.sign, .plus)
        XCTAssertEqual(LayerLumaKey.blackKey, LayerLumaKey(low: 0, high: 0.1, softness: 0.05, inverted: false))
    }

    func testSettingsCarryTheKey() {
        XCTAssertNil(LayerCompositeSettings().lumaKey)
        XCTAssertEqual(LayerCompositeSettings(lumaKey: .blackKey).lumaKey, .blackKey)
        XCTAssertNotEqual(LayerCompositeSettings(lumaKey: .blackKey), LayerCompositeSettings())
    }
}
