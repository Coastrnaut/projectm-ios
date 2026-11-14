// RecordingRecovery.swift — REC-016 interruption recovery (specs/226-rec-016-recording-interruption-recovery,
// contracts/interruption-recovery.md, ADR-0061): what a writer failure leaves, and the thermal guard. Plain Swift;
// builds on Linux.

/// What the writer kept after a failure (REC-016-R3, contract C1.2).
public enum RecordingSalvageOutcome: String, Sendable, Equatable {
    /// The writer was still healthy and was finished at the last appended frame.
    case finished
    /// The writer failed; the file holds its completed movie fragments.
    case partial
    /// Nothing usable: the file was deleted.
    case nothing
}

/// The device's thermal state as the recording sees it (`ProcessInfo.ThermalState` in the app).
public enum RecordingThermalLevel: Int, Sendable, Comparable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical

    public static func < (lhs: RecordingThermalLevel, rhs: RecordingThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What the thermal guard asks the coordinator to do.
public enum RecordingThermalAction: Sendable, Equatable {
    case none
    /// Show the hot-device warning (once per recording).
    case warn
    /// Stop the recording (`RecordingStopReason.thermal`).
    case stop
}

/// REC-016-R8: warns once per recording at Serious, stops at Critical. One value per recording.
public struct RecordingThermalGuard: Sendable, Equatable {
    public private(set) var warned = false

    public init() {}

    public mutating func update(_ level: RecordingThermalLevel) -> RecordingThermalAction {
        if level >= .critical { return .stop }
        if level >= .serious, !warned {
            warned = true
            return .warn
        }
        return .none
    }

    /// Record is refused at this level and above.
    public static let refusalLevel = RecordingThermalLevel.critical

    /// The warning shown at Serious (row X13, system).
    public static let warningNotice = "The device is getting hot. Recording stops if it gets hotter."
}
