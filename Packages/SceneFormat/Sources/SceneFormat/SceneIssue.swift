// SceneIssue.swift — decode refusals and validation issues (SCN-001-R8, R9, R11; contract C4, C5).

/// Why bytes were not read as a scene at all (nothing is returned).
public enum SceneDecodeError: Error, Sendable, Hashable, CustomStringConvertible {
    case empty
    case tooLarge(bytes: Int, limit: Int)
    case notJSON(offset: Int, reason: String)
    case nestingTooDeep(limit: Int)
    case duplicateKey(path: String, key: String)
    case notAScene
    case newerVersion(Int64)
    case invalidVersion(String)
    case tooMany(what: String, count: Int, limit: Int)
    case malformed(path: String, reason: String)
    /// SCN-013: an older version the migration chain cannot bring to the current version.
    case migrationFailed(fromVersion: Int64, step: String?, path: String, reason: String)

    public var message: String {
        switch self {
        case .empty:
            "The file is empty."
        case let .tooLarge(bytes, limit):
            "The scene is \(bytes) bytes; scenes are at most \(limit) bytes."
        case let .notJSON(offset, reason):
            "The scene is not valid JSON at byte \(offset): \(reason)."
        case let .nestingTooDeep(limit):
            "The scene nests deeper than \(limit) levels."
        case let .duplicateKey(path, key):
            "\(path) has the key \"\(key)\" twice."
        case .notAScene:
            "The file is not a projectM-iOS scene."
        case let .newerVersion(version):
            "This scene was saved by a newer version of the app (format version \(version)); this version reads format version \(SceneDocument.currentVersion)."
        case let .invalidVersion(text):
            "The scene's format version must be a whole number from 1; found \(text)."
        case let .tooMany(what, count, limit):
            "The scene has \(count) \(what); at most \(limit) are allowed."
        case let .malformed(path, reason):
            "\(path): \(reason)."
        case let .migrationFailed(version, step, path, reason):
            "The scene's format version \(version) cannot be updated to version \(SceneDocument.currentVersion)"
                + (step.map { (s: String) -> String in " (step \(s))" } ?? "") + ": \(path): \(reason)."
        }
    }

    public var description: String { message }
}

/// One problem found in a decoded document.
public struct SceneIssue: Sendable, Hashable, CustomStringConvertible {
    public enum Severity: String, Sendable, Hashable {
        /// The document cannot become a live scene.
        case error
        /// Reported; the scene still opens.
        case warning
    }

    /// Stable codes (contract C5).
    public enum Code: String, Sendable, Hashable, CaseIterable {
        case invalidSceneID
        case invalidName
        case instanceOutOfRange
        case duplicateInstance
        case kindLimit
        case invalidValueName
        case unknownLayerKind
        case unsupportedBlendMode
        /// CMP-006: a fit mode name this version does not draw; kept and drawn as the layer's default.
        case unsupportedFitMode
        /// CMP-007: a mask shape kind this version does not draw; kept verbatim, the layer drawn unmasked.
        case unsupportedMaskShape
        /// CMP-011: a damaged layer group (bad ID, bad child reference, no layers, not one run); kept,
        /// its layers drawn ungrouped.
        case invalidGroup
        /// FX-020: an `effects` entry of a kind this version does not know; kept verbatim, not shown.
        case unknownEffectKind
        /// FX-020: an `effects` entry naming flash safety or the tone map, which always run last; kept, no effect.
        case fixedEffectStage
        /// FX-020: a second `effects` entry of the same kind; kept, only the first is used.
        case duplicateEffect
        case valueClamped
        case droppedField
        case unknownMaterial
        case danglingAsset
        case assetTypeMismatch
        case invalidAssetKey
        case invalidStoreID
        case invalidTextAsset
        case invalidGraphAsset
        case unknownAssetType
        case unusedAsset
        case missingAsset
        case malformedParameterID
        case orphanedParameter
        case rejectedParameter
        case parameterClamped
        case invalidBinding
        case duplicateBindingTarget
        case invalidExpression
        case invalidModulation
        /// MOD-013: an edge applied after the migration table rewrote an ID.
        case migratedReference
        /// MOD-013: an edge with a retired end; dropped and not saved again.
        case retiredReference
        /// MOD-013: a binding whose audio feature or target this version does not know; kept.
        case orphanedBinding
        /// MOD-013: a connection with an end this version does not know; kept.
        case orphanedConnection
        /// MOD-013: a connection refused by MOD-014 (a feedback loop included); kept.
        case rejectedConnection
        /// MOD-004: a binding whose stored curve this version cannot read; kept verbatim, not applied.
        case unsupportedCurve
        /// MOD-006: a threshold trigger with a missing or wrong field, invalid levels or times, or beyond the limit; kept.
        case invalidTrigger
        /// MOD-006: a threshold trigger whose audio feature or action this version does not know; kept.
        case unknownTrigger
        /// MOD-007: an oscillator with a missing or wrong field, out-of-range settings, or beyond the limit; kept.
        case invalidLFO
        /// MOD-007: an oscillator whose shape this version does not know; kept.
        case unknownLFO
        /// MOD-009: an oscillator's `sync` that is not an object or whose `beats` is not a finite positive number; kept,
        /// the oscillator runs unsynced.
        case invalidLFOSync
        /// MOD-009: an oscillator's sync length this version does not know; kept, the oscillator runs unsynced.
        case unknownLFOSync

