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
