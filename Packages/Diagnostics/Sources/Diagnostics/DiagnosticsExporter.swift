// DiagnosticsExporter.swift — tester-initiated export (task T031; FR-021, FR-061, R-13).
//
// Writes a schema-valid JSON file and a human-readable .txt into a temporary directory and
// returns their URLs for the system share sheet. Called only from a user action (the Export
// button). Nothing is sent anywhere by this code (FR-068).
import Foundation

public enum DiagnosticsExporter {
    /// `CaptureLab-<UTC yyyyMMdd-HHmmss>` — no device or user identifiers in the name (R-13).
    public static func baseName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "CaptureLab-\(formatter.string(from: date))"
    }

    public static func encode(_ snapshot: DiagnosticsSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    public static func text(_ s: DiagnosticsSnapshot) -> String {
        var lines = [
            "CaptureLab diagnostics (metadata only — no audio)",
            "Exported: \(s.exportedAt)",
            "Device: \(s.device.model), OS \(s.device.osVersion ?? "?") (\(s.device.osBuild))",
            "App build: \(s.app.build)",
            "Source mode: \(s.session.sourceMode)",
            "Final state: \(s.session.finalState)" + (s.session.stopReason.map { " (\($0))" } ?? ""),
            "Stop detail: \(s.session.stopDetail ?? "none")",
            "Audio arrived: \(s.session.audioArrived ? "yes" : "no")",
            "Non-silent audio verified: \(s.session.nonSilent ? "yes" : "no")",
            "Samples: \(s.session.sampleCount) over \(String(format: "%.1f", s.session.durationSeconds)) s",
        ]
        for f in s.session.formats {
            lines.append("Format at \(String(format: "%.2f", f.firstSeenSeconds)) s: \(Int(f.sampleRate)) Hz, \(f.channelCount) ch, \(f.sampleType)")
        }
        let t = s.session.timing
        lines.append("Start to first audio: \(t.startToFirstAudioMs.map { String(format: "%.0f ms", $0) } ?? "n/a")")
        lines.append(String(format: "Buffer cadence: mean %.1f ms, max %.1f ms; late buffers %d; dropped frames %d",
                            t.bufferCadenceMeanMs, t.bufferCadenceMaxMs, t.lateBuffers, t.droppedFrames))
        lines.append(String(format: "Levels: peak max %.1f dBFS, RMS mean %.1f dBFS",
                            s.session.levels.peakDBFSMax, s.session.levels.rmsDBFSMean))
        if let timings = s.frameTimings { lines.append(contentsOf: frameTimingLines(timings)) }
        if let note = s.testerNote { lines.append("Tester note: \(note)") }
        lines.append("")
        lines.append("A source counts as working only if 'Non-silent audio verified' is yes (FR-031).")
        return lines.joined(separator: "\n") + "\n"
    }

    /// PERF-001: "Frame stages over N frames (median/p95 ms):" and one line per stage; "n/a" when unavailable.
    static func frameTimingLines(_ t: DiagnosticsSnapshot.FrameTimings) -> [String] {
        func pair(_ median: Double?, _ p95: Double?) -> String {
            guard let median, let p95 else { return "n/a" }
            return String(format: "%.2f/%.2f", median, p95)
        }
        var lines: [String] = ["Frame stages over \(t.windowFrames) frames (median/p95 ms):"]
        for stage in t.stages {
            var line: String = "  \(stage.name): CPU \(pair(stage.cpuMedianMs, stage.cpuP95Ms))"
            if stage.gpuMedianMs != nil { line += ", GPU \(pair(stage.gpuMedianMs, stage.gpuP95Ms))" }
            lines.append(line)
        }
        lines.append("  frame GPU: \(pair(t.frameGPUMedianMs, t.frameGPUP95Ms))")
        if t.rejectedSamples > 0 { lines.append("  rejected samples: \(t.rejectedSamples)") }
        if let budget = t.budget { lines.append(contentsOf: budgetLines(budget)) }
        if let quality = t.effectQuality {   // PERF-003
            lines.append("Effect quality: " + quality.level + (quality.reason.map { (r: String) -> String in " (" + r + ")" } ?? ""))
        }
        return lines
    }

    /// PERF-002: "Frame budget: 16.67 ms at 60 fps, limit 13.33 ms (80%)", the estimates and the flagged passes.
    static func budgetLines(_ b: DiagnosticsSnapshot.FrameTimings.Budget) -> [String] {
        func value(_ ms: Double?) -> String { ms.map { (v: Double) -> String in String(format: "%.2f ms", v) } ?? "n/a" }
        let percent: Int = Int((b.thresholdShare * 100).rounded())
        let fps: Int = Int(b.framesPerSecond.rounded())
        var lines: [String] = [String(format: "Frame budget: %.2f ms at %d fps, limit %.2f ms (%d%%)", b.deadlineMs, fps, b.thresholdMs, percent)]
        lines.append("  estimate: CPU \(value(b.cpuEstimateMs)), GPU \(value(b.gpuEstimateMs))")
        let flagged: String = b.flaggedPasses.isEmpty ? "none" : b.flaggedPasses.joined(separator: ", ")
        lines.append("  over budget: " + flagged)
        return lines
    }

    /// Writes both files and returns [json, txt] URLs.
    public static func write(_ snapshot: DiagnosticsSnapshot, exportedAt date: Date = Date(),
                             directory: URL = FileManager.default.temporaryDirectory) throws -> [URL] {
        let base = baseName(for: date)
        let json = directory.appendingPathComponent("\(base).json")
        let txt = directory.appendingPathComponent("\(base).txt")
        try encode(snapshot).write(to: json, options: [.atomic])
        try Data(text(snapshot).utf8).write(to: txt, options: [.atomic])
        return [json, txt]
    }
}

/// Device and app metadata for exports. Deliberately excludes every identifier (FR-021).
public enum DiagnosticsEnvironment {
    /// Hardware model identifier (e.g. "iPhone17,1"); on the simulator, the simulated model.
    public static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// OS version and build parsed from `operatingSystemVersionString`, e.g. "Version 27.0 (Build 24A123)".
    public static func osVersionAndBuild() -> (version: String, build: String) {
        let info = ProcessInfo.processInfo
        let v = info.operatingSystemVersion
        let version = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        let s = info.operatingSystemVersionString
        if let range = s.range(of: "Build "), let end = s[range.upperBound...].firstIndex(of: ")") {
            return (version, String(s[range.upperBound..<end]))
        }
        return (version, "unknown")
    }

    public static func device() -> DiagnosticsSnapshot.Device {
        let os = osVersionAndBuild()
        return .init(model: modelIdentifier(), osVersion: os.version, osBuild: os.build)
    }

    public static func app(bundle: Bundle = .main, toolchain: String? = nil) -> DiagnosticsSnapshot.App {
        .init(version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
              toolchain: toolchain)
    }
}
