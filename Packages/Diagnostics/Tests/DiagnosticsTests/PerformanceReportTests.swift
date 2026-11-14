// PerformanceReportTests.swift — PERF-012-T07 (specs/209-perf-012-performance-report): the performance report
// validates against contracts/performance-report.schema.json (copied into Resources; scripts/test_scripts.py keeps
// the copy equal), declares schema version 1, keeps unavailable values absent, sanitises every string, and names its
// file without identifiers.
@testable import Diagnostics
import Foundation
import XCTest

final class PerformanceReportTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15T08:00:00Z

    private func schemaErrors(_ data: Data) throws -> [String] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "performance-report.schema", withExtension: "json"))
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let json = try JSONSerialization.jsonObject(with: data)
        var errors: [String] = []
        MiniSchemaValidator.validate(json, against: schema, path: "$", errors: &errors)
        return errors
    }

    private func state(_ at: Double, thermal: String = "nominal", profile: String = "standard") -> PerformanceReport.StateSample {
        PerformanceReport.StateSample(atSeconds: at, thermal: thermal, lowPower: false, profile: profile,
                                      maxFramesPerSecond: 60, renderScale: 1)
    }

    private func report(frames: PerformanceReport.Frames, model: String = "iPhone15,4",
                        visual: String = "projectM") -> PerformanceReport {
        let timings = DiagnosticsSnapshot.FrameTimings(
            windowFrames: 120, rejectedSamples: 0, frameGPUMedianMs: 4.1, frameGPUP95Ms: 6.2,
            stages: [.init(name: "render", samples: 120, cpuMedianMs: 3.0, cpuP95Ms: 5.0)])
        let drops = DiagnosticsSnapshot.FrameDrops(outputs: [.init(output: "device", submitted: 600, skipped: 3, stale: 0)])
        return PerformanceReport(
            exportedAt: date,
            device: .init(model: model, osVersion: "27.0.1", osBuild: "24A1"),
            app: .init(version: "1.1", build: "2", toolchain: "Xcode 27.2"),
            session: .init(durationSeconds: 75.5, visual: visual, overlayShown: true),
            frames: frames, frameDrops: drops, frameTimings: timings,
            states: .init(current: state(70, thermal: "fair", profile: "batterySaver"),
                          timeline: [state(0), state(70, thermal: "fair", profile: "batterySaver")], truncated: false),
            resources: .init(texturePool: .init(pools: 1, liveTextures: 4, liveBytes: 33_177_600, retiredTextures: 1,
                                                retiredBytes: 8_294_400, hits: 10, misses: 4, evictions: 0, purges: 0),
                             memory: .init(footprintBytes: 210_000_000, peakFootprintBytes: 260_000_000,
                                           availableBytes: 1_900_000_000)))
    }

    private var fullFrames: PerformanceReport.Frames {
        PerformanceReport.Frames(sampleCount: 600, measuredSeconds: 10.2, resolutionMs: 0.1, p50Ms: 16.7, p90Ms: 16.8,
                                 p95Ms: 17.0, p99Ms: 33.4, maxMs: 50.2,
                                 longFrames: [.init(thresholdMs: 25, count: 6), .init(thresholdMs: 50, count: 1),
                                              .init(thresholdMs: 100, count: 0)])
    }

    func testFullReportValidatesAndDeclaresVersionOne() throws {
        let data: Data = try DiagnosticsExporter.encode(report(frames: fullFrames))
        XCTAssertEqual(try schemaErrors(data), [])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(PerformanceReport.currentSchemaVersion, 1)
        XCTAssertEqual(object["kind"] as? String, "projectM-iOS.performanceReport")
        XCTAssertEqual(object["exportedAt"] as? String, "2027-01-15T08:00:00Z")
        XCTAssertNil((object["app"] as? [String: Any])?["toolchain"], "the report's app section has no toolchain")
        let decoded = try JSONDecoder().decode(PerformanceReport.self, from: data)
        XCTAssertEqual(decoded, report(frames: fullFrames))
    }

    /// PERF-013-R9: the optional audioSync section validates when present, is absent without samples, and the
    /// drift estimate is reported only while drift is detected.
    func testAudioSyncSectionValidatesAndIsAbsentWithoutSamples() throws {
        var full = report(frames: fullFrames)
        full.audioSync = PerformanceReport.AudioSync(sampleCount: 240, p50Ms: 24.1, p95Ms: 31.0, maxMs: 44.2, driftDetected: true,
                                                     driftPpm: -512.3, detections: 1)
        let data: Data = try DiagnosticsExporter.encode(full)
        XCTAssertEqual(try schemaErrors(data), [])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let section = try XCTUnwrap(object["audioSync"] as? [String: Any])
        XCTAssertEqual(section["driftPpm"] as? Double, -512.3)
        XCTAssertEqual(try JSONDecoder().decode(PerformanceReport.self, from: data), full)
        XCTAssertNil(PerformanceReport.AudioSync(sampleCount: 0, p50Ms: nil, p95Ms: nil, maxMs: nil, driftDetected: false,
                                                 driftPpm: nil, detections: 0))
        let quiet = try XCTUnwrap(PerformanceReport.AudioSync(sampleCount: 5, p50Ms: 20, p95Ms: 21, maxMs: 22, driftDetected: false,
                                                              driftPpm: 12, detections: 0))
        XCTAssertNil(quiet.driftPpm, "no estimate without a verdict")
        let plain = try JSONSerialization.jsonObject(with: DiagnosticsExporter.encode(report(frames: fullFrames))) as? [String: Any]
        XCTAssertNil(plain?["audioSync"], "absent, never empty")
    }

    /// PERF-012 US2: no frame measured → sampleCount 0 and no percentile keys (absent, never 0); still valid.
    func testNoFramesLeavesPercentilesAbsent() throws {
        let frames = PerformanceReport.Frames(sampleCount: 0, measuredSeconds: 0, resolutionMs: 0.1, p50Ms: 0, maxMs: 0)
        let data: Data = try DiagnosticsExporter.encode(report(frames: frames))
        XCTAssertEqual(try schemaErrors(data), [])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let section = try XCTUnwrap(object["frames"] as? [String: Any])
        XCTAssertEqual(section["sampleCount"] as? Int, 0)
        for key in ["p50Ms", "p90Ms", "p95Ms", "p99Ms", "maxMs"] { XCTAssertNil(section[key], key) }
    }

    /// Unknown fixed-set values become "unknown"; system strings lose every character outside the allowed set.
    func testSanitising() throws {
        let r = report(frames: fullFrames, model: "Ada's iPhone/../Users\u{0}x", visual: "Holiday.jpg")
        XCTAssertEqual(r.session.visual, "unknown")
        XCTAssertEqual(r.device.model, "Adas iPhone..Usersx")
        XCTAssertEqual(state(0, thermal: "hot", profile: "My Scene").thermal, "unknown")
        XCTAssertEqual(state(0, thermal: "hot", profile: "My Scene").profile, "unknown")
        XCTAssertEqual(PerformanceReport.systemString(String(repeating: "a", count: 99))?.count, 40)
        XCTAssertNil(PerformanceReport.systemString("/// "))
        XCTAssertEqual(try schemaErrors(DiagnosticsExporter.encode(r)), [])
    }

    func testTimelineIsCappedAndMarkedTruncated() throws {
        let many: [PerformanceReport.StateSample] = (0..<250).map { (i: Int) -> PerformanceReport.StateSample in state(Double(i)) }
        let states = PerformanceReport.States(current: state(250), timeline: many, truncated: false)
        XCTAssertEqual(states.timeline.count, 200)
        XCTAssertTrue(states.truncated)
    }

    func testFileNameAndSignpostSummary() {
        XCTAssertEqual(DiagnosticsExporter.performanceReportName(for: date), "projectM-performance-20270115-080000.json")
        XCTAssertEqual(report(frames: fullFrames).signpostSummary, "samples 600 states 2")   // PERF-012-R10: counts only
    }
}
