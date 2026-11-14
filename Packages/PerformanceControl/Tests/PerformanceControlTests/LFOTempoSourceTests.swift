// LFOTempoSourceTests.swift — MOD-009-T05: the tempo source order for synced oscillators (MOD-009-R3, S2;
// specs/165-mod-009-tempo-lfo, contract T4). A real `TempoSource` feeds `snapshot.lfoTempoBPM` to an `LFOBank`; the
// oscillator's effective rate shows which tempo it follows. Times are passed in.
import ParameterGraph
import PerformanceControl
import XCTest

final class LFOTempoSourceTests: XCTestCase {
    private static let second: UInt64 = 1_000_000_000

    private func rate(_ source: TempoSource, _ lfo: LFO) -> Double {
        lfo.effectiveRateHz(tempoBPM: source.snapshot.lfoTempoBPM)
    }

    func testManualThenConfidentEstimateThenFallback() throws {
        let lfo = try LFO(shape: .sine, rateHz: 0.25, sync: LFOSync(beatsPerCycle: 1))
        var source = TempoSource()
        XCTAssertNil(source.snapshot.lfoTempoBPM, "no tempo at all")
        XCTAssertEqual(rate(source, lfo), 0.25, "no tempo: the stored fallback rate")

        source.updateEstimate(TempoEstimate(bpm: 100, confidence: 0.8, beatNanoseconds: nil))
        XCTAssertEqual(source.snapshot.lfoTempoBPM, 100)
        XCTAssertEqual(rate(source, lfo), 100.0 / 60, accuracy: 1e-12, "a confident estimate is followed")

        for tap in 0..<4 { source.tap(at: 10 * Self.second + UInt64(tap) * Self.second / 2) }   // 500 ms apart
        XCTAssertEqual(source.snapshot.origin, .manual)
        XCTAssertEqual(rate(source, lfo), 2, accuracy: 1e-9, "the manual tap tempo (120 BPM) wins over the estimate")

        source.resetManual()
        source.updateEstimate(TempoEstimate(bpm: 100, confidence: 0.3, beatNanoseconds: nil))
        XCTAssertNil(source.snapshot.lfoTempoBPM, "an estimate below confidence 0.5 is not a tempo")
        XCTAssertEqual(rate(source, lfo), 0.25, "weak detection: the stored fallback rate")
        source.updateEstimate(TempoEstimate(bpm: 100, confidence: TapTempoRules.standard.minimumEstimateConfidence, beatNanoseconds: nil))
        XCTAssertEqual(rate(source, lfo), 100.0 / 60, accuracy: 1e-12, "confidence exactly 0.5 counts")
    }

    func testBankFollowsTheSourceAcrossChanges() throws {
        let lfo = try LFO(shape: .triangle, rateHz: 0.25, sync: LFOSync(beatsPerCycle: 2))
        let bank = LFOBank()
        try bank.set([lfo])
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: 120, confidence: 0.9, beatNanoseconds: nil))
        var out: [Double] = [0]
        let frame: UInt64 = 16_666_667
        var previous: Double?
        for index in 0...180 {
            if index == 90 { source.updateEstimate(TempoEstimate(bpm: 120, confidence: 0.2, beatNanoseconds: nil)) }   // lost
            out.withUnsafeMutableBufferPointer { (buffer: inout UnsafeMutableBufferPointer<Double>) -> Void in
                bank.values(atNanoseconds: UInt64(index) * frame, tempoBPM: source.snapshot.lfoTempoBPM, into: buffer)
            }
            if let previous { XCTAssertLessThanOrEqual(abs(out[0] - previous), 2 * 1 * Double(frame) / 1e9 + 1e-9, "frame \(index)") }
            previous = out[0]
        }
        let phaseAtLoss: Double = 1 * Double(90 * frame) / 1e9   // 2 beats at 120 BPM = 1 Hz
        let expectedCycles: Double = phaseAtLoss + 0.25 * Double(90 * frame) / 1e9
        XCTAssertEqual(out[0], lfo.value(atPhase: expectedCycles - expectedCycles.rounded(.down)), accuracy: 1e-9,
                       "after detection is lost the oscillator continues at its stored 0.25 Hz")
    }
}
