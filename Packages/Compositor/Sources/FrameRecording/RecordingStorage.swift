// RecordingStorage.swift — REC-015 recording disk guard (spec specs/063-rec-015-recording-disk-guard,
// contracts/disk-guard.md, research REC-015-D1 to D5; ADR-0027 amendment).
//
// * `RecordingStorageEstimate`: bytes per second a recording writes, from the output size, the frame
//   rate and the highest average bit rate among the preferred codecs, plus 25% for encoder peaks and
//   the file index (integer math).
// * `RecordingStoragePolicy`: Record needs a 200 MiB reserve plus 60 s at that rate; while recording,
//   the recording stops when less than the reserve plus two 5 s check intervals at the larger of the
//   estimated and measured rates remains. An unknown free-space value never refuses or stops.
// * `StorageProbe`: the free bytes a recording can write into (tests inject values).
//   `VolumeStorageProbe` reads `volumeAvailableCapacityForImportantUsageKey` and `volumeAvailableCapacityKey`
//   (required-reason APIs, Disk space, declared with E174.1 in the app's privacy manifest) and uses the smaller
//   (`guardReading`; QA-011 device run 2026-11-19: on D3 the important-use figure stayed ~400 MB to 2.8 GB above the
//   real free space while 77 GB were written, so purgeable space was not freed and a guard on it alone would let the
//   reserve be all purgeable space); the values stay in memory.
// * `RecordingStorage.fileBytes`: the recording file's size (`fileSizeKey`; no file dates).
// * `RecordingWriterFault`: the test seam that makes the recorder's writer fail after N frames.
// Plain Swift + Foundation; builds on Linux (the volume probe is Apple-only).
import Foundation

/// Reads the free bytes available for important use on the volume that holds `directory`
/// (nil when unknown). Called off the frame loop.
public protocol StorageProbe: Sendable {
    func availableBytes(at directory: URL) -> Int64?
}

public enum VolumeStorageReading {
    /// The figure the disk guard uses (REC-015-D1, amended QA-011 2026-11-19): the smaller of the important-use
    /// capacity (counts purgeable space) and the real available capacity, so the 200 MiB reserve is space that is
    /// free now. Either alone when only one is known; nil when neither is (or a reading is negative).
    public static func guardBytes(important: Int64?, real: Int64?) -> Int64? {
        let known = [important, real].compactMap { $0 }.filter { $0 >= 0 }
        return known.min()
    }
}

#if canImport(Darwin)
/// The real probe: the smaller of `volumeAvailableCapacityForImportantUsage` and `volumeAvailableCapacity` of the
/// directory's volume (REC-015-D1, amended QA-011 2026-11-19).
public struct VolumeStorageProbe: StorageProbe {
    public init() {}

    public func availableBytes(at directory: URL) -> Int64? {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                             .volumeAvailableCapacityKey])
        return VolumeStorageReading.guardBytes(important: values?.volumeAvailableCapacityForImportantUsage,
                                               real: values?.volumeAvailableCapacity.map { Int64($0) })
    }
}
#endif

/// Bytes per second a recording is expected to write (REC-015-R2, research REC-015-D2).
public struct RecordingStorageEstimate: Sendable, Equatable {
    public let bytesPerSecond: Int64

    public init(bytesPerSecond: Int64) {
        self.bytesPerSecond = max(bytesPerSecond, 1)
    }

    /// The highest bit rate among `settings.codecPreference` at the output size (REC-005: the profile's rate), plus 25%, in bytes.
    public init(geometry: RecordingGeometry, settings: RecordingSettings) {
        let rates: [Int] = settings.codecPreference.map { (codec: RecordingCodec) -> Int in
            settings.averageBitRate(codec: codec, width: geometry.outputWidth, height: geometry.outputHeight)   // REC-005
        }
        let bitRate: Int64 = Int64(rates.max() ?? 1_000_000)
        let withHeadroom: Int64 = bitRate * Int64(125)
        self.init(bytesPerSecond: (withHeadroom + Int64(799)) / Int64(800))
    }
}

/// When Record may start and when a recording must stop (REC-015-R3, R5, R9).
public struct RecordingStoragePolicy: Sendable, Equatable {
    /// Never written into: room to finish the file and for the system (200 MiB).
    public static let reserveBytes: Int64 = 209_715_200
    /// Record needs room for at least this much video.
    public static let minimumStartSeconds: Int64 = 60
    /// Seconds between two free-space readings while recording.
    public static let checkIntervalSeconds: Int64 = 5
    /// The stop leaves this many check intervals of writing before the reserve.
    public static let horizonChecks: Int64 = 2

    public let estimate: RecordingStorageEstimate

    public init(estimate: RecordingStorageEstimate) {
        self.estimate = estimate
    }

    /// Reserve + 60 s at the estimated rate.
    public var bytesNeededToStart: Int64 {
        Self.reserveBytes + Self.minimumStartSeconds * estimate.bytesPerSecond
    }

