// DiagnosticsSnapshot.swift — metadata-only export model (task T030; FR-020–FR-022;
// contracts/diagnostics-export.schema.json, schemaVersion 2: version 2 added session.stopDetail,
// owner ruling 2026-11-08).
//
// Property names mirror the schema exactly (the schema sets additionalProperties: false).
// Never contains audio samples, device identifiers (serial, vendor or advertising IDs), or
// account information (FR-021, FR-061).
import AudioCore
import Foundation

public struct DiagnosticsSnapshot: Codable, Sendable, Equatable {
    public static let maxNoteLength = 500
    /// Longest `session.stopDetail` kept (the schema's maxLength); longer details are cut.
    public static let maxStopDetailLength = 300

    public var schemaVersion: Int = 2
    public var exportedAt: String
    public var testerNote: String?
    public var device: Device
    public var app: App
    public var session: Session
    /// PERF-001: per-stage frame timings (the visualizer's automation runs); nil in CaptureLab, which has no
    /// frame loop. Optional and additive: schema version 2 is unchanged and the key is absent when nil.
    public var frameTimings: FrameTimings? = nil

    /// PERF-001-R10 (specs/152-perf-001-stage-timings, data-model.md): medians and nearest-rank 95th
    /// percentiles in milliseconds; an unavailable value is an absent key, never 0.
    public struct FrameTimings: Codable, Sendable, Equatable {
        public static let stageNames: [String] = ["audio", "render", "composite", "output", "encode", "present"]

        public var windowFrames: Int
        public var rejectedSamples: Int
        public var frameGPUMedianMs: Double?
        public var frameGPUP95Ms: Double?
        public var stages: [Stage]
        /// PERF-002 (specs/160-perf-002-gpu-budget): the budget verdict for the same window; absent when not judged.
        public var budget: Budget? = nil

        /// PERF-002-R9: the frame deadline, the threshold and clear shares, the estimates and the flagged passes.
        public struct Budget: Codable, Sendable, Equatable {
            /// Every pass label the meter can flag (6 stages × cpu/gpu, then the whole frame's GPU time).
            public static let passNames: [String] = FrameTimings.stageNames.flatMap { (name: String) -> [String] in
                [name + " cpu", name + " gpu"]
            } + ["gpu frame"]

            public var framesPerSecond: Double
            public var deadlineMs: Double
            public var thresholdShare: Double
            public var clearShare: Double
            public var thresholdMs: Double
            public var cpuEstimateMs: Double?
            public var gpuEstimateMs: Double?
            /// Over-budget pass labels, frame order (at most 13).
            public var flaggedPasses: [String]

            /// Keeps known pass names (at most 13) and only finite, non-negative values (others become absent or 0).
            public init(framesPerSecond: Double, deadlineMs: Double, thresholdShare: Double, clearShare: Double,
                        thresholdMs: Double, cpuEstimateMs: Double? = nil, gpuEstimateMs: Double? = nil, flaggedPasses: [String]) {
                self.framesPerSecond = FrameTimings.clean(framesPerSecond) ?? 0
                self.deadlineMs = FrameTimings.clean(deadlineMs) ?? 0
                self.thresholdShare = FrameTimings.clean(thresholdShare) ?? 0
                self.clearShare = FrameTimings.clean(clearShare) ?? 0
                self.thresholdMs = FrameTimings.clean(thresholdMs) ?? 0
                self.cpuEstimateMs = FrameTimings.clean(cpuEstimateMs)
                self.gpuEstimateMs = FrameTimings.clean(gpuEstimateMs)
                self.flaggedPasses = Array(flaggedPasses.filter { (name: String) -> Bool in Self.passNames.contains(name) }.prefix(13))
            }
        }

        public struct Stage: Codable, Sendable, Equatable {
            /// One of `stageNames`.
            public var name: String
            /// CPU samples in the window.
            public var samples: Int
            public var cpuMedianMs: Double?
            public var cpuP95Ms: Double?
            public var gpuMedianMs: Double?
            public var gpuP95Ms: Double?

