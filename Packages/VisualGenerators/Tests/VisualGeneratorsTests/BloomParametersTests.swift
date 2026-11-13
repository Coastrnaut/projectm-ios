// BloomParametersTests.swift — FX-001-T03: bloom parameters, ranges, clamping and the soft-knee
// threshold (FX-001-R3, R4, R6; research FX-001-D3 step 1, D5). Pure arithmetic; runs on Linux.
import XCTest
import VisualGenerators
@testable import VisualEffects

final class BloomParametersTests: XCTestCase {
    func testDefaults() {
        let p = BloomParameters()
        XCTAssertFalse(p.enabled, "Glow is off by default")
        XCTAssertEqual(p.intensity, 0.5)
        XCTAssertEqual(p.radius, 0.02)
        XCTAssertEqual(p.threshold, 0.7)
        XCTAssertEqual(p.knee, 0.5)
        XCTAssertTrue(p.isPassThrough)
        XCTAssertEqual(BloomParameters.intensityRange, 0...1)
        XCTAssertEqual(BloomParameters.radiusRange, 0.005...0.06)
        XCTAssertEqual(BloomParameters.thresholdRange, 0.1...1)
        XCTAssertEqual(BloomParameters.kneeRange, 0...1)
    }

    func testClampingAndNonFiniteValues() {
        let low = BloomParameters(enabled: true, intensity: -1, radius: 0, threshold: 0, knee: -2).clamped()
        XCTAssertEqual(low, BloomParameters(enabled: true, intensity: 0, radius: 0.005, threshold: 0.1, knee: 0))
        let high = BloomParameters(enabled: true, intensity: 9, radius: 1, threshold: 5, knee: 3).clamped()
        XCTAssertEqual(high, BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 1, knee: 1))
        let nan = BloomParameters(enabled: true, intensity: .nan, radius: .nan, threshold: .nan, knee: .nan).clamped()
        XCTAssertEqual(nan, BloomParameters(enabled: true), "NaN reads the default")
        let inf = BloomParameters(enabled: true, intensity: .infinity, radius: -.infinity, threshold: .infinity, knee: -.infinity).clamped()
        XCTAssertEqual(inf, BloomParameters(enabled: true, intensity: 1, radius: 0.005, threshold: 1, knee: 0))
    }

    func testPassThrough() {
        XCTAssertTrue(BloomParameters(enabled: false, intensity: 1).isPassThrough)
        XCTAssertTrue(BloomParameters(enabled: true, intensity: 0).isPassThrough)
        XCTAssertTrue(BloomParameters(enabled: true, intensity: -3).isPassThrough, "clamped to 0")
        XCTAssertFalse(BloomParameters(enabled: true, intensity: 0.01).isPassThrough)
    }

    func testContributionIsZeroAtOrBelowTheKneeAndExactAboveIt() {
        for threshold: Float in [0.1, 0.4, 0.7, 1] {
            for knee: Float in [0, 0.25, 0.5, 1] {
                let p = BloomParameters(enabled: true, intensity: 1, threshold: threshold, knee: knee)
                let k = p.kneeWidth
                XCTAssertEqual(k, threshold * knee, accuracy: 1e-7)
                // At or below T − K: exactly zero.
                for i in 0...200 {
                    let b = (threshold - k) * Float(i) / 200
                    XCTAssertEqual(p.contribution(ofMaxChannel: b), 0, "T=\(threshold) κ=\(knee) b=\(b)")
                }
                // Above T + K: exactly (b − T)/b.
                for i in 1...50 {
                    let b = threshold + k + Float(i) * 0.05
                    XCTAssertEqual(p.contribution(ofMaxChannel: b), (b - threshold) / b, accuracy: 1e-6)
                }
                // Continuous, nondecreasing, within 0…1 across the whole range.
                var previous: Float = 0
                for i in 0...4000 {
                    let b = Float(i) / 1000
                    let w = p.contribution(ofMaxChannel: b)
                    XCTAssertGreaterThanOrEqual(w, 0)
                    XCTAssertLessThanOrEqual(w, 1)
                    XCTAssertGreaterThanOrEqual(w, previous - 1e-6, "nondecreasing at b=\(b)")
                    XCTAssertLessThanOrEqual(abs(w - previous), 0.02, "continuous at b=\(b)")
                    previous = w
                }
            }
        }
    }

    func testThresholdedColorNeverExceedsTheInputAndSanitizes() {
        let p = BloomParameters(enabled: true, intensity: 1, threshold: 0.3, knee: 0.5)
        XCTAssertEqual(p.thresholded(LinearColor(red: 0, green: 0, blue: 0, alpha: 0)), LinearColor(red: 0, green: 0, blue: 0, alpha: 0))
        XCTAssertEqual(p.thresholded(.opaqueBlack), LinearColor(red: 0, green: 0, blue: 0, alpha: 0), "black contributes nothing")
        for c in [LinearColor(red: 1, green: 1, blue: 1), LinearColor(red: 0.9, green: 0.1, blue: 0.4),
                  LinearColor(red: 0.2, green: 0.25, blue: 0.1), LinearColor(red: 3, green: 2, blue: 1)] {
            let t = p.thresholded(c)
            XCTAssertLessThanOrEqual(t.red, c.red); XCTAssertLessThanOrEqual(t.green, c.green)
            XCTAssertLessThanOrEqual(t.blue, c.blue); XCTAssertLessThanOrEqual(t.alpha, c.alpha)
            XCTAssertGreaterThanOrEqual(t.red, 0)
        }
        let bad = p.thresholded(LinearColor(red: .nan, green: .infinity, blue: -1, alpha: 1))
        XCTAssertEqual(bad, LinearColor(red: 0, green: 0, blue: 0, alpha: 0), "NaN, ∞ and negatives read 0, so nothing is above the threshold")
        let huge = p.thresholded(LinearColor(red: 1e9, green: 0, blue: 0, alpha: 1))
        XCTAssertLessThanOrEqual(huge.red, BloomParameters.maximumComponent)
        XCTAssertTrue(huge.red.isFinite)
    }

    func testCodableClampsAndFillsMissingFields() throws {
        let json = #"{"enabled":true,"intensity":4,"radius":0.03}"#
        let p = try JSONDecoder().decode(BloomParameters.self, from: Data(json.utf8))
        XCTAssertEqual(p, BloomParameters(enabled: true, intensity: 1, radius: 0.03, threshold: 0.7, knee: 0.5))
        let back = try JSONDecoder().decode(BloomParameters.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }
}
