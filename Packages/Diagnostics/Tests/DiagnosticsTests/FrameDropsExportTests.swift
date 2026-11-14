// FrameDropsExportTests.swift — PERF-007-T10 (PERF-007-R11, S5; specs/192-perf-007-frame-drop-telemetry contract C3):
// the optional frame drop counts round-trip through the export, validate against the schema, keep unavailable counts
// as absent keys, and leave exports without them unchanged.
import AudioCore
@testable import Diagnostics
import Foundation
import XCTest

final class FrameDropsExportTests: XCTestCase {
    private func snapshot(_ drops: DiagnosticsSnapshot.FrameDrops?) throws -> DiagnosticsSnapshot {
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
        snap.frameDrops = drops
        return snap
    }

    private func schemaErrors(_ data: Data) throws -> [String] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "diagnostics-export.schema", withExtension: "json"))
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let json = try JSONSerialization.jsonObject(with: data)
        var errors: [String] = []
        MiniSchemaValidator.validate(json, against: schema, path: "$", errors: &errors)
        return errors
    }

    func testFrameDropsRoundTripValidateAndKeepUnavailableAbsent() throws {
        let drops = DiagnosticsSnapshot.FrameDrops(outputs: [
            .init(output: "device", submitted: 300, skipped: 2, stale: 1),                       // projectM: no presentation
            .init(output: "external", submitted: 120, skipped: 0, presented: 118, late: 3, discarded: 2),
            .init(output: "recording", skipped: 5, presented: 15),
        ])
        let original = try snapshot(drops)
        let data = try DiagnosticsExporter.encode(original)
        XCTAssertEqual(try schemaErrors(data), [])
        XCTAssertEqual(try JSONDecoder().decode(DiagnosticsSnapshot.self, from: data), original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let outputs = try XCTUnwrap((object["frameDrops"] as? [String: Any])?["outputs"] as? [[String: Any]])
        XCTAssertEqual(Set(outputs[0].keys), ["output", "submitted", "skipped", "stale"], "unavailable = absent, never 0")
        XCTAssertEqual(Set(outputs[2].keys), ["output", "skipped", "presented", "stale"])
    }

    func testExportWithoutFrameDropsHasNoKey() throws {
        let data = try DiagnosticsExporter.encode(try snapshot(nil))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["frameDrops"])
        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        XCTAssertEqual(try schemaErrors(data), [])
    }

    func testUnknownOutputsDuplicatesAndNegativeValuesAreDropped() throws {
        let drops = DiagnosticsSnapshot.FrameDrops(outputs: [
            .init(output: "bogus", submitted: 1),
            .init(output: "device", submitted: -4, late: -1, stale: -2),
            .init(output: "device", submitted: 9),
        ])
        XCTAssertEqual(drops.outputs, [.init(output: "device", submitted: 0, late: 0, stale: 0)])
        XCTAssertEqual(try schemaErrors(DiagnosticsExporter.encode(try snapshot(drops))), [])
    }
}