            public init(name: String, samples: Int, cpuMedianMs: Double? = nil, cpuP95Ms: Double? = nil,
                        gpuMedianMs: Double? = nil, gpuP95Ms: Double? = nil) {
                self.name = name
                self.samples = samples
                self.cpuMedianMs = cpuMedianMs
                self.cpuP95Ms = cpuP95Ms
                self.gpuMedianMs = gpuMedianMs
                self.gpuP95Ms = gpuP95Ms
            }
        }

        /// Keeps known stage names (at most 6) and only finite, non-negative values (others become absent).
        public init(windowFrames: Int, rejectedSamples: Int, frameGPUMedianMs: Double? = nil, frameGPUP95Ms: Double? = nil,
                    stages: [Stage], budget: Budget? = nil) {
            self.budget = budget
            self.windowFrames = max(0, windowFrames)
            self.rejectedSamples = max(0, rejectedSamples)
            self.frameGPUMedianMs = Self.clean(frameGPUMedianMs)
            self.frameGPUP95Ms = Self.clean(frameGPUP95Ms)
            self.stages = stages.filter { (stage: Stage) -> Bool in Self.stageNames.contains(stage.name) }.prefix(6).map {
                (stage: Stage) -> Stage in
                Stage(name: stage.name, samples: max(0, stage.samples), cpuMedianMs: Self.clean(stage.cpuMedianMs),
                      cpuP95Ms: Self.clean(stage.cpuP95Ms), gpuMedianMs: Self.clean(stage.gpuMedianMs),
                      gpuP95Ms: Self.clean(stage.gpuP95Ms))
            }
        }

        static func clean(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0 else { return nil }
            return value
        }
    }

    public struct Device: Codable, Sendable, Equatable {
        /// Hardware model identifier, e.g. "iPhone17,1".
        public var model: String
        public var osVersion: String?
        public var osBuild: String
    }

    public struct App: Codable, Sendable, Equatable {
        public var version: String?
        public var build: String
        public var toolchain: String?
    }

    public struct Session: Codable, Sendable, Equatable {
        public var sourceMode: String
        public var finalState: String
        public var stopReason: String?
        /// Detail of the stop or failure, e.g. "… (SCStreamError -3824)"; nil when none.
        public var stopDetail: String?
        public var audioArrived: Bool
        public var nonSilent: Bool
        public var sampleCount: Int
        public var durationSeconds: Double
        public var formats: [Format]
        public var timing: Timing
        public var levels: Levels
        public var stateTransitions: [Transition]
        public var lifecycleEvents: [Lifecycle]
    }

    public struct Format: Codable, Sendable, Equatable {
        public var sampleRate: Double
        public var channelCount: Int
        public var sampleType: String
        public var firstSeenSeconds: Double
    }

    public struct Timing: Codable, Sendable, Equatable {
        public var startToFirstAudioMs: Double?
        public var bufferCadenceMeanMs: Double
        public var bufferCadenceMaxMs: Double
        public var droppedFrames: Int
        public var lateBuffers: Int
    }

    public struct Levels: Codable, Sendable, Equatable {
        public var peakDBFSMax: Double
        public var rmsDBFSMean: Double
    }

    public struct Transition: Codable, Sendable, Equatable {
        public var atSeconds: Double
        public var state: String
        public var reason: String?
    }

    public struct Lifecycle: Codable, Sendable, Equatable {
        public var atSeconds: Double
        public var event: String
    }
}

/// Plain inputs for building a snapshot; the app fills this from CaptureManager.
public struct DiagnosticsInput: Sendable {
    public var sourceMode: AudioSourceMode
    public var finalState: AudioState
    public var stopReason: StopReason?
    public var stopDetail: String?
    public var hasVerifiedActiveAudio: Bool
    public var statistics: PCMSinkStatistics
    public var durationSeconds: Double
    public var formats: [(format: AudioFormat, firstSeenSeconds: Double)]
    public var peakDBFSMax: Float
    public var rmsDBFSMean: Float
    public var transitions: [StateTransition]
    public var lifecycle: [(atSeconds: Double, event: String)]

