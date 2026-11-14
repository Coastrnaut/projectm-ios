// PerformanceReport.swift — PERF-012 (specs/209-perf-012-performance-report; contracts/performance-report.schema.json,
// schema version 1): the user-initiated performance report, an extension of the diagnostics export.
//
// Privacy by construction (PERF-012-R9, research PERF-012-D4): the type has no free-text field. Every string is
// either a member of a fixed set (unknown values become "unknown", or the entry is dropped) or sanitised system
// metadata (hardware model, OS version and build, app version and build: only `[A-Za-z0-9 .,_()-]`, at most 40
// characters). No media, file name, path, preset, scene, text overlay or recording name, OSC address, audio,
// identifier or user-entered text can be represented. Reuses `DiagnosticsSnapshot.FrameTimings` (PERF-001/002/003)
// and `FrameDrops` (PERF-007) unchanged. Property names mirror the schema (additionalProperties: false).
import Foundation

public struct PerformanceReport: Codable, Sendable, Equatable {
    public static let currentSchemaVersion: Int = 1
    public static let kindValue: String = "projectM-iOS.performanceReport"
    public static let maxTimelineEntries: Int = 200
    public static let maxSystemStringLength: Int = 40
    public static let visualKinds: [String] = ["projectM", "native", "camera", "photo", "video", "text", "none", "unknown"]

    public var schemaVersion: Int = PerformanceReport.currentSchemaVersion
    public var kind: String = PerformanceReport.kindValue
    public var exportedAt: String
    public var device: Device
    public var app: App
    public var session: Session
    public var frames: Frames
    public var frameDrops: DiagnosticsSnapshot.FrameDrops?
    public var frameTimings: DiagnosticsSnapshot.FrameTimings?
    public var states: States
    public var resources: Resources

    public init(exportedAt: Date, device: DiagnosticsSnapshot.Device, app: DiagnosticsSnapshot.App, session: Session,
                frames: Frames, frameDrops: DiagnosticsSnapshot.FrameDrops? = nil,
                frameTimings: DiagnosticsSnapshot.FrameTimings? = nil, states: States, resources: Resources) {
        self.exportedAt = Self.timestamp(exportedAt)
        self.device = Device(model: Self.systemString(device.model) ?? "unknown",
                             osVersion: device.osVersion.flatMap(Self.systemString),
                             osBuild: Self.systemString(device.osBuild) ?? "unknown")
        self.app = App(version: app.version.flatMap(Self.systemString), build: Self.systemString(app.build) ?? "unknown")
        self.session = session
        self.frames = frames
        self.frameDrops = frameDrops
        self.frameTimings = frameTimings
        self.states = states
        self.resources = resources
    }

    // MARK: - Sections

    public struct Device: Codable, Sendable, Equatable {
        public var model: String
        public var osVersion: String?
        public var osBuild: String
    }

    public struct App: Codable, Sendable, Equatable {
        public var version: String?
        public var build: String
    }

    public struct Session: Codable, Sendable, Equatable {
        public var durationSeconds: Double
        /// One of `visualKinds`.
        public var visual: String
        public var overlayShown: Bool

        public init(durationSeconds: Double, visual: String, overlayShown: Bool) {
            self.durationSeconds = PerformanceReport.nonNegative(durationSeconds)
            self.visual = PerformanceReport.visualKinds.contains(visual) ? visual : "unknown"
            self.overlayShown = overlayShown
        }
    }

    /// Frame-to-frame intervals (PERF-012-R5). Unavailable percentiles are absent keys.
    public struct Frames: Codable, Sendable, Equatable {
        public var sampleCount: Int
        public var measuredSeconds: Double
        public var resolutionMs: Double
        public var p50Ms: Double?
        public var p90Ms: Double?
        public var p95Ms: Double?
        public var p99Ms: Double?
        public var maxMs: Double?
        public var longFrames: [LongFrames]

        public struct LongFrames: Codable, Sendable, Equatable {
            public var thresholdMs: Double
            public var count: Int

            public init(thresholdMs: Double, count: Int) {
                self.thresholdMs = thresholdMs
                self.count = max(0, count)
            }
        }

        public init(sampleCount: Int, measuredSeconds: Double, resolutionMs: Double, p50Ms: Double? = nil,
                    p90Ms: Double? = nil, p95Ms: Double? = nil, p99Ms: Double? = nil, maxMs: Double? = nil,
                    longFrames: [LongFrames] = []) {
            let available: Bool = sampleCount > 0
            self.sampleCount = max(0, sampleCount)
            self.measuredSeconds = PerformanceReport.nonNegative(measuredSeconds)
            self.resolutionMs = resolutionMs
            self.p50Ms = available ? p50Ms : nil
            self.p90Ms = available ? p90Ms : nil
            self.p95Ms = available ? p95Ms : nil
            self.p99Ms = available ? p99Ms : nil
            self.maxMs = available ? maxMs : nil
            self.longFrames = Array(longFrames.prefix(3))
        }
    }

