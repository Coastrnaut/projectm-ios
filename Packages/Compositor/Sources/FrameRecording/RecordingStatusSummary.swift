// RecordingStatusSummary.swift — REC-009 recording status overlay (spec specs/190-rec-009-status-overlay,
// contracts/status-overlay.md, research REC-009-D2 to D4).
//
// * `RecordingStatusSummary`: what the overlay under the recording indicator shows while recording — the
//   live dropped slots (REC-006) with a warning from 10 drops and 2% of the slots, and the free storage
//   with the seconds until the REC-015 guard would stop (its own threshold and rate rule), with the levels
//   low (< 5 min) and critical (< 1 min). Unknown free storage has no level. Integer math.
// * `RecordingWarningThrottle`: which rising warnings are announced — per kind, only a level above the last
//   announced one, at most once per 30 s of recorded (media) time; a level that falls to none re-arms it.
// The values exist in memory only (REC-009-R7). Plain Swift; builds on Linux.
import Foundation

/// The storage line's level (REC-009-R3).
public enum RecordingStorageLevel: Int, Sendable, Equatable, Comparable {
    case ok = 0, low = 1, critical = 2

    public static func < (a: RecordingStorageLevel, b: RecordingStorageLevel) -> Bool { a.rawValue < b.rawValue }
}

public struct RecordingStatusSummary: Sendable, Equatable {
    /// A warning needs at least this many dropped slots…
    public static let droppedWarningMinimum = 10
    /// …and at least 1/50 (2%) of the recording's slots (written + dropped).
    public static let droppedWarningDivisor = 50
    /// Below this many seconds left the storage is low.
    public static let lowSeconds: Int64 = 300
    /// Below this many seconds left the storage is critical.
    public static let criticalSeconds: Int64 = 60

    public let droppedSlots: Int
    public let writtenFrames: Int
    /// The latest free-storage reading; nil when unknown.
    public let availableBytes: Int64?
    /// Seconds of recording until the disk guard stops (≥ 0); nil when the free storage is unknown.
    public let secondsLeft: Int64?

    public init(droppedSlots: Int, writtenFrames: Int, availableBytes: Int64?, secondsLeft: Int64?) {
        self.droppedSlots = max(droppedSlots, 0)
        self.writtenFrames = max(writtenFrames, 0)
        self.availableBytes = availableBytes
        self.secondsLeft = secondsLeft.map { (s: Int64) -> Int64 in max(s, 0) }
    }

    /// From the recorder's statistics and the guard's policy (REC-009-R2, R3, R8).
    public init(statistics: RecordingStatistics, policy: RecordingStoragePolicy?, availableBytes: Int64?,
                fileBytes: Int64?, recordedSeconds: Double) {
        let left: Int64? = policy.flatMap { (p: RecordingStoragePolicy) -> Int64? in
            Self.secondsLeft(policy: p, availableBytes: availableBytes, fileBytes: fileBytes, recordedSeconds: recordedSeconds)
        }
        self.init(droppedSlots: statistics.droppedSlots, writtenFrames: statistics.written,
                  availableBytes: availableBytes, secondsLeft: left)
    }

    /// (free − the guard's stop threshold) ÷ the larger of the estimated and measured rates, rounded down, ≥ 0.
    public static func secondsLeft(policy: RecordingStoragePolicy, availableBytes: Int64?, fileBytes: Int64?,
                                   recordedSeconds: Double) -> Int64? {
        guard let availableBytes else { return nil }
        let threshold: Int64 = policy.stopThreshold(fileBytes: fileBytes, recordedSeconds: recordedSeconds)
        let measured: Int64 = policy.measuredBytesPerSecond(fileBytes: fileBytes, recordedSeconds: recordedSeconds) ?? 0
        let rate: Int64 = max(policy.estimate.bytesPerSecond, measured, 1)
        let room: Int64 = availableBytes - threshold
        return room > 0 ? room / rate : 0
    }

    // MARK: - Dropped frames

    /// The dropped slots as a whole percentage of the recording's slots (rounded down).
    public var droppedPercent: Int {
        let slots: Int = writtenFrames + droppedSlots
        return slots > 0 ? droppedSlots * 100 / slots : 0
    }

    /// REC-009-D2: at least 10 drops and at least 2% of the slots.
    public var droppedWarning: Bool {
        droppedSlots >= Self.droppedWarningMinimum
            && droppedSlots * Self.droppedWarningDivisor >= writtenFrames + droppedSlots
    }

    /// "Dropped frames: 3" or, warned, "Dropping frames: 12 (3%)".
    public var droppedText: String {
        droppedWarning ? "Dropping frames: \(droppedSlots) (\(droppedPercent)%)" : "Dropped frames: \(droppedSlots)"
    }

    // MARK: - Storage

    /// nil when the free storage is unknown.
    public var storageLevel: RecordingStorageLevel? {
        guard let secondsLeft else { return nil }
        if secondsLeft < Self.criticalSeconds { return .critical }
        if secondsLeft < Self.lowSeconds { return .low }
        return .ok
    }

    /// "2.1 GB free, about 14 min left", "850 MB free, under 1 min left", "Free storage unknown".
    public var storageText: String {
        guard let availableBytes, let secondsLeft else { return "Free storage unknown" }
        return Self.bytesText(availableBytes) + " free, " + Self.timeLeftText(secondsLeft)
    }

    /// "about 14 min left" or "under 1 min left".
    public static func timeLeftText(_ seconds: Int64) -> String {
        seconds < 60 ? "under 1 min left" : "about \(seconds / 60) min left"
    }

    /// Decimal units like the system's storage screens: "2.1 GB" from 1 GB (one decimal, rounded down), else "850 MB".
    public static func bytesText(_ bytes: Int64) -> String {
        let value: Int64 = max(bytes, 0)
        if value >= 1_000_000_000 {
            let tenths: Int64 = value / 100_000_000
            return "\(tenths / 10).\(tenths % 10) GB"
        }
        return "\(value / 1_000_000) MB"
    }
}

/// The kinds of recording warnings that are announced (contract C2).
public enum RecordingWarningKind: String, Sendable, CaseIterable {
    case droppedFrames, storage
}

/// REC-009-R4, research D4: rising levels only, at most once per kind per `interval` seconds of recording.
public struct RecordingWarningThrottle: Sendable, Equatable {
    public static let interval: Double = 30

    private var announcedLevel: [RecordingWarningKind: Int] = [:]
    private var announcedAt: [RecordingWarningKind: Double] = [:]

    public init() {}

    /// `level` 0 is no warning. True when the warning should be announced now (and records it).
    public mutating func submit(_ kind: RecordingWarningKind, level: Int, at recordedSeconds: Double) -> Bool {
        let last: Int = announcedLevel[kind] ?? 0
        if level <= 0 {
            announcedLevel[kind] = 0   // re-armed; the 30 s gap still applies
            return false
        }
        guard level > last else { return false }
        if let at = announcedAt[kind], recordedSeconds - at < Self.interval { return false }
        announcedLevel[kind] = level
        announcedAt[kind] = recordedSeconds
        return true
    }
}
