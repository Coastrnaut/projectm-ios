// ShowDocument.swift — `show.json`, version 1 (SHOW-001-R2, R11; contract S1; research SHOW-001-D4).
//
// JSON with sorted keys: encoding the same show twice gives the same bytes, and decode → encode of a
// written file is byte-identical. Order of checks: size (before parsing) → JSON → `format` →
// `version` (a newer one is refused, never rewritten) → fields → the model's rules (cue limit, labels,
// scene IDs, duplicate cue IDs). A position naming no cue is a warning (Standby).
// SCN-007: each cue entry may carry an optional `transition` object (`duration`, `easing`, `type`), written
// only when the cue has one, so older shows keep their bytes; read leniently (contract X1-X3).
import Foundation
import ParameterGraph

public enum ShowDecodeError: Error, Sendable, Hashable, CustomStringConvertible {
    case tooLarge(bytes: Int, limit: Int)
    /// Not JSON, or a field missing or of the wrong type.
    case malformed
    case wrongFormat(String)
    case newerVersion(Int)
    case unsupportedVersion(Int)
    case invalidID(String)
    case invalid(ShowEditError)

    public var description: String {
        switch self {
        case let .tooLarge(bytes, limit): "The show file is \(bytes) bytes; the limit is \(limit)."
        case .malformed: "The show file is not a valid show."
        case let .wrongFormat(format): "The file is a \"\(format)\" file, not a show."
        case let .newerVersion(version): "The show was saved by a newer version of the app (format version \(version))."
        case let .unsupportedVersion(version): "Show format version \(version) is not supported."
        case let .invalidID(text): "\"\(text)\" is not a valid identifier."
        case let .invalid(error): error.description
        }
    }
}

public enum ShowDecodeWarning: Sendable, Hashable {
    /// The stored position named no cue; the show starts at Standby.
    case danglingPosition(String)
    /// SCN-004: folder entries that broke a rule (bad ID or name, unknown parent, cycle, too deep,
    /// duplicate sibling name, over the limit) were left out.
    case droppedFolders(Int)
    /// SCN-004: scene-folder assignments to an unknown folder or a scene no cue shows were left out.
    case droppedFolderAssignments(Int)
    /// SCN-005: tags or `sceneTags` entries that broke a rule (unknown scene, invalid or repeated
    /// tag, over a limit, not a list of strings) were left out.
    case droppedTags(Int)
    /// SCN-007: cue transitions that broke a rule (not an object, a missing field, a duration outside
    /// 0…10 s, an unreadable or invalid easing, a type of 0 or over 64 characters) were left out.
    case droppedTransitions(Int)
    /// SCN-007: a cue's transition type is not one this version knows; it is kept and applied as a cut.
    case unknownTransitionType(cue: String, type: String)
}

public struct ShowDecodeResult: Sendable {
    public let list: ShowCueList
    public let warnings: [ShowDecodeWarning]
}

extension ShowCueList {
    public static let formatName = "projectm-ios.show"
    public static let currentVersion = 1
    /// Checked on the byte count before anything is parsed.
    public static let maximumFileBytes = 1_048_576

    /// The file's bytes (contract S1).
    public func encoded() -> Data {
        var file = ShowFileV1(format: Self.formatName, version: Self.currentVersion, id: id.uuidString, name: name,
                              cues: cues.map { (cue: ShowCue) -> ShowFileV1.Cue in
                                  ShowFileV1.Cue(id: cue.id.uuidString, scene: cue.sceneID, label: cue.label,
                                                 transition: cue.transition.map(StoredTransition.init(_:)))
                              },
                              position: activeCue?.id.uuidString)
        // SCN-004 (contract F4): written only when non-empty, so a show without folders keeps its bytes.
        var tree = folders
        tree.prune(keepingScenes: Set(sceneIDs))
        if !tree.folders.isEmpty {
            file.folders = tree.foldersInFileOrder.map { (f: SceneFolder) -> ShowFileV1.Folder in
                ShowFileV1.Folder(id: f.id.uuidString, name: f.name, parent: f.parentID?.uuidString)
            }
        }
        if !tree.assignments.isEmpty {
            var map: [String: String] = [:]
            for (scene, folder) in tree.assignments { map[scene] = folder.uuidString }
            file.sceneFolders = map
        }
        // SCN-005 (contract T1): written only when a scene the cues show has tags.
        var tagMap = tags
        tagMap.prune(keepingScenes: Set(sceneIDs))
        if !tagMap.isEmpty { file.sceneTags = tagMap.tags.mapValues { (list: [String]) -> LenientTags in .tags(list) } }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Encoding plain strings, ints and arrays cannot fail.
        return (try? encoder.encode(file)) ?? Data()
    }

