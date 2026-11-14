// ShowDocument.swift — `show.json`, version 1 (SHOW-001-R2, R11; contract S1; research SHOW-001-D4).
//
// JSON with sorted keys: encoding the same show twice gives the same bytes, and decode → encode of a
// written file is byte-identical. Order of checks: size (before parsing) → JSON → `format` →
// `version` (a newer one is refused, never rewritten) → fields → the model's rules (cue limit, labels,
// scene IDs, duplicate cue IDs). A position naming no cue is a warning (Standby).
import Foundation

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
                                  ShowFileV1.Cue(id: cue.id.uuidString, scene: cue.sceneID, label: cue.label)
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
        for cue in file.cues {
            guard let cueID = canonicalUUID(cue.id) else { throw .invalidID(cue.id) }
            cues.append(ShowCue(id: cueID, sceneID: cue.scene, label: cue.label))
        }
        var warnings: [ShowDecodeWarning] = []
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
    }
}