    /// False only when the free space is known and below `bytesNeededToStart`.
    public func allowsStart(availableBytes: Int64?) -> Bool {
        guard let availableBytes else { return true }
        return availableBytes >= bytesNeededToStart
    }

    /// The file's measured rate, once at least one second is recorded (nil before).
    public func measuredBytesPerSecond(fileBytes: Int64?, recordedSeconds: Double) -> Int64? {
        guard let fileBytes, recordedSeconds >= 1 else { return nil }
        return Int64((Double(fileBytes) / recordedSeconds).rounded(.up))
    }

    /// The free space below which the recording stops.
    public func stopThreshold(fileBytes: Int64?, recordedSeconds: Double) -> Int64 {
        let measured: Int64 = measuredBytesPerSecond(fileBytes: fileBytes, recordedSeconds: recordedSeconds) ?? 0
        let rate: Int64 = max(estimate.bytesPerSecond, measured)
        let horizon: Int64 = Self.horizonChecks * Self.checkIntervalSeconds
        return Self.reserveBytes + horizon * rate
    }

    /// True when the free space is known and below `stopThreshold`.
    public func shouldStop(availableBytes: Int64?, fileBytes: Int64?, recordedSeconds: Double) -> Bool {
        guard let availableBytes else { return false }
        return availableBytes < stopThreshold(fileBytes: fileBytes, recordedSeconds: recordedSeconds)
    }
}

public enum RecordingStorage {
    /// The file's size in bytes (nil when it cannot be read). `fileSizeKey` only: no file dates.
    public static func fileBytes(at url: URL) -> Int64? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        return Int64(size)
    }
}

/// Test seam (REC-015-R12, REC-016-R2): makes the recorder's writer fail. Tests and DEBUG launch arguments only.
public struct RecordingWriterFault: Sendable {
    /// REC-016-R2: where the failure happens.
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        /// After `afterFrames` appended frames every append fails with `error`; the real writer stays healthy.
        case appendFails
        /// After `afterFrames` appended frames the real writer itself is driven to its failed state.
        case writerFails
        /// Appends succeed; at finish the real writer is driven to its failed state first.
        case finishFails
        /// The recorder fails to start after its writer was created.
        case startFails
    }

    public let kind: Kind
    public let afterFrames: Int
    public let error: NSError

    public init(afterFrames: Int, error: NSError, kind: Kind = .appendFails) {
        self.kind = kind
        self.afterFrames = max(afterFrames, 0)
        self.error = error
    }

    /// A generic (not out-of-space) writer error.
    public static let injectedError = NSError(domain: "AVFoundationErrorDomain", code: -11800,
                                              userInfo: ["NSLocalizedDescription": "The operation could not be completed"])

    /// REC-016: every append after `afterFrames` frames fails; the healthy writer can still finish.
    public static func appendFailure(afterFrames: Int) -> RecordingWriterFault {
        RecordingWriterFault(afterFrames: afterFrames, error: injectedError, kind: .appendFails)
    }

    /// REC-016: the real writer fails after `afterFrames` frames.
    public static func writerFailure(afterFrames: Int) -> RecordingWriterFault {
        RecordingWriterFault(afterFrames: afterFrames, error: injectedError, kind: .writerFails)
    }

    /// REC-016: the real writer fails when the recording is finished.
    public static let finishFailure = RecordingWriterFault(afterFrames: 0, error: injectedError, kind: .finishFails)

    /// REC-016: the recorder fails to start after its writer exists.
    public static let startFailure = RecordingWriterFault(afterFrames: 0, error: injectedError, kind: .startFails)

    /// DEBUG `-uitestWriterFault`: `append:<n>`, `writer:<n>`, `finish`, `start`, `diskFull:<n>`; nil otherwise.
    public init?(argument: String) {
        let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
        let count = parts.count > 1 ? Int(parts[1]) : nil
        switch (parts.first, count) {
        case ("append", let n?): self = .appendFailure(afterFrames: n)
        case ("writer", let n?): self = .writerFailure(afterFrames: n)
        case ("diskFull", let n?): self = .diskFull(afterFrames: n)
        case ("finish", nil): self = .finishFailure
        case ("start", nil): self = .startFailure
        default: return nil
        }
    }

    /// AVFoundation's "disk full" wrapping the POSIX "no space left on device", as the writer reports it.
    public static func diskFull(afterFrames: Int) -> RecordingWriterFault {
        let posix = NSError(domain: RecordingFailure.posixDomain, code: RecordingFailure.posixNoSpaceCode)
        let error = NSError(domain: RecordingFailure.avFoundationDomain, code: RecordingFailure.avFoundationDiskFullCode,
                            userInfo: [NSUnderlyingErrorKey: posix])
        return RecordingWriterFault(afterFrames: afterFrames, error: error)
    }
}