        /// MOD-013 (ADR-0028 amendment): every per-edge modulation problem is a warning, so one edge
        /// never refuses the scene; `invalidModulation` (generator declarations) stays an error.
        public var severity: Severity {
            switch self {
            case .unknownLayerKind, .unsupportedBlendMode, .unsupportedFitMode, .unsupportedMaskShape, .invalidGroup, .unknownEffectKind, .fixedEffectStage,
                 .duplicateEffect, .valueClamped, .droppedField, .unknownAssetType, .unusedAsset,
                 .missingAsset, .orphanedParameter, .rejectedParameter, .parameterClamped,
                 .invalidBinding, .duplicateBindingTarget, .invalidExpression, .migratedReference, .retiredReference,
                 .orphanedBinding, .orphanedConnection, .rejectedConnection, .unsupportedCurve, .invalidTrigger, .unknownTrigger, .invalidLFO, .unknownLFO,
                 .invalidLFOSync, .unknownLFOSync:
                .warning
            default:
                .error
            }
        }
    }

    public let code: Code
    /// Where in the document, e.g. `$.layers[2].composite.opacity`.
    public let path: String
    public let message: String

    public init(_ code: Code, path: String, _ message: String) {
        self.code = code
        self.path = path
        self.message = message
    }

    public var severity: Severity { code.severity }
    public var isError: Bool { severity == .error }

    public var description: String { "\(severity.rawValue) \(code.rawValue) at \(path): \(message)" }
}

/// Why a document could not become a live scene.
public enum SceneLoadError: Error, Sendable, Hashable, CustomStringConvertible {
    /// Every error issue (warnings are returned with a successful load).
    case invalid([SceneIssue])

    public var description: String {
        switch self {
        case let .invalid(issues):
            (["The scene cannot be opened (\(issues.count) problem\(issues.count == 1 ? "" : "s")):"]
                + issues.map { (issue: SceneIssue) -> String in "- " + issue.message }).joined(separator: "\n")
        }
    }
}

/// Why a live state could not be captured as a document.
public enum SceneCaptureError: Error, Sendable, Hashable, CustomStringConvertible {
    /// A stack entry has no content (every entry needs one).
    case missingContent(instance: UInt64)
    /// The content's kind differs from the stack entry's kind.
    case contentMismatch(instance: UInt64, stackKind: String, contentKind: String)

    public var description: String {
        switch self {
        case let .missingContent(instance):
            "Layer \(instance) has no scene content."
        case let .contentMismatch(instance, stackKind, contentKind):
            "Layer \(instance) is a \"\(stackKind)\" layer but its content is \"\(contentKind)\"."
        }
    }
}
