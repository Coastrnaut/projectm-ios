// RecordingLibraryStore.swift — REC-010 (spec specs/198-rec-010-recording-library, contract C1, C2, C5; research
// REC-010-D1 to D3, D7): the kept recordings in `Application Support/RecordingLibrary`.
//
// * The folder is the only record: `scan()` lists its non-hidden regular files (no index), newest first by
//   modification date (a timestamp of a file inside the container, declared reason C617.1), then by name.
// * `keep` moves an offered temporary recording in (a rename on one volume), "<stem> 2.mp4" on a collision.
// * `delete` and `rename` act on one file; `validate` holds the rename rules and their texts.
// No networking; nothing leaves the container here.
import Foundation

/// One file of the library (data model: RecordingLibraryFile).
struct RecordingLibraryFile: Sendable, Equatable, Hashable, Identifiable {
    let url: URL
    let bytes: Int64
    let date: Date

    var name: String { url.lastPathComponent }
    var id: String { name }
    /// The thumbnail cache key: a rename or a changed file makes a new entry.
    var cacheKey: String { "\(name).\(bytes)" }

    /// Newest first, then by name (descending) for equal dates.
    static func newestFirst(_ a: RecordingLibraryFile, _ b: RecordingLibraryFile) -> Bool {
        if a.date != b.date { return a.date > b.date }
        return a.name > b.name
    }
}

/// Why a new name was refused (research REC-010-D7).
enum RecordingRenameError: Error, Equatable {
    case empty, forbiddenCharacter, leadingDot, tooLong, taken

    var message: String {
        switch self {
        case .empty: "Enter a name."
        case .forbiddenCharacter: "Names can't contain / or :."
        case .leadingDot: "Names can't start with a dot."
        case .tooLong: "Use at most 100 characters."
        case .taken: "A recording with that name exists."
        }
    }
}

struct RecordingLibraryStore: Sendable, Equatable {
    /// `Application Support/RecordingLibrary` (FILE-011 `LibraryErasePolicy.recordingLibraryFolderName`).
    static let folderName = "RecordingLibrary"
    static let maxNameLength = 100

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// The real folder. Creates nothing.
    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent(folderName, isDirectory: true)
    }

    static func standard() -> RecordingLibraryStore { RecordingLibraryStore(directory: defaultDirectory) }

    /// The non-hidden regular files, newest first. A missing folder is an empty library.
    func scan() -> [RecordingLibraryFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles])) ?? []
        var files: [RecordingLibraryFile] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let bytes = Int64(values.fileSize ?? 0)
            files.append(RecordingLibraryFile(url: url, bytes: bytes, date: values.contentModificationDate ?? .distantPast))
        }
        return files.sorted(by: RecordingLibraryFile.newestFirst)
    }

    /// Moves `file` into the library under its own name, or "<stem> 2.<ext>", "<stem> 3.<ext>"… when taken.
    func keep(_ file: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = uniqueURL(for: file.lastPathComponent)
        try FileManager.default.moveItem(at: file, to: destination)
        return destination
    }

    func uniqueURL(for name: String) -> URL {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name, isDirectory: false)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
            candidate = directory.appendingPathComponent(next, isDirectory: false)
            number += 1
        }
        return candidate
    }

    /// Removes the file; one that is already gone counts as removed.
    func delete(_ file: RecordingLibraryFile) throws {
        do {
            try FileManager.default.removeItem(at: file.url)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    /// The stem the user typed, trimmed and checked; the file keeps its extension.
    func validate(name proposed: String, excluding file: RecordingLibraryFile) -> Result<String, RecordingRenameError> {
        let stem = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.isEmpty { return .failure(.empty) }
        if stem.contains("/") || stem.contains(":") { return .failure(.forbiddenCharacter) }
        if stem.hasPrefix(".") { return .failure(.leadingDot) }
        if stem.count > Self.maxNameLength { return .failure(.tooLong) }
        let newName = Self.fileName(stem: stem, extensionOf: file.name)
        let taken = scan().contains { (other: RecordingLibraryFile) -> Bool in
            other.name != file.name && other.name.caseInsensitiveCompare(newName) == .orderedSame
        }
        return taken ? .failure(.taken) : .success(newName)
    }

    /// Renames the file to a validated name (same folder); returns the new URL.
    func rename(_ file: RecordingLibraryFile, to proposed: String) throws -> URL {
        let newName = try validate(name: proposed, excluding: file).get()
        let destination = directory.appendingPathComponent(newName, isDirectory: false)
        guard destination.lastPathComponent != file.name else { return file.url }
        try FileManager.default.moveItem(at: file.url, to: destination)
        return destination
    }

    static func fileName(stem: String, extensionOf name: String) -> String {
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// The name without its extension (the rename field's start text).
    static func stem(of name: String) -> String { (name as NSString).deletingPathExtension }
}
