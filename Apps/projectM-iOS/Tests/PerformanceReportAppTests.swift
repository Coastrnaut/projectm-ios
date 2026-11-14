// PerformanceReportAppTests.swift — PERF-012-T13, T15 (specs/209-perf-012-performance-report; roadmap acceptance
// "Export omits personal media and includes versioned schema"):
//
// * A session seeded with personal media — a photo, a text overlay message, a user preset, a named scene, a recording
//   and an approved OSC peer — is exported through the app's own gathering path
//   (`AppCoordinator.gatherPerformanceReportInputs`, the Export button's path). The JSON contains none of the seeded
//   strings, file names or paths; every string in it is a schema enum/const value, the export time or system
//   metadata; `schemaVersion` is 1 and the JSON validates against contracts/performance-report.schema.json.
// * Frames are driven with injected display-link times (no wall clock); the state recorder uses an injected clock.
// * US2: without any measured frame the percentiles are absent and the file still validates.
import Compositor
import Diagnostics
import FrameRecording
import FrameTiming
import Rendering
import XCTest
@testable import projectM_iOS

/// A visual that only holds what it was given (as in FrameDropAppTests).
@MainActor
private final class SeededVisual: FrameDropCounted {
    var frameDrops: FrameDropCounter?
    let measuresPresentation = false
}

/// The personal media of the seeded session.
private struct PersonalMedia {
    static let photoName = "Grandma Ada Birthday 2026.jpg"
    static let textMessage = "Happy birthday Ada Lovelace, love from Charles"
    static let userPresetName = "Ada Secret Preset.milk"
    static let sceneName = "Lovelace Wedding Set"
    static let recordingName = "Ada-Wedding-Recording-2026.mov"
    static let oscPeer = "192.168.77.42"

    let folder: URL
    var photo: URL { folder.appendingPathComponent(Self.photoName) }
    var userPreset: URL { folder.appendingPathComponent(Self.userPresetName) }
    var scene: URL { folder.appendingPathComponent(Self.sceneName + ".projectmscene") }
    var recording: URL { folder.appendingPathComponent(Self.recordingName) }

    /// Every string that must not appear in the report.
    var forbidden: [String] {
        [Self.photoName, Self.textMessage, Self.userPresetName, Self.sceneName, Self.recordingName, Self.oscPeer,
         "Grandma", "Lovelace", "Ada", "Wedding", folder.path, folder.lastPathComponent, NSHomeDirectory(),
         NSTemporaryDirectory(), "file://", "/Users/", "/var/", "/private/"]
    }
}

@MainActor
final class PerformanceReportAppTests: XCTestCase {
    private var media: PersonalMedia!
    private var defaults: UserDefaults!
    private var suiteName = ""

