// SceneTags.swift — SCN-005 scene tags (spec SCN-005-R1 to R4, R7; research SCN-005-D2 to D4;
// contract T1 to T3).
//
// Tags are labels a user assigns to the show's scenes, kept by scene ID in the show's index beside the
// cues and SCN-004's folders. Scene files never change. The vocabulary is derived (the union of every
// scene's tags). Identity folds case, accents and width with SCN-004's folding (`nil` locale); a tag
// keeps its display case, and adding a tag the show already has uses the existing spelling. Each
// scene's tags are kept sorted by (folded text, text). A value type; every refused operation changes
// nothing. Foundation only (builds and tests on Linux).
import Foundation

public enum SceneTagError: Error, Sendable, Hashable, CustomStringConvertible {
    case invalidTag
    case alreadyTagged(String)
    case notTagged(String)
    case tooManyTags(limit: Int)
    case tooManyDistinctTags(limit: Int)
    case sceneNotInShow(String)

    public var description: String {
        switch self {
        case .invalidTag: "A tag is 1 to \(SceneTagMap.maximumTagLength) characters on one line."
        case let .alreadyTagged(tag): "The scene is already tagged \(tag)."
        case let .notTagged(tag): "The scene is not tagged \(tag)."
        case let .tooManyTags(limit): "A scene has at most \(limit) tags."
        case let .tooManyDistinctTags(limit): "A show has at most \(limit) different tags."
        case .sceneNotInShow: "The scene is not in the show."
        }
    }
}

public struct SceneTagMap: Sendable, Hashable {
    public static let maximumTagLength = 40
    public static let maximumTagsPerScene = 16
    public static let maximumDistinctTags = 256

    /// Scene ID → its tags, sorted by (folded text, text); a scene without tags has no entry.
    public private(set) var tags: [String: [String]]

    public init() { tags = [:] }

    public var isEmpty: Bool { tags.isEmpty }

    // MARK: - Rules

    /// Trimmed text of 1…40 characters with no line breaks or control characters, or nil.
    public static func normalizedTag(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumTagLength else { return nil }
        let bad: Bool = trimmed.unicodeScalars.contains { (u: Unicode.Scalar) -> Bool in
            u.properties.generalCategory == .control || CharacterSet.newlines.contains(u)
        }
        return bad ? nil : trimmed
    }

    /// The comparison form of a tag (SCN-004's folding: case, accents, width; fixed locale).
    public static func fold(_ tag: String) -> String { SceneFolderTree.fold(tag) }

    static func ordered(_ a: String, _ b: String) -> Bool {
        let fa: String = fold(a)
        let fb: String = fold(b)
        if fa != fb { return fa < fb }
        return a < b
    }

    // MARK: - Reading

    /// The scene's tags (sorted; empty when none).
    public func tags(ofScene sceneID: String) -> [String] { tags[sceneID] ?? [] }

    /// Whether the scene carries the tag (folded comparison).
    public func scene(_ sceneID: String, has tag: String) -> Bool {
        let folded: String = Self.fold(tag)
        return tags(ofScene: sceneID).contains { (t: String) -> Bool in Self.fold(t) == folded }
    }

    /// One spelling per tag in the show (the smallest by folded text, then text), sorted.
    public var vocabulary: [String] {
        var best: [String: String] = [:]
        for list in tags.values {
            for tag in list {
                let key: String = Self.fold(tag)
                if let current = best[key], !Self.ordered(tag, current) { continue }
                best[key] = tag
            }
        }
        return best.values.sorted(by: Self.ordered)
    }

    /// The show's spelling of a tag (folded match), or nil when no scene carries it.
    public func existingSpelling(of tag: String) -> String? {
        let folded: String = Self.fold(tag)
        return vocabulary.first { (t: String) -> Bool in Self.fold(t) == folded }
    }

    /// How many scenes carry the tag.
    public func count(of tag: String) -> Int {
        tags.keys.filter { (scene: String) -> Bool in self.scene(scene, has: tag) }.count
    }

    /// True when the scene carries every tag of `all` (AND; folded). An empty `all` matches every scene.
    public func matches(sceneID: String, all required: Set<String>) -> Bool {
        guard !required.isEmpty else { return true }
        let own: Set<String> = Set(tags(ofScene: sceneID).map(Self.fold))
        return required.allSatisfy { (tag: String) -> Bool in own.contains(Self.fold(tag)) }
    }

