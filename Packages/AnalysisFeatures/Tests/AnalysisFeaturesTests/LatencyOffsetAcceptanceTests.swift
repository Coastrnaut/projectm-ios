// LatencyOffsetAcceptanceTests.swift — AUD-013-T04, the roadmap acceptance: "Known pulse and frame
// timestamps produce offset within a documented tolerance." (specs/095-aud-013-source-latency-
// calibration, S1; research AUD-013-D6).
//
// Simulated time, no wall clock: a pulse train (20 ms bursts of a 200 Hz sine at 0.8, every 500 ms
// from 300 ms, 3 s) arrives in 512-frame buffers at their sample times into a normalized ring with an
// analysis tap; a `LatencyDelayReader(.analysis)` feeds the real `AnalysisPipeline` (injected clock),
// stepped every 10 ms like its worker; display frames at 60 Hz read the subscription's newest frame,
// as `LiveBandAnalyzer`'s "latest wins" frame loop does. A pulse is shown on the first display frame
// whose largest band reaches 0.5. The measured offset per pulse is that frame's time (and the
// analysis frame's host time) minus the same pulse's at 0 ms. Tolerance ±28.3 ms = one 60 Hz frame
// (16.7 ms) + one hop (512 frames, 11.6 ms).
import AudioCore
import Synchronization
import XCTest
@testable import AnalysisFeatures

/// Simulated monotonic nanoseconds, set by the test loop, read by the pipeline.
private final class SimulatedClock: Sendable {
    private let value = Atomic<UInt64>(0)
    func set(_ nanoseconds: UInt64) { value.store(nanoseconds, ordering: .relaxed) }
    var function: @Sendable () -> UInt64 { { [self] () -> UInt64 in self.value.load(ordering: .relaxed) } }
}

/// What a display frame showed for one pulse.
private struct Reaction {
    var displayMicroseconds: Int
    var hostNanoseconds: UInt64
}

final class LatencyOffsetAcceptanceTests: XCTestCase {
    private static let rate: Int = 44_100
    private static let bufferFrames: Int = 512
    private static let durationMicroseconds: Int = 3_000_000
    private static let stepMicroseconds: Int = 500
    private static let workerMicroseconds: Int = 10_000
    private static let pulseStartMicroseconds: Int = 300_000
    private static let pulsePeriodMicroseconds: Int = 500_000
    private static let pulseLengthMicroseconds: Int = 20_000
    /// One 60 Hz display frame + one 512-frame hop, in milliseconds.
    static let toleranceMilliseconds: Double = 1_000.0 / 60.0 + 512_000.0 / 44_100.0