    /// A fresh folder and preferences suite for the seeded session (made in the test, not in a nonisolated setUp).
    private func beginSession() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PERF012-Ada-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        media = PersonalMedia(folder: folder)
        suiteName = "PERF012.PerformanceReportAppTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
    }

    private func endSession() {
        try? FileManager.default.removeItem(at: media.folder)
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// Writes the personal media where the app keeps such things: files with personal names, the text overlay's
    /// message and the approved OSC peer in the (test) preferences.
    private func seedPersonalMedia() throws {
        try Data([0xFF, 0xD8, 0xFF]).write(to: media.photo)
        try Data("per_frame_1=wave_r=1;".utf8).write(to: media.userPreset)
        try Data("{\"name\":\"\(PersonalMedia.sceneName)\"}".utf8).write(to: media.scene)
        try Data([0, 0, 0, 0x18]).write(to: media.recording)
        let texts = TextOverlayCoordinator.makeDefault(defaults: defaults)
        texts.setMessage(PersonalMedia.textMessage)
        defaults.set([PersonalMedia.oscPeer], forKey: OSCPeersCoordinator.approvedKey)
        defaults.set(PersonalMedia.sceneName, forKey: "PERF012.seeded.sceneName")
        defaults.set(media.userPreset.path, forKey: "PERF012.seeded.userPreset")
    }

    /// 120 frames at 60 Hz with two missed slots, while the overlay counts the "photo" visual.
    private func driveFrames(_ attachment: FrameDropAttachment) throws {
        let visual = SeededVisual()
        attachment.sync(overlayShown: true, target: visual, external: false)
        let counter: FrameDropCounter = try XCTUnwrap(visual.frameDrops)
        let period: Double = 1.0 / 60
        var slot: Int = 0
        for frame in 0..<120 {
            slot += (frame == 40 || frame == 80) ? 2 : 1
            let timestamp: Double = 1_000 + Double(slot) * period
            _ = counter.submit(counter.session, timestamp: timestamp, targetTimestamp: timestamp + period)
        }
    }

    private func recorder(clock: UptimeClock) -> PerformanceStateRecorder {
        PerformanceStateRecorder(uptime: { () -> TimeInterval in clock.now }, read: { () -> PerformanceStateReading in clock.reading },
                                 observes: false)
    }

    private func export(attachment: FrameDropAttachment, recorder: PerformanceStateRecorder, overlayShown: Bool,
                        recording: (statistics: RecordingStatistics, live: Bool)?) throws -> Data {
        let inputs: PerformanceReportInputs = AppCoordinator.gatherPerformanceReportInputs(
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000), recorder: recorder, frameDrops: attachment,
            frameStages: FrameStageAttachment(), recording: recording, visual: .photo, overlayShown: overlayShown,
            pools: [TexturePoolCounters()], footprint: 200_000_000, available: 1_500_000_000)
        return try DiagnosticsExporter.encode(PerformanceReportBuilder.build(inputs))
    }

    // MARK: - Acceptance

    func testExportOmitsPersonalMediaAndIncludesVersionedSchema() throws {
        try beginSession()
        defer { endSession() }
        try seedPersonalMedia()
        let clock = UptimeClock()
        let states: PerformanceStateRecorder = recorder(clock: clock)
        clock.now += 30
        clock.reading.profile = .batterySaver
        clock.reading.settings = QualitySettings(maxFramesPerSecond: 30, renderScale: 0.75)
        states.sample()
        let attachment = FrameDropAttachment()
        try driveFrames(attachment)
        var statistics = RecordingStatistics()
        statistics.written = 118
        statistics.droppedSlots = 2
        let data: Data = try export(attachment: attachment, recorder: states, overlayShown: true, recording: (statistics, true))
        let text: String = try XCTUnwrap(String(data: data, encoding: .utf8))

        for personal in media.forbidden {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(personal), "the report contains \(personal)")
        }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(try schemaErrors(object), [])
        try assertEveryStringIsAllowed(object)

        let report = try JSONDecoder().decode(PerformanceReport.self, from: data)
        XCTAssertEqual(report.schemaVersion, PerformanceReport.currentSchemaVersion)
        XCTAssertEqual(report.session.visual, "photo")
        XCTAssertEqual(report.session.durationSeconds, 30, accuracy: 1e-9)
        XCTAssertEqual(report.frames.sampleCount, 119)
        XCTAssertEqual(try XCTUnwrap(report.frames.p50Ms), 1_000.0 / 60, accuracy: 0.11)
        XCTAssertEqual(try XCTUnwrap(report.frames.maxMs), 2_000.0 / 60, accuracy: 1e-6)
        XCTAssertEqual(report.frames.longFrames.first?.count, 2)   // the two missed slots (33.3 ms ≥ 25 ms)
        XCTAssertEqual(report.frameDrops?.outputs.map(\.output), ["device", "recording"])
        XCTAssertEqual(report.frameDrops?.outputs.first?.skipped, 2)
        XCTAssertEqual(report.states.timeline.map(\.profile), ["standard", "batterySaver"])
        XCTAssertEqual(report.states.current.renderScale, 0.75)
        XCTAssertEqual(report.resources.texturePool?.pools, 1)
        XCTAssertEqual(report.resources.memory.footprintBytes, 200_000_000)
    }

    /// PERF-012 US2: nothing measured → no percentile keys, still valid.
    func testReportWithoutFramesIsValid() throws {
        let data: Data = try export(attachment: FrameDropAttachment(), recorder: recorder(clock: UptimeClock()),
                                    overlayShown: false, recording: nil)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(try schemaErrors(object), [])
        let frames = try XCTUnwrap(object["frames"] as? [String: Any])
        XCTAssertEqual(frames["sampleCount"] as? Int, 0)
        for key in ["p50Ms", "p90Ms", "p95Ms", "p99Ms", "maxMs"] { XCTAssertNil(frames[key], key) }
        XCTAssertNil(object["frameDrops"], "no counting session while the overlay is off")
    }

    /// The timeline appends only changes and stops at 200 entries (truncated); the peak footprint keeps the maximum.
    func testStateRecorderTimeline() {
        let clock = UptimeClock()
        let states: PerformanceStateRecorder = recorder(clock: clock)
        states.sample()   // unchanged: no entry
        XCTAssertEqual(states.timeline.count, 1)
        for i in 0..<250 {
            clock.now += 1
            clock.reading.lowPower = i % 2 == 0
            states.sample()
        }
        XCTAssertEqual(states.timeline.count, PerformanceReport.maxTimelineEntries)
        XCTAssertTrue(states.truncated)
        states.sampleMemory(footprint: 300)
        states.sampleMemory(footprint: 100)
        XCTAssertEqual(states.peakFootprintBytes, 300)
    }

    // MARK: - Helpers

    private func schemaErrors(_ object: [String: Any]) throws -> [String] {
        let bundle = Bundle(for: PerformanceReportAppTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "performance-report.schema", withExtension: "json"))
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var errors: [String] = []
        ContractSchema.validate(object, against: schema, path: "$", errors: &errors)
        return errors
    }

    /// PERF-012 contract C4: every string is a schema enum/const value, the export time, or system metadata.
    private func assertEveryStringIsAllowed(_ object: [String: Any]) throws {
        let device = try XCTUnwrap(object["device"] as? [String: Any])
        let app = try XCTUnwrap(object["app"] as? [String: Any])
        var allowed: Set<String> = ["projectM-iOS.performanceReport", "2027-01-15T08:00:00Z"]
        for value in Array(device.values) + Array(app.values) { if let s = value as? String { allowed.insert(s) } }
        allowed.formUnion(PerformanceReport.visualKinds + PerformanceReport.StateSample.thermalStates
            + PerformanceReport.StateSample.profiles + DiagnosticsSnapshot.FrameDrops.outputNames
            + DiagnosticsSnapshot.FrameTimings.stageNames)
        var found: [String] = []
        ContractSchema.strings(in: object, into: &found)
        for value in found { XCTAssertTrue(allowed.contains(value), "unexpected string in the report: \(value)") }
        XCTAssertFalse(found.isEmpty)
    }
}

