// SceneFolders.swift — SCN-004 logical scene folders (spec SCN-004-R1 to R5; research SCN-004-D1, D2;
// contract F2, F3).
//
// Folders are logical: a tree of (ID, name, parent) plus scene-ID → folder-ID assignments, kept in the
// show's index beside the cues. Scene files never move and every reference to a scene is its scene ID,
// so organizing never breaks a reference. A value type; every refused operation changes nothing.
// Foundation only (builds and tests on Linux).
import Foundation

/// One folder: a stable ID, a name unique among its siblings, and its parent (nil = top level).
public struct SceneFolder: Sendable, Hashable, Identifiable {
    public let id: UUID
    public internal(set) var name: String
    public internal(set) var parentID: UUID?

    public init(id: UUID, name: String, parentID: UUID?) {
        self.id = id
        self.name = name
        self.parentID = parentID
    }
}

public enum SceneFolderError: Error, Sendable, Hashable, CustomStringConvertible {
    case invalidName
    case nameTaken(String)
    case unknownFolder(UUID)
    case intoItself
    case tooDeep(limit: Int)
    case tooManyFolders(limit: Int)
    case duplicateFolderID(UUID)
    case sceneNotInShow(String)

    public var description: String {
        switch self {
        case .invalidName: "A folder name is 1 to \(SceneFolderTree.maximumNameLength) characters on one line."
        case let .nameTaken(name): "A folder named \(name) already exists here."
        case .unknownFolder: "The folder no longer exists."
        case .intoItself: "A folder cannot be moved into itself."
        case let .tooDeep(limit): "Folders can be nested at most \(limit) levels deep."
        case let .tooManyFolders(limit): "A show holds at most \(limit) folders."
        case let .duplicateFolderID(id): "The folder ID \(id.uuidString) is used twice."
        case .sceneNotInShow: "The scene is not in the show."
        }
    }
}

/// What deleting a folder moved to its parent (contract F3).
public struct SceneFolderDeletion: Sendable, Hashable {
    public let folder: SceneFolder
    public let movedScenes: [String]
    public let movedFolders: [UUID]
    /// Child folders renamed because their name was taken in the parent: (id, new name).
    public let renamed: [UUID: String]
}

public struct SceneFolderTree: Sendable, Hashable {
    public static let maximumDepth = 5
    public static let maximumFolders = 256
    public static let maximumNameLength = 80

    public private(set) var folders: [UUID: SceneFolder]
    /// Scene ID → folder ID; a scene without an entry is at the top level.
    public private(set) var assignments: [String: UUID]

    public init() {
        folders = [:]
        assignments = [:]
    }

    public var isEmpty: Bool { folders.isEmpty && assignments.isEmpty }

    // MARK: - Rules

