// ToneAnalyzerDeterminismTests.swift — the analysis that exists today (LevelMeter peak and RMS,
// AudioStateClassifier) gives identical results on repeated runs of every fixture
// (AUD-016-T11; AUD-016-R21, S6). FFT and beat outputs are ANL-001 and ANL-005's (spec, Hand-off).
import Foundation
import XCTest
@testable import AudioCore

final class ToneAnalyzerDeterminismTests: XCTestCase {
    private struct Run: Equatable {
        var levels: [LevelMeter.Levels] = []
        var states: [AudioState] = []
    }

    /// The 48 kHz stereo loop in 1,024-frame blocks, on a clock of frames / 48,000.
    private func analyze(_ fixture: ReferenceToneFixture) throws -> Run {
        let rate = 48_000, block = 1_024
        let loop = try fixture.loop(sampleRate: rate, channels: 2)
        var classifier = AudioStateClassifier()
        classifier.lifecycle(.started, at: 0)
        var run = Run()
        var frame = 0
        while frame < loop.count / 2 {
            let count = min(block, loop.count / 2 - frame)
            let levels = loop.withUnsafeBufferPointer { LevelMeter.measure($0.baseAddress! + frame * 2, count: count * 2) }
            frame += count
            let state = classifier.dataArrived(at: Double(frame) / Double(rate), peakDBFS: levels.peakDBFS,
                                               duration: Double(count) / Double(rate))
            run.levels.append(levels)
            run.states.append(state)
        }
        return run
    }

    func testLevelsAndStatesAreIdenticalOnRepeatedRuns() throws {
        for fixture in ReferenceToneCatalog.fixtures {
            let first = try analyze(fixture)
            let second = try analyze(fixture)
            XCTAssertEqual(first, second, fixture.id)
            XCTAssertEqual(first.levels.count, 469, fixture.id)   // 480,000 frames in 1,024-frame blocks
        }
    }

    /// The states today's classifier reaches (documented in contracts/fixture-catalog.md). A pulse
    /// train is mostly silence: its 2 ms pulses never hold −50 dBFS for 250 ms, so the classifier
    /// truthfully reports "Audio received — silent" (FR-011) although the clicks are audible.
    func testDocumentedFinalStatesAndLevels() throws {
        let expected: [String: AudioState] = [
            "sine-1k": .active, "sine-100": .active, "sine-1500": .active, "sine-split": .active,
            "sweep-log": .active, "sweep-linear": .active,
            "pulse-120": .silent, "pulse-120-accent": .silent, "pulse-132": .silent, "silence": .silent,
        ]
        for fixture in ReferenceToneCatalog.fixtures {
            let run = try analyze(fixture)
            XCTAssertEqual(run.states.last, expected[fixture.id], fixture.id)
        }
        let sine = try analyze(XCTUnwrap(ReferenceToneCatalog.fixture(id: "sine-1k")))
        XCTAssertEqual(sine.levels[10].peakDBFS, -12.04, accuracy: 0.01)
        XCTAssertEqual(sine.levels[10].rmsDBFS, -15.05, accuracy: 0.05)
        let silence = try analyze(XCTUnwrap(ReferenceToneCatalog.fixture(id: "silence")))
        XCTAssertTrue(silence.levels.allSatisfy { $0 == .silent })
    }
}