/// An injected uptime clock and state reading.
@MainActor
private final class UptimeClock {
    var now: TimeInterval = 5_000
    var reading = PerformanceStateReading(thermal: .nominal, lowPower: false, profile: .standard, settings: .full)
}

/// The JSON Schema subset the contract uses (the Diagnostics package's MiniSchemaValidator, which this target cannot
/// import): const, enum, type, required, properties, additionalProperties: false, items, minimum, maximum,
/// exclusiveMinimum, maxLength, maxItems.
private enum ContractSchema {
    static func validate(_ value: Any, against schema: [String: Any], path: String, errors: inout [String]) {
        if let c = schema["const"], !equal(value, c) { errors.append(path + ": const mismatch") }
        if let e = schema["enum"] as? [Any], !e.contains(where: { (candidate: Any) -> Bool in equal(value, candidate) }) {
            errors.append(path + ": not in enum")
        }
        if let t = schema["type"] as? String, !matches(value, t) { errors.append(path + ": expected " + t) }
        if let n = value as? NSNumber, !isBool(value) {
            if let min = schema["minimum"] as? Double, n.doubleValue < min { errors.append(path + ": < minimum") }
            if let max = schema["maximum"] as? Double, n.doubleValue > max { errors.append(path + ": > maximum") }
            if let ex = schema["exclusiveMinimum"] as? Double, n.doubleValue <= ex { errors.append(path + ": ≤ exclusiveMinimum") }
        }
        if let s = value as? String, let maxLen = schema["maxLength"] as? Int, s.count > maxLen { errors.append(path + ": too long") }
        if let obj = value as? [String: Any] {
            for key in schema["required"] as? [String] ?? [] where obj[key] == nil { errors.append(path + "." + key + ": required") }
            let props = schema["properties"] as? [String: Any] ?? [:]
            if (schema["additionalProperties"] as? Bool) == false {
                for key in obj.keys where props[key] == nil { errors.append(path + "." + key + ": additional property") }
            }
            for (key, sub) in props {
                if let v = obj[key], let subSchema = sub as? [String: Any] { validate(v, against: subSchema, path: path + "." + key, errors: &errors) }
            }
        }
        if let arr = value as? [Any] {
            if let maxItems = schema["maxItems"] as? Int, arr.count > maxItems { errors.append(path + ": too many items") }
            if let items = schema["items"] as? [String: Any] {
                for (i, v) in arr.enumerated() { validate(v, against: items, path: path + "[" + String(i) + "]", errors: &errors) }
            }
        }
    }

    static func strings(in value: Any, into found: inout [String]) {
        if let s = value as? String { found.append(s) }
        if let obj = value as? [String: Any] { for v in obj.values { strings(in: v, into: &found) } }
        if let arr = value as? [Any] { for v in arr { strings(in: v, into: &found) } }
    }

    private static func matches(_ v: Any, _ type: String) -> Bool {
        switch type {
        case "object": return v is [String: Any]
        case "array": return v is [Any]
        case "string": return v is String
        case "boolean": return isBool(v)
        case "integer":
            guard let n = v as? NSNumber, !isBool(v) else { return false }
            return n.doubleValue == n.doubleValue.rounded()
        case "number": return v is NSNumber && !isBool(v)
        default: return false
        }
    }

    private static func isBool(_ v: Any) -> Bool {
        guard let n = v as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    private static func equal(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? String, let y = b as? String { return x == y }
        if let x = a as? NSNumber, let y = b as? NSNumber, isBool(a) == isBool(b) { return x == y }
        return false
    }
}
