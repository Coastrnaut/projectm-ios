// ParameterSnapshot.swift — every manual value keyed by parameter ID (MOD-001-R9; research
// MOD-001-D7; contract C4).
//
// The hand-off to scene persistence (SCN-001/SCN-002 write it to disk; MOD-001 writes nothing) and
// the rollback mechanism: restoring an earlier snapshot undoes later changes. JSON form:
// {"schemaVersion": 1, "values": {"<id>": {"kind": …, "value": …}, …}} with sorted keys.
import Foundation

public struct ParameterSnapshot: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var values: [ParameterID: ParameterValue]

    public init(schemaVersion: Int = ParameterSnapshot.currentSchemaVersion, values: [ParameterID: ParameterValue]) {
        self.schemaVersion = schemaVersion
        self.values = values
    }

    /// Stable JSON bytes (sorted keys).
    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

/// One snapshot entry that was not applied, and why.
public struct ParameterRestoreRejection: Sendable, Hashable {
    public let id: ParameterID
    public let error: ParameterStoreError
}

/// What `ParameterStore.restore(_:)` did. Lists are in ID order.
public struct ParameterRestoreReport: Sendable, Hashable {
    /// Entries stored (after clamping).
    public var applied: [ParameterID] = []
    /// Entries whose ID is not registered (MOD-013 flags these as orphaned references).
    public var orphaned: [ParameterID] = []
    /// Entries of the wrong kind or with an invalid value.
    public var rejected: [ParameterRestoreRejection] = []
    /// The snapshot's schema is newer than this build understands; nothing was applied.
    public var unsupportedVersion = false
}

extension ParameterStore {
    /// Every current value, read atomically.
    public func snapshot() -> ParameterSnapshot { ParameterSnapshot(values: allValues()) }

    /// Applies each entry like `set(_:for:)`, in ID order, and reports what happened. A snapshot
    /// with a newer schema version is rejected whole. Parameters missing from the snapshot keep
    /// their current values.
    @discardableResult
    public func restore(_ snapshot: ParameterSnapshot) -> ParameterRestoreReport {
        var report = ParameterRestoreReport()
        guard snapshot.schemaVersion <= ParameterSnapshot.currentSchemaVersion else {
            report.unsupportedVersion = true
            return report
        }
        for (id, value) in snapshot.values.sorted(by: { $0.key < $1.key }) {
            guard registry.contains(id) else {
                report.orphaned.append(id)
                continue
            }
            do {
                try set(value, for: id)
                report.applied.append(id)
            } catch {
                report.rejected.append(ParameterRestoreRejection(id: id, error: error))
            }
        }
        return report
    }
}
