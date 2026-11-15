// TunnelDriveTests.swift — VIS-015-T03 (VIS-015-R4, R5; S1, S2; contract T1, T2): the roadmap acceptance "Tempo
// mapping changes speed and zero BPM falls back smoothly", on the pure drive with an injected 60 Hz clock and tempo.
// 120 BPM settles at exactly twice 60 BPM; at a tempo change the position advances by speed × dt every frame (no jump)
// and the speed moves by at most the one-pole bound; BPM 0, none, NaN, negative or unsure eases to the base speed with
// no NaN. Pure Swift (Linux too).
import XCTest
@testable import VisualGenerators

final class TunnelDriveTests: XCTestCase {
    private static let frame: UInt64 = 1_000_000_000 / 60
    private static let dt = Double(frame) / 1e9
    private let beat = NoiseFieldConfiguration.tunnel()

    /// Advances `frames` frames from frame `start` at `tempo`, checking continuity on every frame.
    private func run(_ drive: inout TunnelDrive, tempo: TunnelTempo, frames: Int, start: Int,
                     configuration: NoiseFieldConfiguration? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let c: NoiseFieldConfiguration = configuration ?? beat
        for f in start..<(start + frames) {
            let before: TunnelDrive = drive
            drive.advance(groups: .silence, tempo: tempo, timeNanoseconds: UInt64(f) * Self.frame, configuration: c)
            XCTAssertTrue(drive.speed.isFinite && drive.phase.isFinite && drive.brightness.isFinite, "frame \(f)", file: file, line: line)
            guard f > 0 else { continue }
            let bound: Double = abs(drive.target - before.speed) * (1 - exp(-Self.dt / TunnelDrive.speedTimeConstant))
            XCTAssertLessThanOrEqual(abs(drive.speed - before.speed), bound + 1e-12, "speed step at frame \(f)", file: file, line: line)
            var advanced: Double = drive.phase - before.phase
            if advanced < 0 { advanced += TunnelDrive.phasePeriod }
            XCTAssertEqual(advanced, drive.speed * Self.dt, accuracy: 1e-9, "position = speed × dt at frame \(f)", file: file, line: line)
        }
    }

    private func settled(_ tempo: TunnelTempo, configuration: NoiseFieldConfiguration? = nil) -> Double {
        var drive = TunnelDrive()
        run(&drive, tempo: TunnelTempo(bpm: 90, confidence: 1), frames: 30, start: 0, configuration: configuration)
        run(&drive, tempo: tempo, frames: 600, start: 30, configuration: configuration)
        return drive.speed
    }

    func testTempoMappingSetsTheSpeed() {
        let slow: Double = settled(TunnelTempo(bpm: 60, confidence: 1))
        let fast: Double = settled(TunnelTempo(bpm: 120, confidence: 0.8))
        XCTAssertEqual(slow, 1, accuracy: 1e-6, "one ring per beat at 60 BPM")
        XCTAssertEqual(fast / slow, 2, accuracy: 1e-6, "120 BPM moves exactly twice as fast as 60 BPM")
        XCTAssertEqual(TunnelDrive.targetSpeed(tempo: TunnelTempo(bpm: 120, confidence: 1), ringsPerBeat: 1, reduceMotion: false), 2)
        XCTAssertEqual(TunnelDrive.targetSpeed(tempo: TunnelTempo(bpm: 120, confidence: 1), ringsPerBeat: 0.5, reduceMotion: false), 1)
        XCTAssertEqual(TunnelDrive.targetSpeed(tempo: TunnelTempo(bpm: 80, confidence: 1), ringsPerBeat: 2, reduceMotion: false), 80.0 / 30)
    }

    func testPhaseIsContinuousAtATempoChange() {
        var drive = TunnelDrive()
        run(&drive, tempo: TunnelTempo(bpm: 60, confidence: 1), frames: 120, start: 0)
        let before: Double = drive.speed
        run(&drive, tempo: TunnelTempo(bpm: 120, confidence: 1), frames: 1, start: 120)
        XCTAssertLessThan(drive.speed - before, 0.04, "one frame moves the speed only a little")
        run(&drive, tempo: TunnelTempo(bpm: 120, confidence: 1), frames: 300, start: 121)
        XCTAssertEqual(drive.speed, 2, accuracy: 1e-3)
    }