    /// Thermal, Low Power, profile and render budget (PERF-012-R7).
    public struct StateSample: Codable, Sendable, Equatable {
        public static let thermalStates: [String] = ["nominal", "fair", "serious", "critical", "unknown"]
        public static let profiles: [String] = ["standard", "followLowPowerMode", "batterySaver", "unknown"]

        public var atSeconds: Double
        public var thermal: String
        public var lowPower: Bool
        public var profile: String
        public var maxFramesPerSecond: Int
        public var renderScale: Double

        public init(atSeconds: Double, thermal: String, lowPower: Bool, profile: String, maxFramesPerSecond: Int,
                    renderScale: Double) {
            self.atSeconds = PerformanceReport.nonNegative(atSeconds)
            self.thermal = Self.thermalStates.contains(thermal) ? thermal : "unknown"
            self.lowPower = lowPower
            self.profile = Self.profiles.contains(profile) ? profile : "unknown"
            self.maxFramesPerSecond = max(0, maxFramesPerSecond)
            self.renderScale = min(max(renderScale.isFinite ? renderScale : 0, 0), 1)
        }

        /// Same state, ignoring the time.
        public func sameState(as other: StateSample) -> Bool {
            thermal == other.thermal && lowPower == other.lowPower && profile == other.profile
                && maxFramesPerSecond == other.maxFramesPerSecond && renderScale == other.renderScale
        }
    }

    public struct States: Codable, Sendable, Equatable {
        public var current: StateSample
        public var timeline: [StateSample]
        public var truncated: Bool

        public init(current: StateSample, timeline: [StateSample], truncated: Bool) {
            self.current = current
            self.timeline = Array(timeline.prefix(PerformanceReport.maxTimelineEntries))
            self.truncated = truncated || timeline.count > PerformanceReport.maxTimelineEntries
        }
    }

    public struct Resources: Codable, Sendable, Equatable {
        public var texturePool: TexturePool?
        public var memory: Memory

        public init(texturePool: TexturePool? = nil, memory: Memory) {
            self.texturePool = texturePool
            self.memory = memory
        }

        /// PERF-004 counters summed over the app's pools.
        public struct TexturePool: Codable, Sendable, Equatable {
            public var pools: Int
            public var liveTextures: Int
            public var liveBytes: Int
            public var retiredTextures: Int
            public var retiredBytes: Int
            public var hits: Int
            public var misses: Int
            public var evictions: Int
            public var purges: Int

            public init(pools: Int, liveTextures: Int, liveBytes: Int, retiredTextures: Int, retiredBytes: Int, hits: Int,
                        misses: Int, evictions: Int, purges: Int) {
                self.pools = max(0, pools)
                self.liveTextures = max(0, liveTextures)
                self.liveBytes = max(0, liveBytes)
                self.retiredTextures = max(0, retiredTextures)
                self.retiredBytes = max(0, retiredBytes)
                self.hits = max(0, hits)
                self.misses = max(0, misses)
                self.evictions = max(0, evictions)
                self.purges = max(0, purges)
            }
        }

        /// Bytes; an unavailable value is absent.
        public struct Memory: Codable, Sendable, Equatable {
            public var footprintBytes: Int?
            public var peakFootprintBytes: Int?
            public var availableBytes: Int?

            public init(footprintBytes: Int? = nil, peakFootprintBytes: Int? = nil, availableBytes: Int? = nil) {
                self.footprintBytes = footprintBytes.map { (v: Int) -> Int in max(0, v) }
                self.peakFootprintBytes = peakFootprintBytes.map { (v: Int) -> Int in max(0, v) }
                self.availableBytes = availableBytes.map { (v: Int) -> Int in max(0, v) }
            }
        }
    }

    // MARK: - Sanitising

    /// System metadata keeps only `[A-Za-z0-9 .,_()-]`, at most 40 characters; nil when nothing is left.
    public static func systemString(_ raw: String) -> String? {
        let allowed: Set<Character> = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,_()-")
        let kept: String = String(raw.filter { (c: Character) -> Bool in allowed.contains(c) }.prefix(maxSystemStringLength))
        let trimmed: String = kept.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// ISO 8601 UTC with seconds, e.g. "2026-11-14T15:30:00Z".
    public static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }

    static func nonNegative(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 0
    }

    /// The signpost summary (PERF-012-R10): counts only.
    public var signpostSummary: String {
        "samples \(frames.sampleCount) states \(states.timeline.count)"
    }
}
