// FrameTimingsExportTests.swift — PERF-001-T14 (PERF-001-R10; specs/152-perf-001-stage-timings data-model.md):
// the optional frame timings round-trip through the export, validate against the schema, and leave exports
// without them unchanged.
import AudioCore
@testable import Diagnostics
import Foundation
import XCTest

final class FrameTimingsExportTests: XCTestCase {
    private func snapshot(_ timings: DiagnosticsSnapshot.FrameTimings?) throws -> DiagnosticsSnapshot {
        let format = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: true, sampleType: .float32)
        let input = DiagnosticsInput(
            sourceMode: .inAppPlayback, finalState: .active, stopReason: nil, hasVerifiedActiveAudio: true,
            statistics: PCMSinkStatistics(sampleCount: 48_000, bufferCount: 100, firstSampleSeconds: 0.05,
                                          lastSampleSeconds: 1.05, cadenceMeanMs: 10.7, cadenceMaxMs: 23,
                                          droppedSamples: 0, lateBuffers: 0, format: format,
                                          formatChangeCount: 0, startToFirstAudioMs: 50),
            durationSeconds: 1.1, formats: [(format, 0.05)], peakDBFSMax: -6, rmsDBFSMean: -12,
            transitions: [StateTransition(atSeconds: 0, state: .active)], lifecycle: [])
        var snap = try DiagnosticsSnapshot.build(from: input, note: nil,
                                                 device: .init(model: "iPhone15,4", osVersion: "27.0.1", osBuild: "24A1"),
                                                 app: .init(version: "1.1", build: "2", toolchain: nil),
                                                 exportedAt: Date(timeIntervalSince1970: 1_800_000_000))
        snap.frameTimings = timings
        return snap
    }

    private static let timings = DiagnosticsSnapshot.FrameTimings(
        windowFrames: 120, rejectedSamples: 2, frameGPUMedianMs: 4.25, frameGPUP95Ms: 5.5,
        stages: [.init(name: "audio", samples: 120, cpuMedianMs: 0.05, cpuP95Ms: 0.09),
                 .init(name: "composite", samples: 120, cpuMedianMs: 1.5, cpuP95Ms: 2.25),
                 .init(name: "output", samples: 118, cpuMedianMs: 0.25, cpuP95Ms: 0.5, gpuMedianMs: 1, gpuP95Ms: 1.25),
                 .init(name: "present", samples: 0)])

    private func schemaErrors(_ data: Data) throws -> [String] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "diagnostics-export.schema", withExtension: "json"))
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let json = try JSONSerialization.jsonObject(with: data)
        var errors: [String] = []
        MiniSchemaValidator.validate(json, against: schema, path: "$", errors: &errors)
        return errors
    }

    func testFrameTimingsRoundTripAndValidate() throws {
        let original = try snapshot(Self.timings)
        let data = try DiagnosticsExporter.encode(original)
        XCTAssertEqual(try schemaErrors(data), [])
        let decoded = try JSONDecoder().decode(DiagnosticsSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.frameTimings?.stages.map(\.name), ["audio", "composite", "output", "present"])
        // Unavailable values are absent keys, never 0 or null.
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let stages = try XCTUnwrap((object["frameTimings"] as? [String: Any])?["stages"] as? [[String: Any]])
        XCTAssertNil(stages[0]["gpuMedianMs"])
        XCTAssertEqual(Set(stages[3].keys), ["name", "samples"])
    }

    func testExportWithoutFrameTimingsHasNoKeyAndStillValidates() throws {
        let data = try DiagnosticsExporter.encode(try snapshot(nil))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["frameTimings"])
        XCTAssertEqual(try schemaErrors(data), [])
        XCTAssertFalse(DiagnosticsExporter.text(try snapshot(nil)).contains("Frame stages"))
    }

    func testUnknownNamesAndInvalidValuesAreDropped() throws {
        let timings = DiagnosticsSnapshot.FrameTimings(
            windowFrames: -1, rejectedSamples: 0, frameGPUMedianMs: .nan, frameGPUP95Ms: -1,
            stages: [.init(name: "bogus", samples: 1), .init(name: "render", samples: 3, cpuMedianMs: .infinity, cpuP95Ms: 2)])
        XCTAssertEqual(timings.windowFrames, 0)
        XCTAssertNil(timings.frameGPUMedianMs)
        XCTAssertNil(timings.frameGPUP95Ms)
        XCTAssertEqual(timings.stages, [.init(name: "render", samples: 3, cpuMedianMs: nil, cpuP95Ms: 2)])
        XCTAssertEqual(try schemaErrors(DiagnosticsExporter.encode(try snapshot(timings))), [])
    }

    func testTextExportListsTheStages() throws {
        let text = DiagnosticsExporter.text(try snapshot(Self.timings))
        XCTAssertTrue(text.contains("Frame stages over 120 frames (median/p95 ms):"))
        XCTAssertTrue(text.contains("  audio: CPU 0.05/0.09\n"))
        XCTAssertTrue(text.contains("  output: CPU 0.25/0.50, GPU 1.00/1.25\n"))
        XCTAssertTrue(text.contains("  present: CPU n/a\n"))
        XCTAssertTrue(text.contains("  frame GPU: 4.25/5.50\n"))
        XCTAssertTrue(text.contains("  rejected samples: 2\n"))
    }

    // MARK: - PERF-002-T10: the budget verdict (optional)

    private static let budget = DiagnosticsSnapshot.FrameTimings.Budget(
        framesPerSecond: 60, deadlineMs: 16.666, thresholdShare: 0.8, clearShare: 0.7, thresholdMs: 13.333,
        cpuEstimateMs: 15.5, gpuEstimateMs: nil, flaggedPasses: ["composite cpu"])

    func testBudgetRoundTripsAndValidates() throws {
        var timings = Self.timings
        timings.budget = Self.budget
        let original = try snapshot(timings)
        let data = try DiagnosticsExporter.encode(original)
        XCTAssertEqual(try schemaErrors(data), [])
        XCTAssertEqual(try JSONDecoder().decode(DiagnosticsSnapshot.self, from: data), original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let budget = try XCTUnwrap((object["frameTimings"] as? [String: Any])?["budget"] as? [String: Any])
        XCTAssertNil(budget["gpuEstimateMs"], "unavailable is an absent key")
        XCTAssertEqual(budget["flaggedPasses"] as? [String], ["composite cpu"])
        let text = DiagnosticsExporter.text(original)
        XCTAssertTrue(text.contains("Frame budget: 16.67 ms at 60 fps, limit 13.33 ms (80%)\n"), text)
        XCTAssertTrue(text.contains("  estimate: CPU 15.50 ms, GPU n/a\n"))
        XCTAssertTrue(text.contains("  over budget: composite cpu\n"))
    }

    func testTimingsWithoutBudgetHaveNoBudgetKey() throws {
        let data = try DiagnosticsExporter.encode(try snapshot(Self.timings))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil((object["frameTimings"] as? [String: Any])?["budget"])
        XCTAssertFalse(DiagnosticsExporter.text(try snapshot(Self.timings)).contains("Frame budget"))
    }

    func testBudgetDropsUnknownPassesAndInvalidValues() throws {
        let budget = DiagnosticsSnapshot.FrameTimings.Budget(
            framesPerSecond: .nan, deadlineMs: -1, thresholdShare: 0.8, clearShare: 0.7, thresholdMs: 13,
            cpuEstimateMs: .infinity, gpuEstimateMs: 2, flaggedPasses: ["bogus", "gpu frame"])
        XCTAssertEqual(budget.framesPerSecond, 0)
        XCTAssertEqual(budget.deadlineMs, 0)
        XCTAssertNil(budget.cpuEstimateMs)
        XCTAssertEqual(budget.flaggedPasses, ["gpu frame"])
        XCTAssertEqual(DiagnosticsSnapshot.FrameTimings.Budget.passNames.count, 13)
        var timings = Self.timings
        timings.budget = budget
        XCTAssertEqual(try schemaErrors(DiagnosticsExporter.encode(try snapshot(timings))), [])
    }

    // MARK: - PERF-003-T11: the effect quality level (optional)

    func testEffectQualityRoundTripsAndValidates() throws {
        var timings = Self.timings
        timings.effectQuality = .init(level: "reduced", reason: "thermal")
        let original = try snapshot(timings)
        let data = try DiagnosticsExporter.encode(original)
        XCTAssertEqual(try schemaErrors(data), [])
        XCTAssertEqual(try JSONDecoder().decode(DiagnosticsSnapshot.self, from: data), original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let quality = try XCTUnwrap((object["frameTimings"] as? [String: Any])?["effectQuality"] as? [String: Any])
        XCTAssertEqual(quality["level"] as? String, "reduced")
        XCTAssertEqual(quality["reason"] as? String, "thermal")
        XCTAssertTrue(DiagnosticsExporter.text(original).contains("Effect quality: reduced (thermal)\n"))
    }

    func testEffectQualityIsAbsentWhenUnknownAndSanitized() throws {
        let data = try DiagnosticsExporter.encode(try snapshot(Self.timings))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil((object["frameTimings"] as? [String: Any])?["effectQuality"])
        let odd = DiagnosticsSnapshot.FrameTimings.EffectQuality(level: "ultra", reason: "heat")
        XCTAssertEqual(odd.level, "full")
        XCTAssertNil(odd.reason)
        var timings = Self.timings
        timings.effectQuality = .init(level: "full")
        XCTAssertEqual(try schemaErrors(DiagnosticsExporter.encode(try snapshot(timings))), [])
    }
}
