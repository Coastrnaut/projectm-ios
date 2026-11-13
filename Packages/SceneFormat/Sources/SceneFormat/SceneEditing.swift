// SceneEditing.swift — duplicate and rename (SCN-003-R1 to R4; specs/074-scn-003-scene-duplicate-and-rename,
// contract D1; ADR-0028 amendment).
//
// Both operations copy the value and set only `name` (and `id` for a duplicate), so every other part —
// layers and their instance IDs, parameters, bindings, modulation, assets (store IDs shared, embedded
// text and graph documents copied with the value) and unknown content at every level — is kept
// exactly: the copy's canonical bytes with the original's id and name put back equal the original's.
// Neither validates the rest of the document (a copy of a scene with warnings has the same warnings).
// Pure; no files. The name rule (`isValidName`, `normalizedName`) is in SceneValidation.swift, the
// module's only Foundation file (it trims white space).

public enum SceneEditError: Error, Sendable, Hashable, CustomStringConvertible {
    /// Not 1…120 characters after trimming, or contains a control character.
    case invalidName
    /// Not canonical uppercase UUID text.
    case invalidSceneID(String)
    /// A duplicate must have a scene ID different from the original's.
    case sameSceneID

    public var description: String {
        switch self {
        case .invalidName: "A scene name is 1 to \(SceneLimits.maximumNameLength) characters without control characters."
        case let .invalidSceneID(id): "\"\(id)\" is not a scene ID."
        case .sameSceneID: "A copy needs a new scene ID."
        }
    }
}

extension SceneDocument {
    /// Suffix of a copy's name (`copyName`).
    public static let copySuffix = " copy"
    /// The name of a copy whose original name is invalid.
    public static let fallbackName = "Scene"

    /// "<name> copy", the base shortened (by characters, then re-trimmed) so the result fits 120
    /// characters; "Scene copy" when `name` is not a valid name.
    public static func copyName(_ name: String) -> String {
        let base = normalizedName(name) ?? fallbackName
        let room = SceneLimits.maximumNameLength - copySuffix.count
        let shortened = base.count > room ? (normalizedName(String(base.prefix(room))) ?? "") : base
        return (shortened.isEmpty ? fallbackName : shortened) + copySuffix
    }

    /// The same scene with a new name (trimmed); the ID and everything else unchanged.
    public func renamed(to name: String) throws(SceneEditError) -> SceneDocument {
        guard let normalized = Self.normalizedName(name) else { throw .invalidName }
        var copy = self
        copy.name = normalized
        return copy
    }

    /// A copy under `newID` (canonical uppercase UUID, different from this scene's) named `name`
    /// (trimmed); everything else unchanged.
    public func duplicated(newID: String, name: String) throws(SceneEditError) -> SceneDocument {
        guard Self.isCanonicalUUID(newID) else { throw .invalidSceneID(newID) }
        guard newID != id else { throw .sameSceneID }
        var copy = try renamed(to: name)
        copy.id = newID
        return copy
    }
}
