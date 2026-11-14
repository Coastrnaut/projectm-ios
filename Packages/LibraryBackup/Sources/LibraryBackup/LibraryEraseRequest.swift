// LibraryEraseRequest.swift — FILE-011 contract E6 (FILE-011-R3, R6; research FILE-011-D1): an erase
// takes effect at the next launch, before any store reads the library, so nothing the running app holds
// in memory can write erased data back.
//
//   LibraryErase/request.json       {"schemaVersion":1,"categories":["scenes","media"]}
//   LibraryErase/last-result.json   {"erased":true,"message":"Erased: …"} — read once by the screen
//
// `LibraryEraseLaunch.run` recovers an interrupted erase (a prepared one is rolled back, a committed one
// finished), then runs a pending request once and records the result. The request is removed after
// the attempt, so a failing erase never blocks a launch twice; a kill before the commit leaves it in
// place, and the next launch rolls back and runs it again from a consistent library.
import Foundation

public struct LibraryEraseRequest: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var schemaVersion: Int
    public var categories: [String]

    public init(categories: Set<LibraryEraseCategory>) {
        schemaVersion = Self.currentVersion
        self.categories = categories.sorted().map { (category: LibraryEraseCategory) -> String in category.rawValue }
    }

    /// Nil for a newer version, an unknown category or no category.
    public var chosen: Set<LibraryEraseCategory>? {
        guard schemaVersion == Self.currentVersion, !categories.isEmpty else { return nil }
        let parsed: [LibraryEraseCategory] = categories.compactMap { (name: String) -> LibraryEraseCategory? in LibraryEraseCategory(rawValue: name) }
        return parsed.count == categories.count ? Set(parsed) : nil
    }
}

public struct LibraryEraseResultNote: Codable, Sendable, Equatable {
    public var erased: Bool
    public var message: String

    public init(erased: Bool, message: String) {
        self.erased = erased
        self.message = message
    }
}

public struct LibraryEraseRequestStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    var workFolder: URL { root.appendingPathComponent(LibraryErasePolicy.workFolderName, isDirectory: true) }
    var requestFile: URL { workFolder.appendingPathComponent("request.json", isDirectory: false) }
    var resultFile: URL { workFolder.appendingPathComponent("last-result.json", isDirectory: false) }

    /// Records an erase for the next launch.
    public func save(_ categories: Set<LibraryEraseCategory>) throws {
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        try JSONEncoder().encode(LibraryEraseRequest(categories: categories)).write(to: requestFile, options: .atomic)
    }

    /// The pending request as written (it may name what this version does not know).
    public var pendingRequest: LibraryEraseRequest? {
        guard let data = try? Data(contentsOf: requestFile) else { return nil }
        return try? JSONDecoder().decode(LibraryEraseRequest.self, from: data)
    }

    public var hasPendingFile: Bool { FileManager.default.fileExists(atPath: requestFile.path) }

    /// The categories of a readable pending request.
    public var pending: Set<LibraryEraseCategory>? { pendingRequest?.chosen }

    /// Removes the request; nothing else changes.
    public func cancel() {
        try? FileManager.default.removeItem(at: requestFile)
        LibraryEraser(root: root).removeWorkFolderIfEmpty()
    }

    func record(_ note: LibraryEraseResultNote) {
        try? FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(note) { try? data.write(to: resultFile, options: .atomic) }
    }

    /// The last launch-time result, once (it is removed when read).
    public func takeResult() -> LibraryEraseResultNote? {
        guard let data = try? Data(contentsOf: resultFile) else { return nil }
        try? FileManager.default.removeItem(at: resultFile)
        LibraryEraser(root: root).removeWorkFolderIfEmpty()
        return try? JSONDecoder().decode(LibraryEraseResultNote.self, from: data)
    }
}

public enum LibraryEraseLaunch {
    /// Call before any store reads the library (and before a pending FILE-005 restore). `settings`: the
    /// app's current values of `LibraryErasePolicy.planningKeys`. Returns the note it recorded, if any.
    @discardableResult
    public static func run(root: URL, settings: [String: LibrarySettingValue], removeSettings: ([String]) -> Void,
                           configure: (LibraryEraser) -> Void = { (_: LibraryEraser) in }) -> LibraryEraseResultNote? {
        let eraser = LibraryEraser(root: root)
        configure(eraser)
        let store = LibraryEraseRequestStore(root: root)
        eraser.recover(removeSettings: removeSettings)
        guard store.hasPendingFile else { return nil }
        defer { store.cancel() }
        let note: LibraryEraseResultNote
        if let chosen = store.pending {
            let plan = LibraryErasePlanner.plan(chosen, root: root, settings: settings)
            switch eraser.run(plan, removeSettings: removeSettings) {
            case let .erased(categories): note = LibraryEraseResultNote(erased: true, message: LibraryEraseText.erased(categories))
            case .failed: note = LibraryEraseResultNote(erased: false, message: LibraryEraseText.failed)
            case let .refused(text): note = LibraryEraseResultNote(erased: false, message: text == LibraryEraseText.failed ? text : text + " Nothing was erased.")
            }
        } else {
            note = LibraryEraseResultNote(erased: false, message: LibraryEraseText.unreadable)
        }
        store.record(note)
        return note
    }
}
