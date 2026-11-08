// Task T020: peak/RMS dBFS on generated signals.
import XCTest
import Foundation
@testable import AudioCore

final class LevelMeterTests: XCTestCase {
    private func sine(amplitude: Float, frequency: Double = 1000, rate: Double = 48_000, seconds: Double = 1) -> [Float] {
        (0..<Int(rate * seconds)).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / rate)) }
    }

    func testMinus6dBFSSine() {
        let amp = Float(pow(10.0, -6.0 / 20.0))
        let s = sine(amplitude: amp)
        let levels = s.withUnsafeBufferPointer { LevelMeter.measure($0.baseAddress!, count: $0.count) }
        XCTAssertEqual(levels.peakDBFS, -6, accuracy: 0.1)
        XCTAssertEqual(levels.rmsDBFS, -9.01, accuracy: 0.1)   // sine RMS = peak − 3.01 dB
    }

    func testDigitalSilenceClampsToFloor() {
        let s = [Float](repeating: 0, count: 4800)
        let levels = s.withUnsafeBufferPointer { LevelMeter.measure($0.baseAddress!, count: $0.count) }
        XCTAssertEqual(levels.peakDBFS, -120)
        XCTAssertEqual(levels.rmsDBFS, -120)
    }

    func testEmptyInputIsSilent() {
        let s: [Float] = [0.5]
        let levels = s.withUnsafeBufferPointer { LevelMeter.measure($0.baseAddress!, count: 0) }
        XCTAssertEqual(levels, .silent)
    }

    func testFullScale() {
        XCTAssertEqual(LevelMeter.dBFS(1), 0, accuracy: 0.0001)
        XCTAssertEqual(LevelMeter.dBFS(-1), -120)   // magnitude is the caller's job
    }
}
