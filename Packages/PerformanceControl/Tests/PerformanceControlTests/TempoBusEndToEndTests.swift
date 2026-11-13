// TempoBusEndToEndTests.swift — a real ANL-016 pipeline fed AUD-016's 120 BPM pulses reaches the
// tempo source as a detected tempo, and a reset of a manual tempo returns to it (SHOW-011-R8, R9,
// R14, S4; task SHOW-011-T05). Driven synchronously with `step()` and a step clock: no wall clock.
import AnalysisFeatures
import AudioCore
import PerformanceControl
import PerformanceControlAnalysis
import Synchronization
import XCTest

final class TempoBusEndToEndTests: XCTestCase {
    func testPulsesBecomeADetectedTempoAndResetReturnsToIt() throws {
        let rate = 44_100
        let generator = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: 0.002, amplitude: 0.5)),
                                          format: try ToneFormat(sampleRate: rate, channels: 2))
        let samples = generator.interleaved(frames: rate * 6)
        let ticks = Atomic<UInt64>(1_000_000_000)
        let pipeline = AnalysisPipeline(configuration: try AnalysisPipelineConfiguration(bandCount: .b16),
                                        clock: { ticks.add(1_000_000, ordering: .relaxed).oldValue })
        let reader = TempoSubscriptionReader(subscription: try pipeline.subscribe(), sampleRate: Double(rate))
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        pipeline.attach(try XCTUnwrap(ring.analysisTap))

        var source = TempoSource()
        let frames = samples.count / 2
        var offset = 0
        samples.withUnsafeBufferPointer { buffer in
            while offset < frames {
                let n = min(2_048, frames - offset)
                ring.write(buffer.baseAddress! + 2 * offset, frames: n)
                offset += n
                pipeline.step()
                source.updateEstimate(reader.poll())
            }
        }
        pipeline.detach()

        let detected = source.snapshot
        XCTAssertEqual(detected.origin, .estimated)
        XCTAssertEqual(try XCTUnwrap(detected.bpm), 120, accuracy: 1)
        XCTAssertGreaterThanOrEqual(detected.confidence, 0.8)
        XCTAssertNotNil(detected.anchorNanoseconds, "beat events give the phase")

        for i in 0..<4 { source.tap(at: 20_000_000_000 + UInt64(i) * 400_000_000) }
        XCTAssertEqual(source.snapshot.origin, .manual)
        XCTAssertEqual(try XCTUnwrap(source.snapshot.bpm), 150, accuracy: 1e-9)
        source.resetManual()
        XCTAssertEqual(source.snapshot, detected, "reset returns to the estimated state")

        // Detaching ended the session: the next poll reports no tempo.
        source.updateEstimate(reader.poll())
        XCTAssertEqual(source.snapshot, .none)
    }

    func testAFrameReadBeforeTheSessionEndsDoesNotBringTheTempoBack() throws {
        // One poll after the whole input and the detach: the newest frame (tempo 120) is older than
        // the session-ended marker, so the reader ends with no tempo.
        let rate = 44_100
        let generator = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: 0.002, amplitude: 0.5)),
                                          format: try ToneFormat(sampleRate: rate, channels: 2))
        let samples = generator.interleaved(frames: rate * 6)
        let pipeline = AnalysisPipeline(configuration: try AnalysisPipelineConfiguration(bandCount: .b16), clock: { 1_000_000_000 })
        let reader = TempoSubscriptionReader(subscription: try pipeline.subscribe(eventCapacity: 1_024), sampleRate: Double(rate))
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        pipeline.attach(try XCTUnwrap(ring.analysisTap))
        let frames = samples.count / 2
        var offset = 0
        samples.withUnsafeBufferPointer { buffer in
            while offset < frames {
                let n = min(2_048, frames - offset)
                ring.write(buffer.baseAddress! + 2 * offset, frames: n)
                offset += n
                pipeline.step()
            }
        }
        pipeline.detach()
        XCTAssertNil(reader.poll())
    }
}
