// CMP-010-T04: the colour key's CPU reference (contracts/color-key.md C1 in specs/230-cmp-010-color-key). Plain Swift,
// runs on Linux. The GPU tests (LayerColorKeyCompositeTests) compare the shader against these numbers.
import Compositor
import XCTest

final class LayerColorKeyReferenceTests: XCTestCase {
    /// A displayed (sRGB) colour as the compositor holds it: premultiplied linear, opaque.
    private static func linear(_ r: Double, _ g: Double, _ b: Double, alpha: Double = 1) -> (Double, Double, Double, Double) {
        (LayerBlend.decode(r) * alpha, LayerBlend.decode(g) * alpha, LayerBlend.decode(b) * alpha, alpha)
    }

    private static func keep(_ key: LayerColorKey, _ p: (Double, Double, Double, Double)) -> Double {
        key.keep(red: p.0, green: p.1, blue: p.2, alpha: p.3)
    }

    func testNeutralsHaveNoChromaAndPrimariesFollowRec709() {
        for v in [0.0, 0.25, 0.5, 1.0] {
            let p = Self.linear(v, v, v)
            let c = LayerColorKey.chroma(red: p.0, green: p.1, blue: p.2, alpha: p.3)
            XCTAssertEqual(c.cb, 0, accuracy: 1e-9)
            XCTAssertEqual(c.cr, 0, accuracy: 1e-9)
        }
        let green = LayerColorKey.greenKey.keyChroma
        XCTAssertEqual(green.cb, -0.7152 / 1.8556, accuracy: 1e-9)
        XCTAssertEqual(green.cr, -0.7152 / 1.5748, accuracy: 1e-9)
        let red = LayerColorKey.chroma(red: 1, green: 0, blue: 0, alpha: 1)
        XCTAssertEqual(red.cr, 0.5, accuracy: 1e-9, "Cr of pure red is 0.5")
        let blue = LayerColorKey.chroma(red: 0, green: 0, blue: 1, alpha: 1)
        XCTAssertEqual(blue.cb, 0.5, accuracy: 1e-9, "Cb of pure blue is 0.5")
    }

    func testPremultipliedInputAndTransparentPixels() {
        let opaque = Self.linear(0.2, 0.8, 0.3)
        let half = Self.linear(0.2, 0.8, 0.3, alpha: 0.5)
        let a = LayerColorKey.chroma(red: opaque.0, green: opaque.1, blue: opaque.2, alpha: opaque.3)
        let b = LayerColorKey.chroma(red: half.0, green: half.1, blue: half.2, alpha: half.3)
        XCTAssertEqual(a.cb, b.cb, accuracy: 1e-9)
        XCTAssertEqual(a.cr, b.cr, accuracy: 1e-9)
        let clear = LayerColorKey.chroma(red: 0.5, green: 0.5, blue: 0.5, alpha: 0)
        XCTAssertEqual(clear.cb, 0)
        XCTAssertEqual(clear.cr, 0)
        XCTAssertEqual(LayerColorKey.chroma(red: .nan, green: .infinity, blue: 0, alpha: 1).cb, 0, accuracy: 1e-9,
                       "non-finite channels read 0")
    }

    /// The acceptance colours: the green patch is keyed out; red, blue, white, skin and dark green are kept.
    func testFixtureColoursUnderTheGreenKey() {
        let key: LayerColorKey = .greenKey
        XCTAssertEqual(Self.keep(key, Self.linear(0, 1, 0)), 0)
        let kept: [(String, (Double, Double, Double, Double))] = [
            ("red", Self.linear(1, 0, 0)), ("blue", Self.linear(0, 0, 1)), ("white", Self.linear(1, 1, 1)),
            ("skin", Self.linear(0.87, 0.67, 0.55)), ("dark green", Self.linear(0, 0.3, 0)),
        ]
        for (name, p) in kept {
            XCTAssertEqual(Self.keep(key, p), 1, name)
            let d: Double = key.distance(red: p.0, green: p.1, blue: p.2, alpha: p.3)
            XCTAssertGreaterThan(d, key.tolerance + key.feather + 0.05, "\(name) is well beyond the feather (d \(d))")
        }
    }

    func testFeatherRampIsMonotonicAndHardCutWithoutFeather() {
        let key = LayerColorKey(red: 0, green: 1, blue: 0, tolerance: 0.2, feather: 0.2)
        XCTAssertEqual(key.keep(distance: 0.2), 0)
        XCTAssertEqual(key.keep(distance: 0.3), 0.5, accuracy: 1e-12)
        XCTAssertEqual(key.keep(distance: 0.4), 1, accuracy: 1e-12)
        var violations = 0
        var previous: Double = -1
        for i in 0...1000 {
            // Displayed colours from green to mid-grey: the distance grows linearly with t.
            let t: Double = Double(i) / 1000
            let p = Self.linear(0.5 * t, 1 - 0.5 * t, 0.5 * t)
            let k: Double = Self.keep(key, p)
            if k < previous - 1e-12 { violations += 1 }
            previous = k
        }
        XCTAssertEqual(violations, 0)
        XCTAssertEqual(previous, 1, accuracy: 1e-9, "grey is kept")
        let hard = LayerColorKey(red: 0, green: 1, blue: 0, tolerance: 0.2, feather: 0)
        XCTAssertEqual(hard.keep(distance: 0.2), 0)
        XCTAssertEqual(hard.keep(distance: 0.2000001), 1)
    }

    func testClampingAndNonFiniteDefaults() {
        let k = LayerColorKey(red: 2, green: -1, blue: .nan, tolerance: 5, feather: -0.0)
        XCTAssertEqual(k.red, 1)
        XCTAssertEqual(k.green, 0)
        XCTAssertEqual(k.blue, 0)
        XCTAssertEqual(k.tolerance, 1)
        XCTAssertEqual(k.feather, 0)
        XCTAssertEqual(k.feather.sign, .plus, "−0 is stored as 0")
        let d = LayerColorKey(red: .infinity, green: .nan, blue: 0, tolerance: .nan, feather: .infinity)
        XCTAssertEqual(d, LayerColorKey.greenKey, "non-finite values read the green key's")
        XCTAssertEqual(LayerColorKey(red: 0, green: 0, blue: 0, feather: 0.9).feather, 0.5)
    }
}
