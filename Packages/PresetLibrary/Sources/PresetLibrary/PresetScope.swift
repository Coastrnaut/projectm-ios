// PresetScope.swift — what Next/Previous/Random walk (feature 002 FR-116-FR-119, research R-27).
import Foundation

public enum PresetScope: Sendable, Hashable {
    case included
    case pack(String)
    case folder(String, [String])
    case favorites
    case search(String)
    case all
    /// A user-made collection, by its permanent id (PRE-007-R11). Its members are in the user's
    /// order, not alphabetical.
    case collection(String)
    /// The presets the user imported (PRE-012-R22), alphabetical.
    case user
    /// PRE-003-R10: the presets carrying every one of these tags (display spellings), alphabetical.
    /// Like a search it is not kept across launches: it is stored as `all`.
    case tagged([String])

    /// Persisted as `settings.presetScope`. A search scope stores `all`: no search text is kept
    /// (spec Clarifications, FR-119).
    public var storageValue: String {
        switch self {
        case .included: "included"
        case .pack(let id): "pack:\(id)"
        case .folder(let id, let path): "folder:" + ([id] + path).joined(separator: "/")
        case .favorites: "favorites"
        case .search, .all, .tagged: "all"
        case .collection(let id): "collection:\(id)"
        case .user: "user"
        }
    }

    public init?(storageValue: String) {
        switch storageValue {
        case "included": self = .included
        case "favorites": self = .favorites
        case "all": self = .all
        case "user": self = .user
        default:
            if storageValue.hasPrefix("pack:") {
                let id = String(storageValue.dropFirst(5))
                guard !id.isEmpty else { return nil }
                self = .pack(id)
            } else if storageValue.hasPrefix("collection:") {
                let id = String(storageValue.dropFirst(11))
                guard !id.isEmpty else { return nil }
                self = .collection(id)
            } else if storageValue.hasPrefix("folder:") {
                let parts = storageValue.dropFirst(7).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 2, !parts[0].isEmpty else { return nil }
                self = .folder(parts[0], Array(parts.dropFirst()))
            } else {
                return nil
            }
        }
    }
}

/// FR-117: stepping and random picks within a scope's members.
public enum ScopeStepper {
    /// Alphabetical step with wrap at both ends; nil for an empty scope. With no current preset,
    /// +1 starts at the first and -1 at the last (release 1.0 behavior).
    public static func step(_ members: [IndexedPreset], from current: IndexedPreset?, by delta: Int) -> IndexedPreset? {
        guard !members.isEmpty else { return nil }
        let index = current.flatMap { members.firstIndex(of: $0) } ?? (delta > 0 ? -1 : 0)
        let count = members.count
        return members[((index + delta) % count + count) % count]
    }

    /// Uniform within the scope, never the current preset when another exists.
    public static func random<G: RandomNumberGenerator>(_ members: [IndexedPreset], excluding current: IndexedPreset?,
                                                         using generator: inout G) -> IndexedPreset? {
        guard !members.isEmpty else { return nil }
        let others = members.filter { $0 != current }
        guard !others.isEmpty else { return members[0] }
        return others.randomElement(using: &generator)
    }
}