    private var distinctFolded: Set<String> {
        var result = Set<String>()
        for list in tags.values { for tag in list { result.insert(Self.fold(tag)) } }
        return result
    }

    // MARK: - Editing

    /// Adds a tag to a scene; returns the spelling stored (the show's existing one when present).
    @discardableResult
    public mutating func add(_ text: String, to sceneID: String) throws(SceneTagError) -> String {
        guard let tag = Self.normalizedTag(text) else { throw .invalidTag }
        var list: [String] = tags(ofScene: sceneID)
        if let own = list.first(where: { (t: String) -> Bool in Self.fold(t) == Self.fold(tag) }) { throw .alreadyTagged(own) }
        guard list.count < Self.maximumTagsPerScene else { throw .tooManyTags(limit: Self.maximumTagsPerScene) }
        let spelling: String
        if let existing = existingSpelling(of: tag) {
            spelling = existing
        } else {
            guard distinctFolded.count < Self.maximumDistinctTags else { throw .tooManyDistinctTags(limit: Self.maximumDistinctTags) }
            spelling = tag
        }
        list.append(spelling)
        tags[sceneID] = list.sorted(by: Self.ordered)
        return spelling
    }

    /// Removes a tag (folded match) from a scene; returns the spelling removed.
    @discardableResult
    public mutating func remove(_ tag: String, from sceneID: String) throws(SceneTagError) -> String {
        let folded: String = Self.fold(tag)
        var list: [String] = tags(ofScene: sceneID)
        guard let index = list.firstIndex(where: { (t: String) -> Bool in Self.fold(t) == folded }) else { throw .notTagged(tag) }
        let removed: String = list.remove(at: index)
        tags[sceneID] = list.isEmpty ? nil : list
        return removed
    }

    /// Gives `target` the tags of `source` (Duplicate Scene; SCN-005-R9). Replaces the target's tags.
    public mutating func copyTags(from source: String, to target: String) {
        let list: [String] = tags(ofScene: source)
        tags[target] = list.isEmpty ? nil : list
    }

    /// Drops the tags of scenes outside `sceneIDs`; returns how many scenes lost their tags.
    @discardableResult
    public mutating func prune(keepingScenes sceneIDs: Set<String>) -> Int {
        let before: Int = tags.count
        tags = tags.filter { (entry: (key: String, value: [String])) -> Bool in sceneIDs.contains(entry.key) }
        return before - tags.count
    }

    // MARK: - Stored form (ShowDocument)

    /// Builds a map from stored entries, keeping what satisfies every rule (research SCN-005-D4).
    /// `stored` is scene ID → the stored list (nil = not a list of strings). Scenes are visited in
    /// sorted ID order and each list in its stored order, so the result is deterministic. Returns the
    /// map and how many tags and entries were dropped.
    public static func repaired(_ stored: [String: [String]?], sceneIDs: Set<String>) -> (map: SceneTagMap, dropped: Int) {
        var map = SceneTagMap()
        var dropped = 0
        for scene in stored.keys.sorted() {
            let value: [String]? = stored[scene] ?? nil
            guard let list = value else { dropped += 1; continue }   // not a list of strings
            // An unknown scene drops all its tags; an empty list is a dropped entry.
            guard sceneIDs.contains(scene), !list.isEmpty else { dropped += max(list.count, 1); continue }
            for text in list {
                // A stored tag must already be in its normalized form and must not repeat on the scene.
                guard let tag = normalizedTag(text), tag == text, !map.scene(scene, has: tag) else {
                    dropped += 1
                    continue
                }
                var tagsOfScene: [String] = map.tags(ofScene: scene)
                guard tagsOfScene.count < maximumTagsPerScene else { dropped += 1; continue }
                if map.existingSpelling(of: tag) == nil, map.distinctFolded.count >= maximumDistinctTags { dropped += 1; continue }
                tagsOfScene.append(tag)   // each scene keeps its own stored spelling
                map.tags[scene] = tagsOfScene.sorted(by: ordered)
            }
        }
        return (map, dropped)
    }
}