    public init(sourceMode: AudioSourceMode, finalState: AudioState, stopReason: StopReason?,
                hasVerifiedActiveAudio: Bool, statistics: PCMSinkStatistics, durationSeconds: Double,
                formats: [(format: AudioFormat, firstSeenSeconds: Double)], peakDBFSMax: Float,
                rmsDBFSMean: Float, transitions: [StateTransition], lifecycle: [(atSeconds: Double, event: String)],
                stopDetail: String? = nil) {
        self.sourceMode = sourceMode
        self.finalState = finalState
        self.stopReason = stopReason
        self.stopDetail = stopDetail
        self.hasVerifiedActiveAudio = hasVerifiedActiveAudio
        self.statistics = statistics
        self.durationSeconds = durationSeconds
        self.formats = formats
        self.peakDBFSMax = peakDBFSMax
        self.rmsDBFSMean = rmsDBFSMean
        self.transitions = transitions
        self.lifecycle = lifecycle
    }
}

/// Schema enum for lifecycle events.
public let diagnosticsLifecycleEvents: Set<String> = [
    "background", "foreground", "lock", "unlock", "interruptionBegan", "interruptionEnded",
    "routeChange", "streamStopped", "formatChange",
]

extension DiagnosticsSnapshot {
    public enum BuildError: Error, Equatable {
        case noteTooLong
    }

    /// Builds a schema-valid snapshot. `note` is the tester's optional free text (≤ 500 chars).
    public static func build(from input: DiagnosticsInput, note: String?, device: Device, app: App,
                             exportedAt: Date = Date()) throws -> DiagnosticsSnapshot {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, trimmed.count > maxNoteLength { throw BuildError.noteTooLong }
        let stats = input.statistics
        let channels = max(1, stats.format?.channelCount ?? 1)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return DiagnosticsSnapshot(
            exportedAt: formatter.string(from: exportedAt),
            testerNote: (trimmed?.isEmpty ?? true) ? nil : trimmed,
            device: device,
            app: app,
            session: Session(
                sourceMode: input.sourceMode.rawValue,
                finalState: input.finalState.rawValue,
                stopReason: input.stopReason?.code,
                // Cut by Unicode scalars: JSON Schema's maxLength counts code points, not characters.
                stopDetail: input.stopDetail.map { String(String.UnicodeScalarView($0.unicodeScalars.prefix(maxStopDetailLength))) },
                audioArrived: stats.sampleCount > 0,
                nonSilent: input.hasVerifiedActiveAudio,
                sampleCount: stats.sampleCount,
                durationSeconds: max(0, input.durationSeconds),
                formats: input.formats.prefix(100).map {
                    Format(sampleRate: $0.format.sampleRate, channelCount: $0.format.channelCount,
                           sampleType: $0.format.sampleType.rawValue, firstSeenSeconds: max(0, $0.firstSeenSeconds))
                },
                timing: Timing(startToFirstAudioMs: stats.startToFirstAudioMs,
                               bufferCadenceMeanMs: max(0, stats.cadenceMeanMs),
                               bufferCadenceMaxMs: max(0, stats.cadenceMaxMs),
                               droppedFrames: stats.droppedSamples / channels,
                               lateBuffers: stats.lateBuffers),
                levels: Levels(peakDBFSMax: Double(min(0, input.peakDBFSMax)),
                               rmsDBFSMean: Double(min(0, input.rmsDBFSMean))),
                stateTransitions: input.transitions.prefix(1000).map {
                    Transition(atSeconds: max(0, $0.atSeconds), state: $0.state.rawValue, reason: $0.reason)
                },
                lifecycleEvents: input.lifecycle.filter { diagnosticsLifecycleEvents.contains($0.event) }
                    .prefix(1000).map { Lifecycle(atSeconds: max(0, $0.atSeconds), event: $0.event) }
            )
        )
    }
}
