// DocumentSchema.swift — the versioned constraints of one JSON document type, declared once next to
// its format (FILE-007-R5; contract C2). A reader takes its structural limits and its version policy
// from here: the shape is checked first (`validate`), then the version (`verdict`). Semantic checks
// (records, ids, counts) stay in each reader after decoding.
import Foundation

public struct DocumentSchema: Sendable, Equatable {
    /// The format name (an archive manifest's `format`, or a registry name for a local file).
    public let name: String
    /// Versions below this are refused; between this and `currentVersion` they are migrated.
    public let oldestReadableVersion: Int
    public let currentVersion: Int
    public let limits: JSONLimits

    public enum VersionVerdict: Sendable, Equatable {
        case current
        /// Readable through migration steps.
        case older
        /// Written by a newer app: refused with "update the app", nothing interpreted.
        case newer
        /// Below the oldest readable version.
        case unsupported
    }

    public init(name: String, oldestReadableVersion: Int, currentVersion: Int, limits: JSONLimits) {
        precondition(oldestReadableVersion <= currentVersion, "oldest readable version after the current one")
        self.name = name
        self.oldestReadableVersion = oldestReadableVersion
        self.currentVersion = currentVersion
        self.limits = limits
    }

    public func verdict(for version: Int) -> VersionVerdict {
        if version == currentVersion { return .current }
        if version > currentVersion { return .newer }
        return version >= oldestReadableVersion ? .older : .unsupported
    }

    /// The structural check (FILE-007-R1 to R4) with this schema's limits.
    @discardableResult
    public func validate(_ data: Data) throws(JSONShapeError) -> JSONShapeSummary {
        try BoundedJSON.validate(data, limits: limits)
    }

    /// The same schema with its byte limit lowered to `maxBytes` (an archive's own manifest limit).
    public func capped(atBytes maxBytes: Int) -> DocumentSchema {
        var limits = self.limits
        limits.maxBytes = min(limits.maxBytes, maxBytes)
        return DocumentSchema(name: name, oldestReadableVersion: oldestReadableVersion, currentVersion: currentVersion, limits: limits)
    }
}
