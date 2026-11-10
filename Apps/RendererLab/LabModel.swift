// LabModel.swift — RendererLab's runs (ADR-0003 device measurements; tasks T072, T075, T078).
//
// Launch arguments, or the environment variables RL_BACKEND, RL_MODE, RL_DURATION, RL_PRESET_SECONDS
// (all optional; with a mode the run starts by itself, so devicectl can drive it):
//   -backend gles|angle      renderer under test (default gles)
//   -mode sweep|session|flashcost|loadsweep
//                            sweep: every upstream test preset and every starter preset, each
//                            loaded and rendered for 2 s; session: render for -duration seconds,
//                            changing starter preset every -presetSeconds; flashcost (ANGLE
//                            only, T104): GPU-synchronized frame times with Reduce flashing off
//                            and on, alternating, on each starter preset
//                            loadsweep (feature 002 T236): every preset of the library index
//                            (PresetIndex.json and PresetArchive.bin, exclusions ignored) loaded
//                            once, no render wait; the report lists the ids that failed, for
//                            Resources/PresetExclusions.txt. RL_SHARD (or -shard) i/n runs the
//                            i-th of n equal parts (1-based), e.g. 2/4
//   -duration 600            session length in seconds
//   -presetSeconds 20        session preset interval
// Results go to Documents/RendererLab-<backend>-<mode>-<timestamp>.json (UIFileSharingEnabled), with
// the device model and OS, the engine's library-loading log (RI-009: PROJECTM_GLRESOLVER_TRACE_LOGGING
// is set before the engine is created), per-preset results or per-second frame rates, and the
// thermal states seen.
import ANGLERendering
import AudioCore
import Foundation
import Observation
import PresetLibrary
import ProjectMBridge
import Rendering
import UIKit

@MainActor
@Observable
final class LabModel {
    enum Backend: String, CaseIterable, Codable { case gles, angle }
    enum Mode: String, Codable { case sweep, session, flashcost, loadsweep }

    struct Config: Codable {
        var backend: Backend = .gles
        var mode: Mode?
        var duration: Double = 600
        var presetSeconds: Double = 20
        /// loadsweep part (1-based index, count).
        var shard: (index: Int, count: Int) = (1, 1)

        private enum CodingKeys: String, CodingKey { case backend, mode, duration, presetSeconds }

        /// Environment variables RL_BACKEND, RL_MODE, RL_DURATION, RL_PRESET_SECONDS win over the
        /// -key value launch arguments (devicectl passes environment variables untouched, while it
        /// may take a launch argument such as -duration for one of its own options).
        static func fromLaunchArguments() -> Config {
            let defaults = UserDefaults.standard   // -key value launch arguments land here
            let env = ProcessInfo.processInfo.environment
            func value(_ key: String, _ envKey: String) -> String? { env[envKey] ?? defaults.string(forKey: key) }
            var config = Config()
            if let b = value("backend", "RL_BACKEND"), let backend = Backend(rawValue: b) { config.backend = backend }
            if let m = value("mode", "RL_MODE") { config.mode = Mode(rawValue: m) }
            if let d = value("duration", "RL_DURATION").flatMap(Double.init) { config.duration = max(10, d) }
            if let s = value("presetSeconds", "RL_PRESET_SECONDS").flatMap(Double.init) { config.presetSeconds = max(2, s) }
            if let parts = value("shard", "RL_SHARD")?.split(separator: "/").compactMap({ Int($0) }), parts.count == 2,
               parts[1] >= 1, (1...parts[1]).contains(parts[0]) {
                config.shard = (parts[0], parts[1])
            }
            return config
        }
    }

    struct PresetResult: Codable {
        var group: String           // "tests" (upstream) or "starter"
        var id: String
        var loaded: Bool
        var error: String?
        var loadMs: Double
        var framesPerSecond: Double
    }

