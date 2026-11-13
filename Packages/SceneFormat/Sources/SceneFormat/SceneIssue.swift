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

        public var severity: Severity {
            switch self {
            case .unknownLayerKind, .unsupportedBlendMode, .valueClamped, .droppedField, .unknownAssetType, .unusedAsset,
                 .missingAsset, .orphanedParameter, .rejectedParameter, .parameterClamped:
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