    /// The pulse train, mono value per frame.
    private static func signal(totalFrames: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: totalFrames)
        let startFrame: Int = pulseStartMicroseconds * rate / 1_000_000
        let periodFrames: Int = pulsePeriodMicroseconds * rate / 1_000_000
        let lengthFrames: Int = pulseLengthMicroseconds * rate / 1_000_000
        var pulse: Int = startFrame
        while pulse + lengthFrames < totalFrames {
            for i in 0..<lengthFrames {
                let phase: Double = 2 * Double.pi * 200 * Double(i) / Double(rate)
                samples[pulse + i] = Float(0.8 * sin(phase))
            }
            pulse += periodFrames
        }
        return samples
    }

    static var pulseCount: Int {
        let usable: Int = durationMicroseconds - pulseStartMicroseconds - pulseLengthMicroseconds
        return usable / pulsePeriodMicroseconds + 1
    }

    /// Runs the simulation at `milliseconds` of visual delay; returns the first reaction per pulse.
    private func run(milliseconds: Double) throws -> [Reaction] {
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        let control = LatencyOffsetControl(targetFrames: LatencyOffset.frames(milliseconds: milliseconds))
        let reader = LatencyDelayReader(try XCTUnwrap(ring.analysisTap), control: control, mode: .analysis)
        let clock = SimulatedClock()
        let pipeline = AnalysisPipeline(configuration: .standard, clock: clock.function)
        let subscription = try pipeline.subscribe()
        pipeline.attach(reader)

        let totalFrames: Int = Self.durationMicroseconds * Self.rate / 1_000_000
        let mono: [Float] = Self.signal(totalFrames: totalFrames)
        var stereo = [Float](repeating: 0, count: Self.bufferFrames * 2)
        let bands = UnsafeMutablePointer<Float>.allocate(capacity: AnalysisSubscription.maximumBands)
        defer { bands.deallocate() }

        var written = 0
        var nextWorker = 0
        var nextDisplay = 0
        var displayIndex = 0
        var shown: Float = 0
        var shownHost: UInt64 = 0
        var armed = true
        var reactions: [Reaction] = []
        var t = 0
        while t <= Self.durationMicroseconds {
            clock.set(UInt64(t) * 1_000)
            // Buffers whose last frame has played by now arrive (capture callback cadence).
            while written + Self.bufferFrames <= totalFrames {
                let endMicroseconds: Int = (written + Self.bufferFrames) * 1_000_000 / Self.rate
                guard endMicroseconds <= t else { break }
                for i in 0..<Self.bufferFrames {
                    stereo[2 * i] = mono[written + i]
                    stereo[2 * i + 1] = mono[written + i]
                }
                stereo.withUnsafeBufferPointer { (p: UnsafeBufferPointer<Float>) -> Void in
                    ring.write(p.baseAddress!, frames: Self.bufferFrames)
                }
                written += Self.bufferFrames
            }
            if t >= nextWorker {
                pipeline.step()
                nextWorker += Self.workerMicroseconds
            }
            if t >= nextDisplay {
                if let frame = subscription.latestFrame(into: bands, capacity: AnalysisSubscription.maximumBands) {
                    var peak: Float = 0
                    for b in 0..<frame.bandCount where bands[b] > peak { peak = bands[b] }
                    shown = peak
                    shownHost = frame.time.hostNanoseconds
                }
                if armed && shown >= 0.5 {
                    reactions.append(Reaction(displayMicroseconds: nextDisplay, hostNanoseconds: shownHost))
                    armed = false
                } else if !armed && shown < 0.2 {
                    armed = true
                }
                displayIndex += 1
                nextDisplay = displayIndex * 1_000_000 / 60
            }
            t += Self.stepMicroseconds
        }
        pipeline.detach()
        return reactions
    }

    func testKnownPulsesShowTheConfiguredOffsetWithinTolerance() throws {
        let baseline: [Reaction] = try run(milliseconds: 0)
        // The last pulse may not reach the screen within 3 s at 250 ms; compare the pulses both runs show.
        XCTAssertGreaterThanOrEqual(baseline.count, Self.pulseCount - 1, "every pulse reacts at 0 ms")
        var table: [String] = ["AUD-013 S1 offset | pulses | mean display shift | max display error | mean host shift | max host error (ms; tolerance \(String(format: "%.1f", Self.toleranceMilliseconds)))"]
        let offsets: [Double] = [0, 100, 250]
        for offset in offsets {
            let delayed: [Reaction] = try run(milliseconds: offset)
            let pairs: Int = min(baseline.count, delayed.count)
            XCTAssertGreaterThanOrEqual(pairs, Self.pulseCount - 1, "offset \(offset): every pulse reacts")
            var displaySum: Double = 0
            var hostSum: Double = 0
            var displayWorst: Double = 0
            var hostWorst: Double = 0
            for i in 0..<pairs {
                let displayShift: Double = Double(delayed[i].displayMicroseconds - baseline[i].displayMicroseconds) / 1_000
                let hostDelta: Int64 = Int64(bitPattern: delayed[i].hostNanoseconds &- baseline[i].hostNanoseconds)
                let hostShift: Double = Double(hostDelta) / 1_000_000
                let displayError: Double = abs(displayShift - offset)
                let hostError: Double = abs(hostShift - offset)
                XCTAssertLessThanOrEqual(displayError, Self.toleranceMilliseconds, "offset \(offset), pulse \(i): display shift \(displayShift) ms")
                XCTAssertLessThanOrEqual(hostError, Self.toleranceMilliseconds, "offset \(offset), pulse \(i): host shift \(hostShift) ms")
                displaySum += displayShift
                hostSum += hostShift
                displayWorst = max(displayWorst, displayError)
                hostWorst = max(hostWorst, hostError)
            }
            let count: Double = Double(max(pairs, 1))
            let row: String = String(format: "%.0f | %d | %.1f | %.1f | %.1f | %.1f", offset, pairs, displaySum / count, displayWorst, hostSum / count, hostWorst)
            table.append(row)
        }
        print(table.joined(separator: "\n"))
    }

    /// AUD-013-R4: a negative offset is not supported; it clamps to 0 and behaves exactly as 0 ms.
    func testNegativeOffsetClampsToZero() throws {
        XCTAssertEqual(LatencyOffset.frames(milliseconds: -100), 0)
        let negative: [Reaction] = try run(milliseconds: -100)
        let zero: [Reaction] = try run(milliseconds: 0)
        XCTAssertEqual(negative.map(\.displayMicroseconds), zero.map(\.displayMicroseconds))
    }
}
