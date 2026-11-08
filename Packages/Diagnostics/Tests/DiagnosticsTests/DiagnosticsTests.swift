// Task T022: export validates against the schema; no identifiers; note limit; filename; timing.
import XCTest
import Foundation
import AudioCore
@testable import Diagnostics

final class DiagnosticsTests: XCTestCase {
    private func input(sampleCount: Int = 48_000, verified: Bool = true) -> DiagnosticsInput {
        let format = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: true, sampleType: .float32)
        return DiagnosticsInput(
            sourceMode: .inAppPlayback, finalState: .active, stopReason: nil,
            hasVerifiedActiveAudio: verified,
            statistics: PCMSinkStatistics(sampleCount: sampleCount, bufferCount: 100, firstSampleSeconds: 0.05,
                                          lastSampleSeconds: 1.05, cadenceMeanMs: 10.7, cadenceMaxMs: 23,
                                          droppedSamples: 64, lateBuffers: 1, format: format,
                                          formatChangeCount: 0, startToFirstAudioMs: 50),
            durationSeconds: 1.1,
            formats: [(format, 0.05)], peakDBFSMax: -6, rmsDBFSMean: -12,
            transitions: [StateTransition(atSeconds: 0, state: .waiting), StateTransition(atSeconds: 0.3, state: .active)],
            lifecycle: [(0.5, "background"), (0.6, "notAnEvent")])
    }

    private let device = DiagnosticsSnapshot.Device(model: "iPhone17,1", osVersion: "27.0.0", osBuild: "24A1")
    private let app = DiagnosticsSnapshot.App(version: "0.1", build: "1", toolchain: nil)

    private func snapshot(note: String? = "Safari video") throws -> DiagnosticsSnapshot {
        try DiagnosticsSnapshot.build(from: input(), note: note, device: device, app: app,
                                      exportedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testExportValidatesAgainstSchema() throws {
        let data = try DiagnosticsExporter.encode(try snapshot())
        let json = try JSONSerialization.jsonObject(with: data)
        let url = try XCTUnwrap(Bundle.module.url(forResource: "diagnostics-export.schema", withExtension: "json"))
        let schema = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        var errors: [String] = []
        MiniSchemaValidator.validate(json, against: schema as! [String: Any], path: "$", errors: &errors)
        XCTAssertEqual(errors, [])
    }

    func testNoIdentifiersInExport() throws {
        let text = String(decoding: try DiagnosticsExporter.encode(try snapshot()), as: UTF8.self)
        for forbidden in ["identifierForVendor", "advertisingIdentifier", "serial", "udid", "UDID", "IDFA", "IDFV"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
    }

    func testNoteLimit() {
        XCTAssertThrowsError(try snapshot(note: String(repeating: "a", count: 501)))
        XCTAssertNoThrow(try snapshot(note: String(repeating: "a", count: 500)))
        XCTAssertNil(try snapshot(note: "   ").testerNote)
    }

    func testFilenamePattern() {
        let name = DiagnosticsExporter.baseName(for: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(name, "CaptureLab-20270115-080000")
        XCTAssertNotNil(name.range(of: #"^CaptureLab-\d{8}-\d{6}$"#, options: .regularExpression))
    }

    func testWriteProducesJsonAndText() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try DiagnosticsExporter.write(try snapshot(), exportedAt: Date(timeIntervalSince1970: 0), directory: dir)
        XCTAssertEqual(urls.map(\.pathExtension), ["json", "txt"])
        let text = try String(contentsOf: urls[1], encoding: .utf8)
        XCTAssertTrue(text.contains("Non-silent audio verified: yes"))
    }

    func testDerivedFields() throws {
        let s = try snapshot()
        XCTAssertTrue(s.session.audioArrived)
        XCTAssertTrue(s.session.nonSilent)
        XCTAssertEqual(s.session.timing.droppedFrames, 32, "samples ÷ channels")
        XCTAssertEqual(s.session.lifecycleEvents.map(\.event), ["background"], "unknown events dropped")
        XCTAssertEqual(s.session.timing.startToFirstAudioMs, 50)
    }

    func testNoSamplesMeansNotArrived() throws {
        let s = try DiagnosticsSnapshot.build(from: input(sampleCount: 0, verified: false), note: nil, device: device, app: app)
        XCTAssertFalse(s.session.audioArrived)
        XCTAssertFalse(s.session.nonSilent)
    }
}

/// Validates the subset of JSON Schema used by diagnostics-export.schema.json:
/// type (incl. arrays of types), const, enum, required, properties, additionalProperties:false,
/// items, minimum, maximum, exclusiveMinimum, maxLength, maxItems.
enum MiniSchemaValidator {
    static func validate(_ value: Any, against schema: [String: Any], path: String, errors: inout [String]) {
        if let c = schema["const"], !equal(value, c) { errors.append("\(path): const mismatch") }
        if let e = schema["enum"] as? [Any], !e.contains(where: { equal(value, $0) }) { errors.append("\(path): not in enum") }
        if let t = schema["type"] {
            let types = (t as? [String]) ?? [t as! String]
            if !types.contains(where: { matches(value, $0) }) { errors.append("\(path): expected \(types)") }
        }
        if let n = value as? NSNumber, !(value is Bool) {
            if let min = schema["minimum"] as? Double, n.doubleValue < min { errors.append("\(path): < minimum") }
            if let max = schema["maximum"] as? Double, n.doubleValue > max { errors.append("\(path): > maximum") }
            if let ex = schema["exclusiveMinimum"] as? Double, n.doubleValue <= ex { errors.append("\(path): ≤ exclusiveMinimum") }
        }
        if let s = value as? String, let maxLen = schema["maxLength"] as? Int, s.count > maxLen { errors.append("\(path): too long") }
        if let obj = value as? [String: Any] {
            for key in schema["required"] as? [String] ?? [] where obj[key] == nil { errors.append("\(path).\(key): required") }
            let props = schema["properties"] as? [String: Any] ?? [:]
            if (schema["additionalProperties"] as? Bool) == false {
                for key in obj.keys where props[key] == nil { errors.append("\(path).\(key): additional property") }
            }
            for (key, sub) in props {
                if let v = obj[key], let subSchema = sub as? [String: Any] {
                    validate(v, against: subSchema, path: "\(path).\(key)", errors: &errors)
                }
            }
        }
        if let arr = value as? [Any] {
            if let maxItems = schema["maxItems"] as? Int, arr.count > maxItems { errors.append("\(path): too many items") }
            if let items = schema["items"] as? [String: Any] {
                for (i, v) in arr.enumerated() { validate(v, against: items, path: "\(path)[\(i)]", errors: &errors) }
            }
        }
    }

    private static func matches(_ v: Any, _ type: String) -> Bool {
        switch type {
        case "object": return v is [String: Any]
        case "array": return v is [Any]
        case "string": return v is String
        case "boolean": return isBool(v)
        case "integer": if let n = v as? NSNumber, !isBool(v) { return n.doubleValue == n.doubleValue.rounded() }; return false
        case "number": return v is NSNumber && !isBool(v)
        case "null": return v is NSNull
        default: return false
        }
    }

    private static func isBool(_ v: Any) -> Bool {
        guard let n = v as? NSNumber else { return false }
        #if canImport(Darwin)
        return CFGetTypeID(n) == CFBooleanGetTypeID()
        #else
        // swift-corelibs-foundation encodes Bool-backed NSNumbers with the "c" type encoding.
        return String(cString: n.objCType) == "c"
        #endif
    }

    private static func equal(_ a: Any, _ b: Any) -> Bool {
        (a as? NSObject)?.isEqual(b) ?? false
    }
}