    public static func decode(_ data: Data) throws(ShowDecodeError) -> ShowDecodeResult {
        guard data.count <= maximumFileBytes else { throw .tooLarge(bytes: data.count, limit: maximumFileBytes) }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(ShowFileHeader.self, from: data) else { throw .malformed }
        guard header.format == formatName else { throw .wrongFormat(header.format) }
        guard header.version <= currentVersion else { throw .newerVersion(header.version) }
        guard header.version == currentVersion else { throw .unsupportedVersion(header.version) }
        guard let file = try? decoder.decode(ShowFileV1.self, from: data) else { throw .malformed }
        guard let showID = canonicalUUID(file.id) else { throw .invalidID(file.id) }
        guard file.cues.count <= maximumCues else { throw .invalid(.tooManyCues(limit: maximumCues)) }
        var cues: [ShowCue] = []
        var warnings: [ShowDecodeWarning] = []
        var droppedTransitions = 0
        for cue in file.cues {
            guard let cueID = canonicalUUID(cue.id) else { throw .invalidID(cue.id) }
            var transition: ShowCueTransition? = nil
            if let stored = cue.transition {   // SCN-007 (contract X2)
                transition = stored.transition
                if transition == nil { droppedTransitions += 1 }
                if let type = transition?.type, !type.isKnown {
                    warnings.append(.unknownTransitionType(cue: cue.id, type: type.text))
                }
            }
            cues.append(ShowCue(id: cueID, sceneID: cue.scene, label: cue.label, transition: transition))
        }
        if droppedTransitions > 0 { warnings.append(.droppedTransitions(droppedTransitions)) }
        var position = ShowPosition.standby
        if let text = file.position {
            if let cueID = canonicalUUID(text), cues.contains(where: { (c: ShowCue) -> Bool in c.id == cueID }) {
                position = .cue(cueID)
            } else {
                warnings.append(.danglingPosition(text))
            }
        }
        do {
            var list = try ShowCueList(id: showID, name: file.name, cues: cues, position: position)
            if file.folders != nil || file.sceneFolders != nil {
                let entries = (file.folders ?? []).map { (f: ShowFileV1.Folder) -> (id: String, name: String, parent: String?) in
                    (f.id, f.name, f.parent)
                }
                let repaired = SceneFolderTree.repaired(folders: entries, assignments: file.sceneFolders ?? [:],
                                                        sceneIDs: Set(list.sceneIDs))
                list.folders = repaired.tree
                if repaired.droppedFolders > 0 { warnings.append(.droppedFolders(repaired.droppedFolders)) }
                if repaired.droppedAssignments > 0 { warnings.append(.droppedFolderAssignments(repaired.droppedAssignments)) }
            }
            if let stored = file.sceneTags {   // SCN-005 (contract T2)
                let raw: [String: [String]?] = stored.mapValues { (value: LenientTags) -> [String]? in value.list }
                let repaired = SceneTagMap.repaired(raw, sceneIDs: Set(list.sceneIDs))
                list.tags = repaired.map
                if repaired.dropped > 0 { warnings.append(.droppedTags(repaired.dropped)) }
            } else if file.sceneTagsUnreadable {
                warnings.append(.droppedTags(1))
            }
            return ShowDecodeResult(list: list, warnings: warnings)
        } catch {
            throw .invalid(error)
        }
    }

    private static func canonicalUUID(_ text: String) -> UUID? {
        guard let id = UUID(uuidString: text), id.uuidString == text else { return nil }
        return id
    }
}

/// Read first, so a newer version is recognised whatever its other fields look like.
private struct ShowFileHeader: Decodable {
    let format: String
    let version: Int
}

