// PresetReferenceSnapshot.swift — roadmap PRE-018 (R1; data-model.md): the preset IDs that the five
// reference stores name, copied when a check starts so the scan never touches a live store.
import Foundation

public struct PresetReferenceSnapshot: Sendable, Equatable {
    public struct Collection: Sendable, Equatable {
        public var id: String
        public var name: String
        public var presetIDs: [String]

        public init(id: String, name: String, presetIDs: [String]) {
            self.id = id; self.name = name; self.presetIDs = presetIDs
        }
    }

    public var favorites: [String]
    /// Preset IDs with at least one tag.
    public var tags: [String]
    /// Preset IDs with at least one adjustment (PRE-016).
    public var overrides: [String]
    public var collections: [Collection]
    public var recents: [String]

    public init(favorites: [String] = [], tags: [String] = [], overrides: [String] = [], collections: [Collection] = [],
                recents: [String] = []) {
        self.favorites = favorites; self.tags = tags; self.overrides = overrides
        self.collections = collections; self.recents = recents
    }

    public static let empty = PresetReferenceSnapshot()
}