    func testZeroOrLostTempoFallsBackSmoothlyToTheBaseSpeed() {
        let base: Double = TunnelDrive.baseRingsPerSecond
        let lost: [(String, TunnelTempo)] = [("BPM 0", TunnelTempo(bpm: 0, confidence: 1)), ("none", .none),
                                             ("NaN", TunnelTempo(bpm: .nan, confidence: 1)), ("negative", TunnelTempo(bpm: -5, confidence: 1)),
                                             ("unsure", TunnelTempo(bpm: 120, confidence: 0.3)),
                                             ("NaN confidence", TunnelTempo(bpm: 120, confidence: .nan))]
        for (name, tempo) in lost {
            var drive = TunnelDrive()
            run(&drive, tempo: TunnelTempo(bpm: 120, confidence: 1), frames: 300, start: 0)
            XCTAssertEqual(drive.speed, 2, accuracy: 1e-3)
            run(&drive, tempo: tempo, frames: 1, start: 300)
            XCTAssertGreaterThan(drive.speed, 1.98, "\(name): no jump on the first frame")
            run(&drive, tempo: tempo, frames: 400, start: 301)
            XCTAssertEqual(drive.speed, base, accuracy: 1e-3, "\(name): eased to the base speed")
            XCTAssertNil(tempo.validBPM, name)
        }
        XCTAssertEqual(settled(.none), base, accuracy: 1e-6)
    }

    func testFirstFrameTakesTheTargetAndTimeNeverRunsBackwards() {
        var drive = TunnelDrive()
        drive.advance(groups: .silence, tempo: TunnelTempo(bpm: 120, confidence: 1), timeNanoseconds: 5_000_000_000, configuration: beat)
        XCTAssertEqual(drive.speed, 2)
        XCTAssertEqual(drive.phase, 0, "the first frame is the anchor")
        drive.advance(groups: .silence, tempo: TunnelTempo(bpm: 120, confidence: 1), timeNanoseconds: 15_000_000_000, configuration: beat)
        XCTAssertEqual(drive.phase, 2 * TunnelDrive.maxStep, accuracy: 1e-12, "a 10 s gap moves at most 0.25 s worth")
        let before: Double = drive.phase
        drive.advance(groups: .silence, tempo: TunnelTempo(bpm: 120, confidence: 1), timeNanoseconds: 1_000_000_000, configuration: beat)
        XCTAssertEqual(drive.phase, before, "time going backwards does not move it")
        drive.reset()
        XCTAssertEqual(drive, TunnelDrive())
    }

    func testPaceChangeEasesAndPhaseWraps() {
        var drive = TunnelDrive()
        run(&drive, tempo: TunnelTempo(bpm: 60, confidence: 1), frames: 60, start: 0)
        run(&drive, tempo: TunnelTempo(bpm: 60, confidence: 1), frames: 400, start: 60, configuration: .tunnel(pace: .double))
        XCTAssertEqual(drive.speed, 2, accuracy: 1e-3, "2 rings per beat at 60 BPM")
        // Wrap: start close to the period by running the cap for a long simulated time with big steps.
        var long = TunnelDrive()
        var t: UInt64 = 0
        for _ in 0..<6000 {
            long.advance(groups: .silence, tempo: TunnelTempo(bpm: 200, confidence: 1), timeNanoseconds: t, configuration: .tunnel(pace: .double))
            t += 250_000_000
        }
        XCTAssertTrue(long.phase >= 0 && long.phase < TunnelDrive.phasePeriod, "wrapped: \(long.phase)")
        XCTAssertEqual(long.speed, TunnelDrive.maximumRingsPerSecond, accuracy: 1e-9)
    }

    func testPaceAndConfiguration() {
        XCTAssertEqual(TunnelPace.allCases.map(\.ringsPerBeat), [0.5, 1, 2])
        XCTAssertEqual(TunnelPace.beat.title, "1 ring per beat")
        XCTAssertNil(TunnelPace(ringsPerBeat: 0))
        XCTAssertEqual(NoiseFieldConfiguration(tunnelPace: 1.7).tunnelPace, 2, "snaps to a pace")
        XCTAssertEqual(NoiseFieldConfiguration(tunnelPace: .nan).tunnelPace, 0)
        let t = NoiseFieldConfiguration(wedges: 6, tunnelPace: 1)
        XCTAssertTrue(t.isTunnel)
        XCTAssertFalse(t.isKaleidoscope, "a tunnel is never folded")
        XCTAssertEqual(NoiseFieldConfiguration.tunnel().seed, 1301)
        XCTAssertFalse(NoiseFieldConfiguration().isTunnel)
    }
}
