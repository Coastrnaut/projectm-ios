// DisplayCalibrationTests.swift — OUT-009-T02 (specs/268-out-009-output-color-calibration; OUT-009-S1, S2): the
// transfer function and stored form of `DisplayCalibration`, pure Swift (also on Linux).
import Compositor
import Foundation
import XCTest

final class DisplayCalibrationTests: XCTestCase {
    func testTheDefaultsAreTheIdentity() {
        let c = DisplayCalibration.identity
        XCTAssertTrue(c.isIdentity)
        XCTAssertEqual(DisplayCalibration(gamma: 1, red: 1, green: 1, blue: 1), c)
        for e in [0.0, 0.001, 0.18, 0.5, 0.999, 1.0, -0.2, 1.3] {
            XCTAssertEqual(c.apply(encoded: e, channel: 0), e, "bypass, bit for bit")
        }
    }

    func testGainAndGammaMaths() {
        let c = DisplayCalibration(gamma: 2, red: 0.8, green: 1, blue: 1.2)
        XCTAssertEqual(c.exponent, 0.5)
        XCTAssertEqual(c.apply(encoded: 0.25, channel: 0), 0.8 * 0.5, accuracy: 1e-12, "red: 0.8 × 0.25^(1/2)")
        XCTAssertEqual(c.apply(encoded: 0.25, channel: 1), 0.5, accuracy: 1e-12)
        XCTAssertEqual(c.apply(encoded: 0.25, channel: 2), 0.6, accuracy: 1e-12)
        let darker = DisplayCalibration(gamma: 0.5, red: 1, green: 1, blue: 1)
        XCTAssertEqual(darker.apply(encoded: 0.5, channel: 1), 0.25, accuracy: 1e-12, "gamma below 1 darkens mid-tones")
        XCTAssertEqual(darker.apply(encoded: 0, channel: 1), 0, "black stays black")
        XCTAssertEqual(darker.apply(encoded: 1, channel: 1), 1, "white stays white at trim 1")
        let v = c.apply(encoded: SIMD3<Double>(1, 0.25, 0))
        XCTAssertEqual(v.x, 0.8, accuracy: 1e-12)
        XCTAssertEqual(v.y, 0.5, accuracy: 1e-12)
        XCTAssertEqual(v.z, 0)
    }

    func testValuesAndOutputAreClamped() {
        let c = DisplayCalibration(gamma: 9, red: 0.1, green: 3, blue: .nan)
        XCTAssertEqual(c.gamma, 2.5)
        XCTAssertEqual(c.red, 0.5)
        XCTAssertEqual(c.green, 1.5)
        XCTAssertEqual(c.blue, 1, "non-finite reads the default")
        XCTAssertEqual(c.apply(encoded: 0.9, channel: 1), 1, "1.5 × 0.9^0.4 is clamped to 1")
        XCTAssertEqual(c.apply(encoded: 1.7, channel: 0), 0.5, "input clamped to 1 first")
        XCTAssertEqual(c.apply(encoded: -1, channel: 0), 0)
        XCTAssertEqual(c.apply(encoded: .nan, channel: 0), 0)
        XCTAssertEqual(DisplayCalibration(gamma: 0.1, red: 1, green: 1, blue: 1).gamma, 0.5)
        XCTAssertEqual(DisplayCalibration.identity.with(red: 2).red, 1.5)
    }

    func testTheStoredFormRoundTripsAndRejectsGarbage() {
        let c = DisplayCalibration(gamma: 1.35, red: 0.8, green: 1, blue: 1.12)
        XCTAssertEqual(c.stored, "1.35,0.8,1,1.12")
        XCTAssertEqual(DisplayCalibration(stored: c.stored), c)
        XCTAssertEqual(DisplayCalibration.identity.stored, "1,1,1,1")
        XCTAssertEqual(DisplayCalibration(stored: " 3 ,0,1,1"), DisplayCalibration(gamma: 2.5, red: 0.5, green: 1, blue: 1), "clamped")
        for bad in ["", "1,1,1", "1,1,1,1,1", "a,1,1,1", "1,,1,1", "nan,1,1,1", "inf,1,1,1"] {
            XCTAssertNil(DisplayCalibration(stored: bad), bad)
        }
    }
}