    /// Trimmed text of 1…80 characters with no line breaks, or nil.
    public static func normalizedName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumNameLength else { return nil }
        guard !trimmed.unicodeScalars.contains(where: { (u: Unicode.Scalar) -> Bool in u.properties.generalCategory == .control || CharacterSet.newlines.contains(u) }) else {
            return nil
        }
        return trimmed
    }

    /// The comparison form of a name: case, accents and width folded, fixed locale.
    public static func fold(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    // MARK: - Reading

    public func folder(_ id: UUID) -> SceneFolder? { folders[id] }

    /// The scene's folder (nil = top level or an unknown folder).
    public func folderID(ofScene sceneID: String) -> UUID? {
        guard let id = assignments[sceneID], folders[id] != nil else { return nil }
        return id
    }

    /// Subfolders of `parent` (nil = top level), sorted by folded name, then ID.
    public func children(of parent: UUID?) -> [SceneFolder] {
        folders.values.filter { (f: SceneFolder) -> Bool in f.parentID == parent }.sorted(by: Self.ordered)
    }

    static func ordered(_ a: SceneFolder, _ b: SceneFolder) -> Bool {
        let fa = fold(a.name)
        let fb = fold(b.name)
        if fa != fb { return fa < fb }
        return a.id.uuidString < b.id.uuidString
    }

    /// The scenes of `sceneIDs` whose folder is `folder` (nil = top level), in the given order.
    public func sceneIDs(in folder: UUID?, among sceneIDs: [String]) -> [String] {
        sceneIDs.filter { (id: String) -> Bool in folderID(ofScene: id) == folder }
    }

    /// Folders from the top level down to `id` (empty for an unknown ID).
    public func path(of id: UUID) -> [SceneFolder] {
        var result: [SceneFolder] = []
        var current: UUID? = id
        while let next = current, let folder = folders[next], result.count <= Self.maximumDepth {
            result.insert(folder, at: 0)
            current = folder.parentID
        }
        return result
    }

    /// "Set A / Encore" for a folder; nil for nil or an unknown folder.
    public func pathText(of id: UUID?) -> String? {
        guard let id else { return nil }
        let names = path(of: id).map { (f: SceneFolder) -> String in f.name }
        return names.isEmpty ? nil : names.joined(separator: " / ")
    }

    /// 1 for a top-level folder; 0 for the top level itself (nil).
    public func depth(of id: UUID?) -> Int {
        guard let id else { return 0 }
        return path(of: id).count
    }

    /// 1 for a folder without subfolders.
    public func height(of id: UUID) -> Int {
        1 + (children(of: id).map { (f: SceneFolder) -> Int in height(of: f.id) }.max() ?? 0)
    }

    /// `id` and every folder below it.
    public func subtree(of id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id]
        for child in children(of: id) { result.formUnion(subtree(of: child.id)) }
        return result
    }

    /// Whether `id` can be moved into `parent` (the Move to… sheet dims the rest).
    public func canMoveFolder(_ id: UUID, to parent: UUID?) -> Bool {
        guard let folder = folders[id] else { return false }
        if folder.parentID == parent { return true }
        guard (try? checkFolderMove(folder, to: parent)) != nil else { return false }
        return true
    }

    /// Whether a new folder can be created inside `parent`.
    public func canCreateFolder(in parent: UUID?) -> Bool {
        guard folders.count < Self.maximumFolders, depth(of: parent) < Self.maximumDepth else { return false }
        if let parent { return folders[parent] != nil }
        return true
    }

    private func nameTaken(_ name: String, in parent: UUID?, except: UUID? = nil) -> Bool {
        let folded = Self.fold(name)
        return folders.values.contains { (f: SceneFolder) -> Bool in
            f.parentID == parent && f.id != except && Self.fold(f.name) == folded
        }
    }

    // MARK: - Editing

    /// Creates a folder in `parent` (nil = top level).
    @discardableResult
    public mutating func createFolder(named text: String, in parent: UUID?, id: UUID = UUID()) throws(SceneFolderError) -> SceneFolder {
        guard let name = Self.normalizedName(text) else { throw .invalidName }
        guard folders[id] == nil else { throw .duplicateFolderID(id) }
        if let parent, folders[parent] == nil { throw .unknownFolder(parent) }
        guard folders.count < Self.maximumFolders else { throw .tooManyFolders(limit: Self.maximumFolders) }
        guard depth(of: parent) < Self.maximumDepth else { throw .tooDeep(limit: Self.maximumDepth) }
        guard !nameTaken(name, in: parent) else { throw .nameTaken(name) }
        let folder = SceneFolder(id: id, name: name, parentID: parent)
        folders[id] = folder
        return folder
    }

    public mutating func renameFolder(_ id: UUID, to text: String) throws(SceneFolderError) {
        guard var folder = folders[id] else { throw .unknownFolder(id) }
        guard let name = Self.normalizedName(text) else { throw .invalidName }
        guard !nameTaken(name, in: folder.parentID, except: id) else { throw .nameTaken(name) }
        folder.name = name
        folders[id] = folder
    }

    private func checkFolderMove(_ folder: SceneFolder, to parent: UUID?) throws(SceneFolderError) {
        if let parent {
            guard folders[parent] != nil else { throw .unknownFolder(parent) }
            guard !subtree(of: folder.id).contains(parent) else { throw .intoItself }
        }
        guard depth(of: parent) + height(of: folder.id) <= Self.maximumDepth else { throw .tooDeep(limit: Self.maximumDepth) }
        guard !nameTaken(folder.name, in: parent, except: folder.id) else { throw .nameTaken(folder.name) }
    }

    /// Moves a folder (and everything in it) into `parent`; moving to its own parent changes nothing.
    public mutating func moveFolder(_ id: UUID, to parent: UUID?) throws(SceneFolderError) {
        guard var folder = folders[id] else { throw .unknownFolder(id) }
        guard folder.parentID != parent else { return }
        try checkFolderMove(folder, to: parent)
        folder.parentID = parent
        folders[id] = folder
    }

    /// Puts a scene in `folder` (nil = top level). Returns false when it was already there.
    @discardableResult
    public mutating func moveScene(_ sceneID: String, to folder: UUID?) throws(SceneFolderError) -> Bool {
        if let folder, folders[folder] == nil { throw .unknownFolder(folder) }
        guard folderID(ofScene: sceneID) != folder else { return false }
        assignments[sceneID] = folder
        return true
    }

    /// Deletes a folder: its scenes and subfolders move to its parent; a subfolder whose name is
    /// taken there gets " 2", " 3"… (contract F3). No scene is removed.
    @discardableResult
    public mutating func deleteFolder(_ id: UUID) throws(SceneFolderError) -> SceneFolderDeletion {
        guard let folder = folders[id] else { throw .unknownFolder(id) }
        let parent = folder.parentID
        let scenes = assignments.filter { (entry: (key: String, value: UUID)) -> Bool in entry.value == id }.map(\.key).sorted()
        for scene in scenes { assignments[scene] = parent }
        let moving = children(of: id)
        folders[id] = nil
        var renamed: [UUID: String] = [:]
        for child in moving {
            var updated = child
            updated.parentID = parent
            if nameTaken(child.name, in: parent, except: child.id) {
                updated.name = freeName(child.name, in: parent, except: child.id)
                renamed[child.id] = updated.name
            }
            folders[child.id] = updated
        }
        return SceneFolderDeletion(folder: folder, movedScenes: scenes, movedFolders: moving.map(\.id), renamed: renamed)
    }

    /// "<name> 2", "<name> 3"…, the base shortened so the result fits 80 characters.
    private func freeName(_ name: String, in parent: UUID?, except: UUID) -> String {
        var n = 2
        while true {
            let suffix = " \(n)"
            let room = Self.maximumNameLength - suffix.count
            let base = name.count > room ? String(name.prefix(room)).trimmingCharacters(in: .whitespaces) : name
            let candidate = base + suffix
            if !nameTaken(candidate, in: parent, except: except) { return candidate }
            n += 1
        }
    }

    // MARK: - Stored form (ShowDocument)

    /// Folders parents first (depth, then ID text), for a deterministic file.
    public var foldersInFileOrder: [SceneFolder] {
        folders.values.sorted { (a: SceneFolder, b: SceneFolder) -> Bool in
            let da = depth(of: a.id)
            let db = depth(of: b.id)
            if da != db { return da < db }
            return a.id.uuidString < b.id.uuidString
        }
    }

    /// Drops assignments to unknown folders or to scenes outside `sceneIDs`; returns how many.
    @discardableResult
    public mutating func prune(keepingScenes sceneIDs: Set<String>) -> Int {
        let before = assignments.count
        assignments = assignments.filter { (entry: (key: String, value: UUID)) -> Bool in
            sceneIDs.contains(entry.key) && folders[entry.value] != nil
        }
        return before - assignments.count
    }

    /// Builds a tree from stored entries, accepting what satisfies every rule (research SCN-004-D4).
    /// Returns the tree and the numbers of folders and assignments dropped.
    public static func repaired(folders entries: [(id: String, name: String, parent: String?)],
                                assignments stored: [String: String],
                                sceneIDs: Set<String>) -> (tree: SceneFolderTree, droppedFolders: Int, droppedAssignments: Int) {
        var tree = SceneFolderTree()
        var pending: [(id: UUID, name: String, parent: UUID?)] = []
        var dropped = 0
        var seen = Set<UUID>()
        for entry in entries {
            guard let id = canonicalUUID(entry.id), seen.insert(id).inserted, let name = normalizedName(entry.name), name == entry.name else {
                dropped += 1
                continue
            }
            var parent: UUID?
            if let text = entry.parent {
                guard let parentID = canonicalUUID(text) else { dropped += 1; continue }
                parent = parentID
            }
            pending.append((id, name, parent))
        }
        var progress = true
        while progress && !pending.isEmpty {
            progress = false
            var rest: [(id: UUID, name: String, parent: UUID?)] = []
            for item in pending {
                if let parent = item.parent, tree.folders[parent] == nil {
                    rest.append(item)
                    continue
                }
                if (try? tree.createFolder(named: item.name, in: item.parent, id: item.id)) != nil {
                    progress = true
                } else {
                    dropped += 1
                }
            }
            pending = rest
        }
        dropped += pending.count   // unknown parents and cycles
        var droppedAssignments = 0
        for (scene, folderText) in stored {
            guard sceneIDs.contains(scene), let folder = canonicalUUID(folderText), tree.folders[folder] != nil else {
                droppedAssignments += 1
                continue
            }
            tree.assignments[scene] = folder
        }
        return (tree, dropped, droppedAssignments)
    }

    private static func canonicalUUID(_ text: String) -> UUID? {
        guard let id = UUID(uuidString: text), id.uuidString == text else { return nil }
        return id
    }
}