    struct Report: Codable {
        var tool = "RendererLab"
        var backend: Backend
        var mode: Mode
        var device: String
        var systemVersion: String
        var appBuild: String
        var startedAt: Date
        var finishedAt: Date
        var engineLog: [String]
        var thermalStates: [String]
        var lowPowerMode: Bool
        var drawableScale: Double
        var viewPoints: [Double]
        var presets: [PresetResult]?
        var framesPerSecond: [Double]?
        var flashCost: [FlashCostResult]?
        var loadFailures: [String]?
        var summary: [String: Double]
    }

    /// Reduce-flashing cost on one preset (T104): median frame time with the post-pass off and on.
    struct FlashCostResult: Codable {
        var id: String
        var medianOffMs: Double
        var medianOnMs: Double
        var costMs: Double
    }

    var config = Config.fromLaunchArguments()
    var status = "Idle"
    var renderer: (any VisualizerRenderer)?
    var lastReportPath: String?
    var isRunning = false

    private var feeder: ReferenceAudioFeeder?
    private let engineLog = EngineLog()
    private var thermalStates: Set<String> = []

    init() {
        // RI-009 evidence: the engine logs every library its GL resolver tries to open.
        setenv("PROJECTM_GLRESOLVER_TRACE_LOGGING", "1", 1)
        let log = engineLog
        ProjectMEngine.setLogHandler({ message, level in log.append("[\(level)] \(message)") }, minimumLevel: 3)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// Creates the renderer for the configured backend and starts the reference audio.
    func prepare() {
        do {
            let renderer: any VisualizerRenderer
            switch config.backend {
            case .gles: renderer = try GLESRenderer.make()
            case .angle: renderer = try ANGLERenderer.make()
            }
            let feeder = try ReferenceAudioFeeder()
            renderer.attach(pcm: feeder.ring)
            feeder.start()
            self.feeder = feeder
            self.renderer = renderer
            status = "Ready: \(config.backend.rawValue)"
        } catch {
            status = "Renderer failed: \(error)"
        }
    }

    func runIfRequested() {
        guard let mode = config.mode, !isRunning else { return }
        Task { await run(mode) }
    }

    func run(_ mode: Mode) async {
        guard let renderer, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        thermalStates = [Self.thermalName()]
        let started = Date()
        // Let the view lay out and the display link settle.
        try? await Task.sleep(for: .seconds(2))
        var presets: [PresetResult]?
        var fps: [Double]?
        var flashCost: [FlashCostResult]?
        var loadFailures: [String]?
        var summary: [String: Double] = [:]
        switch mode {
        case .sweep:
            let results = await sweep(renderer)
            presets = results
            for group in ["tests", "starter"] {
                let g = results.filter { $0.group == group }
                summary["\(group)Total"] = Double(g.count)
                summary["\(group)Loaded"] = Double(g.filter(\.loaded).count)
                summary["\(group)LoadMsMax"] = g.map(\.loadMs).max() ?? 0
            }
        case .session:
            let windows = await session(renderer)
            fps = windows
            let sorted = windows.sorted()
            summary["windows"] = Double(windows.count)
            summary["fpsMean"] = windows.isEmpty ? 0 : windows.reduce(0, +) / Double(windows.count)
            summary["fpsMin"] = sorted.first ?? 0
            summary["fpsP5"] = sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count) * 0.05)]
            summary["fractionAtLeast55"] = windows.isEmpty ? 0 : Double(windows.filter { $0 >= 55 }.count) / Double(windows.count)
            summary["fractionAtLeast30"] = windows.isEmpty ? 0 : Double(windows.filter { $0 >= 30 }.count) / Double(windows.count)
        case .loadsweep:
            let (results, failed) = await loadSweep(renderer)
            presets = results.filter { !$0.loaded }
            loadFailures = failed
            let times = results.map(\.loadMs).sorted()
            summary["presets"] = Double(results.count)
            summary["failed"] = Double(failed.count)
            summary["shardIndex"] = Double(config.shard.index)
            summary["shardCount"] = Double(config.shard.count)
            summary["loadMsMedian"] = times.isEmpty ? 0 : times[times.count / 2]
            summary["loadMsMax"] = times.last ?? 0
        case .flashcost:
            guard let angle = renderer as? ANGLERenderer else {
                status = "flashcost needs -backend angle"
                return
            }
            let results = await measureFlashCost(angle)
            flashCost = results
            let costs = results.map(\.costMs).sorted()
            summary["presets"] = Double(results.count)
            summary["costMsMedian"] = costs.isEmpty ? 0 : costs[costs.count / 2]
            summary["costMsMax"] = costs.last ?? 0
            summary["surfaceWidth"] = Double(angle.currentSurfaceSizeForLab.width)
            summary["surfaceHeight"] = Double(angle.currentSurfaceSizeForLab.height)
        }
        let view = renderer.view
        let report = Report(backend: config.backend, mode: mode, device: Self.modelIdentifier(),
                            systemVersion: UIDevice.current.systemVersion,
                            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
                            startedAt: started, finishedAt: Date(), engineLog: engineLog.lines,
                            thermalStates: thermalStates.sorted(), lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                            drawableScale: view.contentScaleFactor,
                            viewPoints: [view.bounds.width, view.bounds.height],
                            presets: presets, framesPerSecond: fps, flashCost: flashCost,
                            loadFailures: loadFailures, summary: summary)
        save(report)
    }

    // MARK: - Runs

    private func sweep(_ renderer: any VisualizerRenderer) async -> [PresetResult] {
        var all: [(String, Preset)] = testPresets().map { ("tests", $0) }
        if let catalog = try? PresetRepository(presetsFolder: Self.resource("Presets")).load() {
            all += catalog.presets.map { ("starter", $0) }
        }
        var results: [PresetResult] = []
        for (index, item) in all.enumerated() {
            status = "Sweep \(index + 1)/\(all.count): \(item.1.name)"
            let start = Date()
            var failure: String?
            do { try await renderer.setPreset(item.1) } catch { failure = (error as NSError).localizedDescription }
            let loadMs = Date().timeIntervalSince(start) * 1000
            try? await Task.sleep(for: .seconds(2.2))   // two full 1 s frame-rate windows
            thermalStates.insert(Self.thermalName())
            results.append(PresetResult(group: item.0, id: item.1.id, loaded: failure == nil, error: failure,
                                        loadMs: loadMs, framesPerSecond: renderer.metrics.framesPerSecond))
        }
        status = "Sweep done: \(results.filter(\.loaded).count)/\(results.count) loaded"
        return results
    }

    /// Feature 002 T236: every indexed preset in this shard, loaded once without a render wait. Only
    /// failures are kept in the report (12,941 rows would be noise); the count and timings are in
    /// the summary.
    private func loadSweep(_ renderer: any VisualizerRenderer) async -> ([PresetResult], [String]) {
        guard let library = try? await PresetLibrary.load(from: .main),
              let resources = Bundle.main.resourceURL,
              let archive = try? PresetArchive(url: resources.appendingPathComponent("PresetArchive.bin"),
                                               packIds: library.archiveOrder) else {
            status = "loadsweep: PresetIndex.json or PresetArchive.bin missing (build phase)"
            return ([], [])
        }
        renderer.setTextureSearchPaths([resources.appendingPathComponent("PresetTextures")])
        let all = library.presets
        let size = (all.count + config.shard.count - 1) / config.shard.count
        let part = all.dropFirst((config.shard.index - 1) * size).prefix(size)
        var results: [PresetResult] = []
        var failed: [String] = []
        for (n, item) in part.enumerated() {
            if n % 25 == 0 { status = "Load sweep \(n + 1)/\(part.count) (shard \(config.shard.index)/\(config.shard.count))" }
            var preset = Preset(id: item.id, name: item.name, fileURL: resources.appendingPathComponent(item.path),
                                packID: item.source, author: item.author)
            let start = Date()
            var failure: String?
            do {
                if !item.isIncluded { preset.data = try archive.contents(of: item.id) }
                try await renderer.setPreset(preset)
            } catch {
                failure = (error as NSError).localizedDescription
                failed.append(item.id)
            }
            results.append(PresetResult(group: item.source, id: item.id, loaded: failure == nil, error: failure,
                                        loadMs: Date().timeIntervalSince(start) * 1000, framesPerSecond: 0))
            if n % 200 == 0 { thermalStates.insert(Self.thermalName()) }
            await Task.yield()
        }
        status = "Load sweep done: \(failed.count) of \(results.count) failed"
        return (results, failed)
    }

    private func session(_ renderer: any VisualizerRenderer) async -> [Double] {
        let presets = (try? PresetRepository(presetsFolder: Self.resource("Presets")).load().presets) ?? []
        var windows: [Double] = []
        var last = renderer.metrics
        let start = Date()
        var nextChange = start
        var index = 0
        while Date().timeIntervalSince(start) < config.duration {
            if Date() >= nextChange, !presets.isEmpty {
                try? await renderer.setPreset(presets[index % presets.count])
                index += 1
                nextChange = Date().addingTimeInterval(config.presetSeconds)
            }
            try? await Task.sleep(for: .milliseconds(250))
            let now = renderer.metrics
            if now != last, now.framesPerSecond > 0 {
                windows.append(now.framesPerSecond)
                last = now
            }
            thermalStates.insert(Self.thermalName())
            let elapsed = Int(Date().timeIntervalSince(start))
            status = "Session \(elapsed)/\(Int(config.duration)) s, \(String(format: "%.1f", now.framesPerSecond)) fps"
        }
        status = "Session done: \(windows.count) windows"
        return windows
    }

    /// Per starter preset: 30 warm-up frames, then 5 rounds of 40 frames off and 40 on.
    private func measureFlashCost(_ renderer: ANGLERenderer) async -> [FlashCostResult] {
        let presets = (try? PresetRepository(presetsFolder: Self.resource("Presets")).load().presets) ?? []
        renderer.pause()
        defer { renderer.resume() }
        var results: [FlashCostResult] = []
        for (index, preset) in presets.enumerated() {
            status = "Flash cost \(index + 1)/\(presets.count): \(preset.name)"
            guard (try? await renderer.setPreset(preset)) != nil else { continue }
            _ = renderer.timedFrames(30, reduceFlashing: false)
            var off: [Double] = [], on: [Double] = []
            for _ in 0..<5 {
                off += renderer.timedFrames(40, reduceFlashing: false)
                on += renderer.timedFrames(40, reduceFlashing: true)
                await Task.yield()
            }
            thermalStates.insert(Self.thermalName())
            let medianOff = Self.median(off), medianOn = Self.median(on)
            results.append(FlashCostResult(id: preset.id, medianOffMs: medianOff, medianOnMs: medianOn,
                                           costMs: medianOn - medianOff))
        }
        status = "Flash cost done: \(results.count) presets"
        return results
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    // MARK: - Helpers

    private func testPresets() -> [Preset] {
        let folder = Self.resource("tests")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return files.filter { $0.hasSuffix(".milk") }.sorted().map {
            Preset(id: "tests/\($0)", name: $0, fileURL: folder.appendingPathComponent($0))
        }
    }

    private func save(_ report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let stamp = ISO8601DateFormatter().string(from: report.startedAt).replacingOccurrences(of: ":", with: "")
        let name = "RendererLab-\(report.backend.rawValue)-\(report.mode.rawValue)-\(stamp).json"
        let url = URL.documentsDirectory.appendingPathComponent(name)
        do {
            try encoder.encode(report).write(to: url)
            lastReportPath = name
            status += " — saved \(name)"
        } catch {
            status += " — save failed: \(error)"
        }
    }

    static func resource(_ name: String) -> URL {
        Bundle.main.resourceURL!.appendingPathComponent(name)
    }

    static func thermalName() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    static func modelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

/// Thread-safe collector for engine log lines (the engine may log from any thread).
final class EngineLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ line: String) {
        lock.lock()
        if storage.count < 2_000 { storage.append(line) }
        lock.unlock()
    }
    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
