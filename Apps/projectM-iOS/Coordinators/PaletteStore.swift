// PaletteStore.swift — UIX-011-R2 (research UIX-011-D4; contract P1): the palette library file
// `Library/Application Support/Palettes/palettes.json`.
//
// * Read at init: damaged entries are dropped and counted (`issue`); a file from a newer app version is kept untouched and
//   the store becomes read-only; a file that is not a palette file is set aside as `palettes.unreadable.json` and the
//   library starts empty (the user can still recover it by hand).
// * Every successful edit is saved at once (atomic write). Built-ins are never written.
// * The folder name is FILE-005's `LibraryFolders.Folder.palettes`, FILE-009's Scenes root and FILE-011's Scenes erase
//   folder (an app test checks they agree). `-uitestResetNotice` removes the folder.
import Foundation
import Observation
import SceneFormat

enum PaletteStoreIssue: Equatable, Sendable {
    case dropped(Int)
    case newerVersion
    case setAside
    case saveFailed

    var message: String {
        switch self {
        case let .dropped(count): count == 1 ? "1 damaged palette couldn't be read." : "\(count) damaged palettes couldn't be read."
        case .newerVersion: PaletteEditError.readOnly.message
        case .setAside: "The palette file couldn't be read and was set aside. Your palettes start empty."
        case .saveFailed: "Palettes couldn't be saved."
        }
    }
}

@MainActor
@Observable
final class PaletteStore {
    nonisolated static let folderName = PaletteFile.folderName
    nonisolated static let fileName = PaletteFile.fileName
    nonisolated static let setAsideName = "palettes.unreadable.json"

    @ObservationIgnored let directory: URL
    private(set) var library: PaletteLibrary
    private(set) var issue: PaletteStoreIssue?
    private(set) var isReadOnly = false

    var fileURL: URL { directory.appendingPathComponent(Self.fileName, isDirectory: false) }

    /// `Library/Application Support/Palettes`.
    nonisolated static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    init(directory: URL) {
        self.directory = directory
        library = PaletteLibrary()
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoded = try PaletteFile.decode([UInt8](data))
            library = decoded.library
            issue = decoded.dropped > 0 ? .dropped(decoded.dropped) : nil
        } catch .newerVersion {
            isReadOnly = true
            issue = .newerVersion
        } catch {
            let aside: URL = directory.appendingPathComponent(Self.setAsideName, isDirectory: false)
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            issue = .setAside
        }
    }

    /// Applies one edit and saves; returns the edit's error (nothing changes then).
    @discardableResult
    func edit(_ change: (inout PaletteLibrary) throws(PaletteEditError) -> Void) -> PaletteEditError? {
        guard !isReadOnly else { return .readOnly }
        var next: PaletteLibrary = library
        do {
            try change(&next)
        } catch {
            return error
        }
        guard next != library else { return nil }
        library = next
        save()
        return nil
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(PaletteFile.encode(library)).write(to: fileURL, options: .atomic)
            if issue == .saveFailed { issue = nil }
        } catch {
            issue = .saveFailed
        }
    }
}
