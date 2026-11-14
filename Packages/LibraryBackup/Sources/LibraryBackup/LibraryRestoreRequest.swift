// LibraryRestoreRequest.swift — FILE-005 contract C6 (FILE-005-R6; research FILE-005-D3): a restore
// takes effect at the next launch, before any store reads the library.
//
//   LibraryRestore/pending/backup.pmbackup   the picked backup (a copy)
//   LibraryRestore/pending/request.json      {"schemaVersion":1,"choice":"keepBoth","backupSHA256":"…"}
//   LibraryRestore/last-result.json          {"restored":true,"message":"…"} — read once by the screen
//
// `LibraryRestoreLaunch.run` recovers an interrupted restore, then installs a pending request (the
// backup is read and the library planned again with the recorded choice) and records the result. The
// request is removed in every case, so a failing backup never blocks a launch twice.
import Foundation
import LocalPortability

public struct LibraryRestoreRequest: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var choice: LibraryRestoreChoice
    public var backupSHA256: String

    public init(choice: LibraryRestoreChoice, backupSHA256: String) {
        self.choice = choice
        self.backupSHA256 = backupSHA256
    }
}

public struct LibraryRestoreResultNote: Codable, Sendable, Equatable {
    public var restored: Bool
    public var message: String

    public init(restored: Bool, message: String) {
        self.restored = restored
        self.message = message
    }
}

public struct LibraryRestoreRequestStore: Sendable {
    public let folders: LibraryFolders

    public init(folders: LibraryFolders) {
        self.folders = folders
    }

    var pendingFolder: URL { folders.restore.appendingPathComponent("pending", isDirectory: true) }
    var backupFile: URL { pendingFolder.appendingPathComponent("backup." + LibraryBackupFormat.fileExtension, isDirectory: false) }
    var requestFile: URL { pendingFolder.appendingPathComponent("request.json", isDirectory: false) }
    var resultFile: URL { folders.restore.appendingPathComponent("last-result.json", isDirectory: false) }

    /// Records a restore for the next launch (the backup first, the request last).
    public func save(backup: Data, choice: LibraryRestoreChoice) throws {
        cancel()
        try FileManager.default.createDirectory(at: pendingFolder, withIntermediateDirectories: true)
        try backup.write(to: backupFile, options: .atomic)
        let request = LibraryRestoreRequest(choice: choice, backupSHA256: PortableSHA256.hex(backup))
        try JSONEncoder().encode(request).write(to: requestFile, options: .atomic)
    }

    public var pending: LibraryRestoreRequest? {
        guard let data = try? Data(contentsOf: requestFile) else { return nil }
        return try? JSONDecoder().decode(LibraryRestoreRequest.self, from: data)
    }

    /// Removes the request; nothing else changes.
    public func cancel() {
        try? FileManager.default.removeItem(at: pendingFolder)
    }

    func pendingBackup() -> Data? { try? Data(contentsOf: backupFile) }

    func record(_ note: LibraryRestoreResultNote) {
        try? FileManager.default.createDirectory(at: folders.restore, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(note) { try? data.write(to: resultFile, options: .atomic) }
    }

    /// The last launch-time result, once (it is removed when read).
    public func takeResult() -> LibraryRestoreResultNote? {
        guard let data = try? Data(contentsOf: resultFile) else { return nil }
        try? FileManager.default.removeItem(at: resultFile)
        return try? JSONDecoder().decode(LibraryRestoreResultNote.self, from: data)
    }
}

public enum LibraryRestoreLaunch {
    /// Call before any store reads the library. Returns the note it recorded, if any.
    @discardableResult
    public static func run(folders: LibraryFolders, settings: [String: LibrarySettingValue],
                           applySettings: ([String: LibrarySettingValue]) -> Void) -> LibraryRestoreResultNote? {
        let installer = LibraryRestoreInstaller(folders: folders)
        let store = LibraryRestoreRequestStore(folders: folders)
        installer.recover(applySettings: applySettings)
        guard let request = store.pending else {
            if FileManager.default.fileExists(atPath: store.pendingFolder.path) { store.cancel() }
            return nil
        }
        defer { store.cancel() }
        let note = install(request, store: store, installer: installer, settings: settings, applySettings: applySettings)
        store.record(note)
        return note
    }

    private static func install(_ request: LibraryRestoreRequest, store: LibraryRestoreRequestStore, installer: LibraryRestoreInstaller,
                                settings: [String: LibrarySettingValue],
                                applySettings: ([String: LibrarySettingValue]) -> Void) -> LibraryRestoreResultNote {
        guard let data = store.pendingBackup(), PortableSHA256.hex(data) == request.backupSHA256 else {
            return LibraryRestoreResultNote(restored: false, message: LibraryRestoreText.failed)
        }
        let backup: LibraryBackupContents
        do {
            backup = try LibraryBackupReader.read(data)
        } catch {
            return LibraryRestoreResultNote(restored: false, message: error.message + " Nothing was changed.")
        }
        let library: LibraryContents
        do {
            library = try LibraryContentsReader.read(folders: folders(of: installer), settings: settings)
        } catch {
            return LibraryRestoreResultNote(restored: false, message: error.message + " Nothing was changed.")
        }
        let plan = LibraryRestorePlanner.plan(backup: backup.contents, library: library, choice: request.choice)
        switch installer.install(backup: backup.contents, plan: plan, settings: settings, applySettings: applySettings) {
        case let .restored(summary): return LibraryRestoreResultNote(restored: true, message: summary.message)
        case .changed: return LibraryRestoreResultNote(restored: false, message: LibraryRestoreText.failed)
        case let .refused(text):
            if text == LibraryRestoreText.nothingToRestore { return LibraryRestoreResultNote(restored: true, message: text) }
            return LibraryRestoreResultNote(restored: false, message: text == LibraryRestoreText.failed ? text : text + " Nothing was changed.")
        }
    }

    private static func folders(of installer: LibraryRestoreInstaller) -> LibraryFolders { installer.folders }
}