private struct ShowFileV1: Codable {
    struct Cue: Codable {
        let id: String
        let scene: String
        let label: String
        /// SCN-007, optional: absent (or null) = no transition.
        var transition: StoredTransition? = nil

        enum CodingKeys: String, CodingKey { case id, scene, label, transition }

        init(id: String, scene: String, label: String, transition: StoredTransition?) {
            self.id = id
            self.scene = scene
            self.label = label
            self.transition = transition
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            scene = try container.decode(String.self, forKey: .scene)
            label = try container.decode(String.self, forKey: .label)
            transition = try container.decodeIfPresent(StoredTransition.self, forKey: .transition)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(scene, forKey: .scene)
            try container.encode(label, forKey: .label)
            try container.encodeIfPresent(transition, forKey: .transition)
        }
    }

    /// SCN-004: a scene folder (parent nil = top level).
    struct Folder: Codable {
        let id: String
        let name: String
        let parent: String?

        // `parent` is written as null at the top level.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(parent, forKey: .parent)
        }
    }

    let format: String
    let version: Int
    let id: String
    let name: String
    let cues: [Cue]
    let position: String?
    /// SCN-004, optional: absent = no folders.
    var folders: [Folder]? = nil
    /// SCN-004, optional: scene ID → folder ID; absent = every scene at the top level.
    var sceneFolders: [String: String]? = nil
    /// SCN-005, optional: scene ID → tags; absent = no tags. Read leniently (contract T2).
    var sceneTags: [String: LenientTags]? = nil
    /// SCN-005: `sceneTags` was present but not an object (decoding only).
    var sceneTagsUnreadable = false

    enum CodingKeys: String, CodingKey {
        case format, version, id, name, cues, position, folders, sceneFolders, sceneTags
    }

    init(format: String, version: Int, id: String, name: String, cues: [Cue], position: String?) {
        self.format = format
        self.version = version
        self.id = id
        self.name = name
        self.cues = cues
        self.position = position
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        cues = try container.decode([Cue].self, forKey: .cues)
        position = try container.decodeIfPresent(String.self, forKey: .position)
        folders = try container.decodeIfPresent([Folder].self, forKey: .folders)
        sceneFolders = try container.decodeIfPresent([String: String].self, forKey: .sceneFolders)
        if container.contains(.sceneTags), try !container.decodeNil(forKey: .sceneTags) {
            if let map = try? container.decode([String: LenientTags].self, forKey: .sceneTags) {
                sceneTags = map
            } else {
                sceneTagsUnreadable = true
            }
        }
    }

    // `position` is written as null at Standby (the synthesized encoder would leave it out).
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
        try container.encode(version, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(cues, forKey: .cues)
        try container.encode(position, forKey: .position)
        try container.encodeIfPresent(folders, forKey: .folders)
        try container.encodeIfPresent(sceneFolders, forKey: .sceneFolders)
        try container.encodeIfPresent(sceneTags, forKey: .sceneTags)
    }
}

/// SCN-005: one `sceneTags` value, read leniently: a list of strings, or anything else (dropped).
private enum LenientTags: Codable {
    case tags([String])
    case other

    var list: [String]? {
        if case let .tags(list) = self { return list }
        return nil
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([String].self) { self = .tags(list) } else { self = .other }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(list ?? [])
    }
}

/// SCN-007: one cue's `transition` value, read leniently: anything that is not a valid transition object
/// decodes as `nil` content (dropped with a warning) instead of refusing the show.
private struct StoredTransition: Codable {
    let transition: ShowCueTransition?

    init(_ transition: ShowCueTransition) { self.transition = transition }

    private struct Fields: Codable {
        let duration: Double
        let easing: String
        let type: String
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let fields = try? container.decode(Fields.self), let type = ShowTransitionType(text: fields.type),
              let easing = MappingCurve(textForm: fields.easing) else {
            transition = nil
            return
        }
        transition = try? ShowCueTransition(type: type, durationSeconds: fields.duration, easing: easing)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        guard let transition else { return try container.encodeNil() }
        try container.encode(Fields(duration: transition.durationSeconds, easing: transition.easing.textForm,
                                    type: transition.type.text))
    }
}
